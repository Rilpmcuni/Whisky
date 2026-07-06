//
//  BottleVM+LauncherPreset.swift
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
import WhiskyKit

extension BottleVM {
    /// Applies a launcher preset to an existing bottle: mutates the bottle's
    /// settings via `LauncherDetection.applyLauncherFixes` (env vars, locale,
    /// DXVK, GPU spoofing, network timeouts, etc.) and then installs the
    /// winetricks verbs returned by `launcher.recommendedWinetricksVerbs()`.
    /// If the launcher defines an `autoInstallURL` (e.g. Epic Games), the
    /// installer is downloaded and run after the winetricks baseline is in
    /// place, mirroring the Steam/Ubisoft auto-install flow.
    func applyLauncherPreset(to bottle: Bottle, launcher: LauncherType) async {
        guard bottleSetupState?.bottleURL == bottle.url else { return }

        bottleSetupState?.phase = .applyingLauncherSettings(launcher)
        bottleSetupState?.logLines.append("Applying \(launcher.displayName) launcher settings…")
        LauncherDetection.applyLauncherFixes(for: bottle, launcher: launcher, force: true)

        let verbs = launcher.recommendedWinetricksVerbs()
        guard !verbs.isEmpty else {
            await installAutoInstallLauncher(for: bottle, launcher: launcher)
            bottleSetupState?.phase = .completed(launcher)
            return
        }

        bottleSetupState?.logLines.append("Installing \(verbs.count) winetricks dependencies…")
        let verbStream = Winetricks.installVerbs(verbs, for: bottle)
        for await (verb, progress) in verbStream {
            handleWinetricksProgress(progress, verb: verb, verbs: verbs)
        }

        // After the winetricks baseline is done, optionally download + run the
        // launcher's own installer (e.g. Epic Games Launcher .msi).
        await installAutoInstallLauncher(for: bottle, launcher: launcher)

        bottleSetupState?.phase = .completed(launcher)
        bottleSetupState?.logLines.append("\(launcher.displayName) bottle is ready.")
    }

    /// When `launcher.autoInstallURL` is non-nil, downloads the installer to
    /// a temp path and runs it in Wine (`msiexec /i` for .msi, `wine` for .exe).
    /// This brings Epic Games Launcher (and any future launcher without an
    /// official winetricks verb) to feature parity with Steam/Ubisoft.
    private func installAutoInstallLauncher(for bottle: Bottle, launcher: LauncherType) async {
        guard let url = launcher.autoInstallURL else { return }

        bottleSetupState?.logLines.append("Downloading \(launcher.displayName) installer…")
        bottleSetupState?.phase = .installingDependencies(verb: launcher.displayName)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisky-launcher-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            bottleSetupState?.logLines.append("✗ Could not create temp dir: \(error.localizedDescription)")
            return
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Download the installer.
        let installerURL: URL
        if url.pathExtension.lowercased() == "msi" {
            installerURL = tempDir.appendingPathComponent("EpicGamesLauncherInstaller.msi")
        } else {
            installerURL = tempDir.appendingPathComponent("launcherInstaller.exe")
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: installerURL)
            let kilobytes = data.count / 1024
            bottleSetupState?.logLines.append(
                "✓ Downloaded \(launcher.displayName) installer (\(kilobytes) KB)"
            )
        } catch {
            bottleSetupState?.logLines.append(
                "✗ Failed to download \(launcher.displayName): \(error.localizedDescription)"
            )
            return
        }

        // Run it via Wine.
        bottleSetupState?.phase = .installingDependencies(verb: launcher.displayName)
        bottleSetupState?.logLines.append("Running \(launcher.displayName) installer in Wine…")

        let isMSI = url.pathExtension.lowercased() == "msi"
        await runInstallerInWine(
            installerURL: installerURL,
            bottle: bottle,
            isMSI: isMSI
        )

        bottleSetupState?.logLines.append("✓ \(launcher.displayName) installer completed")
    }

    /// Runs a downloaded installer inside the bottle's Wine prefix.
    /// Uses `msiexec /i` for .msi files, plain `wine` for .exe files.
    private func runInstallerInWine(installerURL: URL, bottle: Bottle, isMSI: Bool) async {
        let process = makeInstallerProcess(
            installerURL: installerURL,
            bottle: bottle,
            isMSI: isMSI
        )
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            bottleSetupState?.logLines.append(
                "✗ Failed to launch installer: \(error.localizedDescription)"
            )
            return
        }

        attachInstallerOutputHandlers(stdout: stdout, stderr: stderr)

        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }

    /// Builds the `Process` for invoking a launcher installer in Wine.
    private func makeInstallerProcess(
        installerURL: URL,
        bottle: Bottle,
        isMSI: Bool
    ) -> Process {
        let wineExecutable = WhiskyWineInstaller.binFolder.appendingPathComponent("wine64")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = isMSI
            ? [wineExecutable.path, "msiexec", "/i", installerURL.path, "/qn"]
            : [wineExecutable.path, installerURL.path, "/S"]

        process.environment = [
            "WINEPREFIX": bottle.url.path(percentEncoded: false),
            "WINE": "wine64",
            "PATH": [
                WhiskyWineInstaller.binFolder.path(percentEncoded: false),
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin"
            ].joined(separator: ":"),
            "HOME": NSHomeDirectory(),
            "WINEDEBUG": "fixme-all"
        ]
        return process
    }

    /// Streams installer stdout/stderr lines as `bottleSetupState` log entries.
    private func attachInstallerOutputHandlers(stdout: Pipe, stderr: Pipe) {
        let stdoutQueue = DispatchQueue(label: "whisky.installer.stdout")
        let stdoutSem = DispatchSemaphore(value: 0)
        let stderrSem = DispatchSemaphore(value: 0)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { stdoutSem.signal(); return }
            if let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty {
                stdoutQueue.async {
                    self.bottleSetupState?.logLines.append(line)
                }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { stderrSem.signal(); return }
            if let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty {
                stdoutQueue.async {
                    self.bottleSetupState?.logLines.append(line)
                }
            }
        }
    }

    /// Maps a single `WinetricksInstallProgress` event to a `bottleSetupState`
    /// mutation (phase + log line + verb counter).
    private func handleWinetricksProgress(
        _ progress: WinetricksInstallProgress,
        verb: String,
        verbs: [String]
    ) {
        let advanceIndex = { [weak self] in
            if let idx = verbs.firstIndex(of: verb) {
                self?.bottleSetupState?.currentVerbIndex = idx + 1
            }
        }

        switch progress {
        case .preparing:
            bottleSetupState?.phase = .installingDependencies(verb: verb)
            bottleSetupState?.logLines.append("→ Preparing \(verb)…")
        case let .output(line):
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { bottleSetupState?.logLines.append(trimmed) }
        case let .completed(exitCode) where exitCode == 0:
            advanceIndex()
            bottleSetupState?.logLines.append("✓ \(verb) installed")
        case let .completed(exitCode):
            advanceIndex()
            bottleSetupState?.logLines.append("⚠ \(verb) exited with code \(exitCode)")
        case let .failed(message):
            advanceIndex()
            bottleSetupState?.logLines.append("✗ \(verb) failed: \(message)")
        }
    }
}
