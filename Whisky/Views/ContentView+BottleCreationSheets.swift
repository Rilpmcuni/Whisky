//
//  ContentView+BottleCreationSheets.swift
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

import SwiftUI

/// Bundles all bottle-creation-related sheets (creation form, setup
/// progress, first-time setup) so that `ContentView` stays under SwiftLint's
/// type body length limit.
struct BottleCreationSheetsModifier: ViewModifier {
    @Binding var showBottleCreation: Bool
    @Binding var showSetup: Bool
    @Binding var newlyCreatedBottleURL: URL?
    let setupSheetBinding: Binding<Bool>

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showBottleCreation) {
                BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
            }
            .sheet(isPresented: setupSheetBinding) {
                BottleSetupProgressSheet(isPresented: setupSheetBinding)
            }
            .sheet(isPresented: $showSetup) {
                SetupView(showSetup: $showSetup, firstTime: false)
            }
    }
}
