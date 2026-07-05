//
//  BottleCreationView.swift
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
import WhiskyKit

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
        ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false
    /// Selected launcher preset; `nil` means a plain custom bottle.
    @State private var selectedLauncher: LauncherType?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                launcherTabBar

                Form {
                    TextField("create.name", text: $newBottleName)
                        .onChange(of: newBottleName) { _, name in
                            nameValid = !name.isEmpty
                        }
                        .accessibilityIdentifier("create.nameField")

                    Picker("create.win", selection: $newBottleVersion) {
                        ForEach(WinVersion.allCases.reversed(), id: \.self) {
                            Text($0.pretty())
                        }
                    }

                    ActionView(
                        text: "create.path",
                        subtitle: newBottleURL.prettyPath(),
                        actionName: "create.browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = BottleData.containerDir
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                newBottleURL = url
                            }
                        }
                    }

                    if let launcher = selectedLauncher {
                        launcherInfoSection(for: launcher)
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("create.cancelButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid)
                    .accessibilityIdentifier("create.createButton")
                }
            }
            .onSubmit {
                submit()
            }
            .onChange(of: selectedLauncher) { _, launcher in
                // Auto-default the bottle name to the launcher's display name
                // when the user picks a preset and hasn't typed anything yet.
                if let launcher, newBottleName.isEmpty {
                    newBottleName = launcher.displayName
                    nameValid = true
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
    }

    /// Top bar with "Personalizada" + one tab per launcher.
    private var launcherTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                launcherTab(.none, label: "Personalizada")
                ForEach(LauncherType.allCases) { launcher in
                    launcherTab(launcher, label: launcher.displayName)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }

    /// Single segmented-style tab button for either "Personalizada" (`nil`)
    /// or a specific launcher preset.
    private func launcherTab(_ launcher: LauncherType?, label: String) -> some View {
        let isSelected = (selectedLauncher?.id ?? "") == (launcher?.id ?? "")
        return Button {
            selectedLauncher = launcher
            if launcher == nil { newBottleName = ""; nameValid = false }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Per-launcher info section shown inside the form when a preset is active.
    @ViewBuilder
    private func launcherInfoSection(for launcher: LauncherType) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(launcher.fixesDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if launcher.supportsAutoInstall {
                    Label(
                        "Installará automáticamente: \(launcher.displayName)",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Deberás instalar \(launcher.displayName) manualmente tras la bottle",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                DisclosureGroup("Dependencias (\(launcher.recommendedWinetricksVerbs().count))") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(launcher.recommendedWinetricksVerbs(), id: \.self) { verb in
                            Text("• \(verb)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        } header: {
            Text("Preset: \(launcher.displayName)")
        }
    }

    func submit() {
        newlyCreatedBottleURL = BottleVM.shared.createNewBottle(
            bottleName: newBottleName,
            winVersion: newBottleVersion,
            bottleURL: newBottleURL,
            launcherPreset: selectedLauncher
        )
        dismiss()
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
