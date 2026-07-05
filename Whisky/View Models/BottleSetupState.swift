//
//  BottleSetupState.swift
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

/// One phase of the bottle setup pipeline.
enum BottleSetupPhase: Equatable, Sendable {
    case creatingPrefix
    case applyingLauncherSettings(LauncherType)
    case installingDependencies(verb: String)
    case completed(LauncherType)
    case failed(message: String)
}

/// Live progress of a bottle creation + optional launcher-preset setup.
struct BottleSetupState: Identifiable, Equatable, Sendable {
    let id = UUID()
    let bottleURL: URL
    let bottleName: String
    var phase: BottleSetupPhase
    /// Cumulative log captured from winetricks stdout/stderr.
    var logLines: [String]
    /// Index of the verb currently being installed, when in `installingDependencies`.
    var currentVerbIndex: Int
    /// Total number of verbs queued for installation (0 if none).
    var totalVerbs: Int

    static func == (lhs: BottleSetupState, rhs: BottleSetupState) -> Bool {
        lhs.id == rhs.id
    }
}
