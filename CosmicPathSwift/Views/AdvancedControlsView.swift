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
/// Edits go straight into `viewModel.config.advanced`. Time, display and camera
/// options take effect immediately, even while the simulation is running. The settings are
/// kept across Reset; "Restore defaults" returns them to `AdvancedSettings()`.
struct AdvancedControlsView: View {
    @Bindable var viewModel: SimulationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                displaySection
                cameraSection
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

    // MARK: - Time & Integration

    private var timeSection: some View {
        Section {
            accuracyPicker
            speedPicker
            stepButton
        } header: {
            Text("Time & Integration")
        } footer: {
            Text("These apply immediately, even while running.")
        }
    }

    private var accuracyPicker: some View {
        captionedRow(
            "Accuracy",
            caption: "Size of each integration step relative to this scenario's own. Smaller is more accurate and uses more CPU; on-screen speed stays the same."
        ) {
            Picker("Accuracy", selection: $viewModel.config.advanced.time.timeStepMultiplier) {
                ForEach(TimeSettings.timeStepChoices, id: \.self) { value in
                    Text("×\(Self.fractionLabel(value))").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var speedPicker: some View {
        captionedRow(
            "Speed",
            caption: "How fast simulated time runs. Uses more steps per frame rather than larger steps, so accuracy is unchanged."
        ) {
            Picker("Speed", selection: $viewModel.config.advanced.time.timeSpeed) {
                ForEach(TimeSettings.timeSpeedChoices, id: \.self) { value in
                    Text("\(Self.fractionLabel(value))×").tag(value)
                }
            }
            .pickerStyle(.segmented)
            if viewModel.isSpeedLimited {
                Text("Limited by CPU at this accuracy")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var stepButton: some View {
        captionedRow("Step", caption: "Advance one frame while paused.") {
            Button("Step One Frame") { viewModel.stepFrame() }
                .disabled(viewModel.isRunning)
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            explainedToggle(
                "Spacetime Grid",
                isOn: $viewModel.config.advanced.display.showSpacetimeGrid,
                caption: "Background grid pulled toward each body. A visual aid only: the physics doesn't use it."
            )
            if viewModel.config.advanced.display.showSpacetimeGrid {
                warpSlider
            }
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
            trailLengthPicker
            explainedToggle(
                "Velocity Vectors",
                isOn: $viewModel.config.advanced.display.showVelocityVectors,
                caption: "Green arrow along each body's motion. On a circular orbit it's 0.3 × the radius long; faster bodies get longer arrows."
            )
            explainedToggle(
                "Acceleration Vectors",
                isOn: $viewModel.config.advanced.display.showAccelerationVectors,
                caption: "Pink arrow showing the total gravitational pull on each body, on the same scale as velocity for a circular orbit."
            )
        } header: {
            Text("Display")
        } footer: {
            Text("Display options change only what's drawn, and apply immediately.")
        }
    }

    private var warpSlider: some View {
        let strength = $viewModel.config.advanced.display.gridWarpStrength
        return captionedRow(
            "Grid Warp: ×\(String(format: "%.2g", strength.wrappedValue))",
            caption: "How strongly the grid is pulled toward the bodies. 0 gives a flat grid."
        ) {
            Slider(value: strength, in: DisplaySettings.gridWarpRange, step: 0.25)
        }
    }

    private var trailLengthPicker: some View {
        captionedRow(
            "Trail Length",
            caption: "How far back the orbit trails reach. Measured in simulated time, so speed and accuracy don't change it."
        ) {
            Picker("Trail Length", selection: $viewModel.config.advanced.display.trailLengthMultiplier) {
                ForEach(DisplaySettings.trailLengthChoices, id: \.self) { value in
                    Text(value == 0 ? "Off" : "\(Self.fractionLabel(value))×").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section {
            captionedRow("View", caption: "Top looks straight down on the orbit, Edge-on along it. Drag the canvas to rotate freely.") {
                HStack {
                    ForEach(CameraPreset.allCases, id: \.self) { preset in
                        Button(preset.displayName) { viewModel.applyCameraPreset(preset) }
                            .frame(maxWidth: .infinity)
                    }
                }
                // Bordered buttons get their own tap areas instead of sharing the row's.
                .buttonStyle(.bordered)
            }
            explainedToggle(
                "Lock Zoom",
                isOn: $viewModel.config.advanced.display.lockZoom,
                caption: "Keep the current scale instead of zooming to fit. Bodies can then leave the screen."
            )
        } header: {
            Text("Camera")
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

    /// A titled row with a caption, followed by its control.
    private func captionedRow<Content: View>(
        _ title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// "¼", "½" or a whole number, for the multiplier pickers.
    private static func fractionLabel(_ value: Double) -> String {
        switch value {
        case 0.25: return "¼"
        case 0.5: return "½"
        default: return String(format: "%g", value)
        }
    }

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
