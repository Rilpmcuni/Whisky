//
//  Winetricks.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import AppKit
import Foundation
import os
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "Winetricks")

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    /// Path to the winetricks binary to use. Prefers the one shipped in the
    /// Whisky runtime folder; if missing (e.g. dev builds that didn't package
    /// it), falls back to a system install (Homebrew at
    /// `/opt/homebrew/bin/winetricks`, or anywhere in PATH).
    static let winetricksURL: URL = {
        let bundled = WhiskyWineInstaller.libraryFolder.appending(path: "winetricks")
        if FileManager.default.isExecutableFile(atPath: bundled.path(percentEncoded: false)) {
            return bundled
        }
        // Fall back to Homebrew's winetricks (installed via `brew install winetricks`).
        let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin/winetricks")
        if FileManager.default.isExecutableFile(atPath: homebrew.path(percentEncoded: false)) {
            return homebrew
        }
        // Last resort: search PATH via /usr/bin/env.
        if let resolved = findInPath("winetricks") {
            return resolved
        }
        // Default to the bundled path so error messages stay consistent
        // (and surface the absence to the user when they try to install).
        return bundled
    }()

    /// Locates an executable in `$PATH` via `/usr/bin/which`. Returns its URL
    /// when found, `nil` otherwise.
    private static func findInPath(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    @MainActor
    static func runCommand(command: String, bottle: Bottle) async {
        await runCommandInternal(command: command, bottle: bottle, isRetryAfterRepair: false)
    }

    @MainActor
    private static func runCommandInternal(command: String, bottle: Bottle, isRetryAfterRepair: Bool) async {
        // Pre-flight validation: check that the Wine prefix has required user directories
        let validationResult = WinePrefixValidation.validatePrefix(for: bottle)

        if !validationResult.isValid {
            logger.warning("Prefix validation failed before running winetricks '\(command)'")
            // Don't offer repair again if this is already a retry after repair
            if isRetryAfterRepair {
                logger.error("Validation still failing after repair attempt")
                let alert = NSAlert()
                alert.messageText = String(localized: "winetricks.error.repairFailed")
                alert.informativeText = String(localized: "winetricks.error.repairFailedInfo")
                alert.alertStyle = .critical
                alert.addButton(withTitle: String(localized: "button.ok"))
                alert.runModal()
                return
            }
            await showPrefixErrorAlert(
                validationResult: validationResult,
                bottle: bottle,
                command: command
            )
            return
        }

        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent()
        else { return }
        // swiftlint:disable:next line_length
        let winetricksCmd = #"PATH=\"\#(WhiskyWineInstaller.binFolder.path):\#(resourcesURL.path(percentEncoded: false)):$PATH\" WINE=wine64 WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricksURL.path(percentEncoded: false))\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error {
                logger.error("AppleScript error: \(error)")
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    @MainActor
    private static func showPrefixErrorAlert(
        validationResult: WinePrefixValidation.ValidationResult,
        bottle: Bottle,
        command: String
    ) async {
        guard let diagnostics = validationResult.diagnostics else { return }

        let errorMessage: String
        switch validationResult {
        case .valid:
            return
        case .missingUserProfile:
            errorMessage = String(localized: "winetricks.error.missingUserProfile")
        case .missingAppData:
            errorMessage = String(localized: "winetricks.error.missingAppData")
        case .corruptedPrefix:
            errorMessage = String(localized: "winetricks.error.corruptedPrefix")
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "winetricks.error.prefixTitle")
        alert.informativeText = errorMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "winetricks.error.repairPrefix"))
        alert.addButton(withTitle: String(localized: "winetricks.error.copyDiagnostics"))
        alert.addButton(withTitle: String(localized: "button.cancel"))

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Repair prefix
            await repairPrefixAndRetry(bottle: bottle, command: command)
        case .alertSecondButtonReturn:
            // Copy diagnostics
            let report = diagnostics.reportString(error: errorMessage)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        default:
            break
        }
    }

    @MainActor
    private static func repairPrefixAndRetry(bottle: Bottle, command: String) async {
        defer {
            bottle.clearWineUsernameCache()
        }
        do {
            logger.info("Attempting to repair Wine prefix for bottle '\(bottle.settings.name)'")
            try await Wine.repairPrefix(bottle: bottle)
            logger.info("Prefix repair completed, retrying winetricks command")
            // Retry the original command - validation will be done by runCommandInternal
            // and will show an error if still invalid (without offering repair again)
            await runCommandInternal(command: command, bottle: bottle, isRetryAfterRepair: true)
        } catch {
            logger.error("Failed to repair prefix: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = String(localized: "winetricks.error.repairFailed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: String(localized: "button.ok"))
            alert.runModal()
        }
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        // Grab the verbs file
        let verbsURL = WhiskyWineInstaller.libraryFolder.appending(path: "verbs.txt")
        let verbs: String = await { () async -> String in
            do {
                let (data, _) = try await URLSession.shared.data(from: verbsURL)
                return String(data: data, encoding: .utf8) ?? String()
            } catch {
                return String()
            }
        }()

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(
                        category: cateogry,
                        verbs: []
                    )
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
