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
    func applyLauncherPreset(to bottle: Bottle, launcher: LauncherType) async {
        guard bottleSetupState?.bottleURL == bottle.url else { return }

        bottleSetupState?.phase = .applyingLauncherSettings(launcher)
        bottleSetupState?.logLines.append("Applying \(launcher.displayName) launcher settings…")
        LauncherDetection.applyLauncherFixes(for: bottle, launcher: launcher, force: true)

        let verbs = launcher.recommendedWinetricksVerbs()
        guard !verbs.isEmpty else {
            bottleSetupState?.phase = .completed(launcher)
            return
        }

        bottleSetupState?.logLines.append("Installing \(verbs.count) winetricks dependencies…")
        let verbStream = Winetricks.installVerbs(verbs, for: bottle)
        for await (verb, progress) in verbStream {
            handleWinetricksProgress(progress, verb: verb, verbs: verbs)
        }

        bottleSetupState?.phase = .completed(launcher)
        bottleSetupState?.logLines.append("\(launcher.displayName) bottle is ready.")
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
