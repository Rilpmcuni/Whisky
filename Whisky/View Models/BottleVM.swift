//
//  BottleVM.swift
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

import Foundation
import os.log
import SemanticVersion
import WhiskyKit

// MARK: - Bottle Setup State
//
// State types `BottleSetupPhase` and `BottleSetupState` (live progress of
// the optional launcher-preset post-creation steps) are defined in
// `BottleSetupState.swift` and surfaced via `BottleVM.bottleSetupState`.

private let bottleVMLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky",
    category: "BottleVM"
)

// MARK: - Bottle Creation Errors

enum BottleCreationError: LocalizedError {
    case directoryCreationFailed
    case metadataCreationFailed
    case wineVersionChangeFailed
    case persistenceSaveFailed
    /// The chosen location failed pre-flight validation. Carries the already
    /// localized, user-facing message (built at the throw site) since the alert
    /// displays `errorDescription` verbatim.
    case locationUnsuitable(message: String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            String(localized: "bottle.creation.error.directoryCreationFailed")
        case .metadataCreationFailed:
            String(localized: "bottle.creation.error.metadataCreationFailed")
        case .wineVersionChangeFailed:
            String(localized: "bottle.creation.error.wineVersionChangeFailed")
        case .persistenceSaveFailed:
            String(localized: "bottle.creation.error.persistenceSaveFailed")
        case let .locationUnsuitable(message):
            message
        }
    }
}

@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    @Published var bottleCreationAlert: BottleCreationAlert?
    /// Live progress of an in-flight bottle setup (prefix + optional launcher preset).
    /// `nil` when no preset pipeline is running (e.g. plain custom bottle).
    @Published var bottleSetupState: BottleSetupState?

    struct BottleCreationAlert: Identifiable {
        let id = UUID()
        let message: String
        let diagnostics: String
    }

    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        bottles.filter { $0.isAvailable == true }.count
    }

    /// Creates a new bottle. When `launcherPreset` is non-nil, the bottle is
    /// configured with the launcher's env-var preset and its required winetricks
    /// verbs are auto-installed after the wineboot prefix is initialized.
    func createNewBottle(
        bottleName: String,
        winVersion: WinVersion,
        bottleURL: URL,
        launcherPreset: LauncherType? = nil
    ) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        let request = BottleCreationRequest(
            bottleName: bottleName,
            winVersion: winVersion,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir,
            launcherPreset: launcherPreset
        )

        if let launcher = launcherPreset {
            bottleSetupState = BottleSetupState(
                bottleURL: newBottleDir,
                bottleName: bottleName,
                phase: .creatingPrefix,
                logLines: [],
                currentVerbIndex: 0,
                totalVerbs: launcher.recommendedWinetricksVerbs().count
            )
        }

        Task {
            await self.createBottleTask(request: request)
        }
        return newBottleDir
    }

    private struct BottleCreationRequest {
        let bottleName: String
        let winVersion: WinVersion
        let bottleURL: URL
        let newBottleDir: URL
        let launcherPreset: LauncherType?
    }

    private func createBottleTask(request: BottleCreationRequest) async {
        var bottle: Bottle?
        do {
            // Pre-flight the chosen location before creating anything, so an
            // unwritable or near-full destination surfaces a clear error up
            // front instead of a cryptic late wineboot failure (issue #61).
            switch BottleLocationValidation.validate(at: request.bottleURL) {
            case .valid:
                break
            case let .notWritable(path):
                throw BottleCreationError.locationUnsuitable(
                    message: String(format: String(localized: "bottle.creation.preflight.notWritable"), path)
                )
            case let .insufficientSpace(availableBytes, requiredBytes):
                throw BottleCreationError.locationUnsuitable(
                    message: String(
                        format: String(localized: "bottle.creation.preflight.insufficientSpace"),
                        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file),
                        ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
                    )
                )
            }

            try createBottleDirectory(at: request.newBottleDir)

            // Create bottle on main actor (since Bottle is @MainActor)
            let createdBottle = Bottle(bottleUrl: request.newBottleDir, inFlight: true)
            bottle = createdBottle
            bottles.append(createdBottle)

            // Configure bottle settings (all on MainActor)
            createdBottle.settings.windowsVersion = request.winVersion
            createdBottle.settings.name = request.bottleName

            // Wine operations are async and can run on background threads
            try await Wine.changeWinVersion(bottle: createdBottle, win: request.winVersion)
            let wineVer = try await Wine.wineVersion()
            createdBottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

            // Bootstrap host fonts so Unity titles render fallback glyphs correctly.
            BottleFontBootstrap.copySystemFonts(toPrefix: createdBottle.url)

            // Save settings
            createdBottle.saveBottleSettings()

            // Apply launcher preset (env vars + winetricks verbs) when requested.
            // Run after the prefix is bootstrapped so winetricks verbs find
            // a fully initialized Wine prefix.
            if let launcher = request.launcherPreset {
                await applyLauncherPreset(to: createdBottle, launcher: launcher)
                loadBottles()
            }

            persistBottleCreation(request: request)
            loadBottles()
            Telemetry.capture(.firstBottleCreated)
        } catch {
            handleBottleCreationFailure(error, request: request, bottle: bottle)
        }
    }
    // `applyLauncherPreset(to:launcher:)` and winetricks progress handling
    // live in `BottleVM+LauncherPreset.swift` to keep this file under SwiftLint
    // length limits.

    private func createBottleDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw BottleCreationError.directoryCreationFailed
        }
    }

    private func persistBottleCreation(request: BottleCreationRequest) {
        if !bottlesList.paths.contains(request.newBottleDir) {
            bottlesList.paths.append(request.newBottleDir)
        }
    }

    private func handleBottleCreationFailure(
        _ error: Error,
        request: BottleCreationRequest,
        bottle: Bottle?
    ) {
        let message = error.localizedDescription
        let diagnostics = makeBottleCreationDiagnostics(
            bottleName: request.bottleName,
            winVersion: request.winVersion,
            bottleURL: request.bottleURL,
            newBottleDir: request.newBottleDir,
            error: error
        )
        bottleVMLogger.error("Failed to create new bottle: \(message)")
        bottleVMLogger.error("\(diagnostics, privacy: .public)")
        bottleCreationAlert = BottleCreationAlert(
            message: message,
            diagnostics: diagnostics
        )

        // Clean up on failure
        if let bottle, let index = bottles.firstIndex(of: bottle) {
            bottles.remove(at: index)
        }
        try? FileManager.default.removeItem(at: request.newBottleDir)
    }
}
