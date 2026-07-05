//
//  BottleSetupProgressSheet.swift
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

/// Sheet shown while a bottle is being created and a launcher preset is being
/// applied (env vars + winetricks verb install pipeline). Observes
/// `BottleVM.bottleSetupState` for live progress.
struct BottleSetupProgressSheet: View {
    @ObservedObject private var bottleVM = BottleVM.shared
    /// Set to `true` by the host when the user dismisses the sheet (or it
    /// auto-dismisses when the phase reaches `.completed`).
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            headerView

            if let state = bottleVM.bottleSetupState {
                progressBarView(state: state)

                logView(state: state)

                HStack {
                    Spacer()
                    if case .completed = state.phase {
                        Button("Done") { isPresented = false }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else if case .failed = state.phase {
                        Button("Close") { isPresented = false }
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Text("No cierres Xcode ni Whisky…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .onChange(of: bottleVM.bottleSetupState?.phase) { _, phase in
            if case .completed = phase {
                // Auto-close 1.5s after completion so the user can read the
                // final "bottle is ready." log line.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isPresented = false
                }
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if let state = bottleVM.bottleSetupState {
            VStack(spacing: 4) {
                Image(systemName: phaseIcon(state.phase))
                    .font(.system(size: 32))
                    .foregroundStyle(phaseColor(state.phase))
                Text("Configurando \"\(state.bottleName)\"")
                    .font(.headline)
                Text(phaseLabel(state.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressBarView(state: BottleSetupState) -> some View {
        let progress: Double = {
            guard state.totalVerbs > 0 else { return 0.5 }
            return Double(state.currentVerbIndex) / Double(state.totalVerbs)
        }()
        return VStack(spacing: 4) {
            ProgressView(value: progress, total: 1.0)
            HStack {
                Text("\(state.currentVerbIndex) / \(state.totalVerbs) dependencias")
                    .font(.caption)
                Spacer()
                if state.totalVerbs > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func logView(state: BottleSetupState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.logLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onChange(of: state.logLines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Phase presentation helpers

    private func phaseIcon(_ phase: BottleSetupPhase) -> String {
        switch phase {
        case .creatingPrefix, .applyingLauncherSettings:
            "gearshape"
        case .installingDependencies:
            "arrow.down.circle"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func phaseColor(_ phase: BottleSetupPhase) -> Color {
        switch phase {
        case .creatingPrefix, .applyingLauncherSettings, .installingDependencies:
            .accentColor
        case .completed:
            .green
        case .failed:
            .red
        }
    }

    private func phaseLabel(_ phase: BottleSetupPhase) -> String {
        switch phase {
        case .creatingPrefix:
            "Inicializando Wine…"
        case let .applyingLauncherSettings(launcher):
            "Aplicando ajustes de \(launcher.displayName)…"
        case let .installingDependencies(verb):
            "Instalando \(verb)…"
        case let .completed(launcher):
            "¡Bottle de \(launcher.displayName) lista!"
        case let .failed(message):
            "Error: \(message)"
        }
    }
}
