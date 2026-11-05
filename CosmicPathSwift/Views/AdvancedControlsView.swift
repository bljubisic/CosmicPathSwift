//
//  AdvancedControlsView.swift
//  CosmicPathSwift
//
//  Sheet with options for experienced users (issue #20). Opened from the
//  "Advanced" button, which only appears once the user turns on
//  "Advanced Controls" in the control panel.
//

import SwiftUI

/// Advanced options, grouped by topic, each with a short explanation.
///
/// Edits go straight into `viewModel.config.advanced`. Display options take
/// effect immediately, even while the simulation is running. The settings are
/// kept across Reset; "Restore defaults" returns them to `AdvancedSettings()`.
struct AdvancedControlsView: View {
    @Bindable var viewModel: SimulationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                restoreSection
            }
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Medium detent leaves the canvas visible, so display changes can be seen as they're made.
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            explainedToggle(
                "Spacetime Grid",
                isOn: $viewModel.config.advanced.display.showSpacetimeGrid,
                caption: "Background grid pulled toward each body. A visual aid only: the physics doesn't use it."
            )
            explainedToggle(
                "Centre of Mass",
                isOn: $viewModel.config.advanced.display.showCenterOfMass,
                caption: "The point all bodies orbit. The view stays centred on it."
            )
            explainedToggle(
                "Relativistic Radii",
                isOn: $viewModel.config.advanced.display.showRelativisticRadii,
                caption: "Schwarzschild radius rₛ = 2GM/c² for every body. In black hole mode, also the photon sphere (1.5 rₛ) and the innermost stable circular orbit (3 rₛ)."
            )
        } header: {
            Text("Display")
        } footer: {
            Text("Display options change only what's drawn, and apply immediately.")
        }
    }

    // MARK: - Restore Defaults

    private var restoreSection: some View {
        Section {
            Button("Restore Defaults", role: .destructive) {
                viewModel.restoreAdvancedDefaults()
            }
            .disabled(viewModel.config.advanced == AdvancedSettings())
        } footer: {
            Text("Advanced settings are kept when you tap Reset. This returns all of them to their defaults.")
        }
    }

    // MARK: - Helpers

    /// A toggle with a one-line title and a caption explaining what it does.
    private func explainedToggle(_ title: String, isOn: Binding<Bool>, caption: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    AdvancedControlsView(viewModel: SimulationViewModel())
}
