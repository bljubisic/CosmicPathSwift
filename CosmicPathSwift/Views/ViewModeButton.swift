//
//  ViewModeButton.swift
//  CosmicPathSwift
//
//  Cycles the canvas through 2D → Split → 3D (issue #38). Works while
//  running: the mode is render-only.
//

import SwiftUI

struct ViewModeButton: View {
    enum Style {
        /// Bordered, for the paused control row.
        case bordered
        /// Plain title-size icon, for the floating row while running.
        case floating
    }

    let viewModel: SimulationViewModel
    var style: Style = .bordered

    private var mode: CanvasViewMode { viewModel.config.advanced.display.viewMode }

    var body: some View {
        switch style {
        case .bordered:
            button
                .buttonStyle(.bordered)
                .tint(.indigo)
        case .floating:
            button
                .font(.title2)
                .foregroundStyle(.indigo)
                .buttonStyle(.plain)
        }
    }

    private var button: some View {
        Button {
            viewModel.config.advanced.display.viewMode = mode.next
        } label: {
            Image(systemName: mode.systemImage)
        }
        .help("View: \(mode.displayName)")
        .accessibilityLabel("View: \(mode.displayName)")
        .accessibilityHint("Switches to \(mode.next.displayName)")
    }
}
