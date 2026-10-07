//
//  ControlPanelView.swift
//  CosmicPathSwift
//
//  Simulation controls: start/pause, reset, the 2-Body | 3-Body mode switch,
//  black hole mode toggle, and parameter sliders for mass, separation, and
//  orbital inclination (3-body parameters live in ThreeBodyControlsView).
//
//  ## Inclination Slider
//
//  The inclination slider (0° – 90°) sets the tilt of the orbital plane
//  relative to the default x-y plane. At 0° the orbit is flat (original 2D
//  behaviour). At 90° the orbit is polar. Changes trigger `applyConfigChange`
//  which restarts the simulation with the updated 3D initial conditions.
//
//  To appreciate an inclined orbit, drag the canvas to rotate the camera
//  (horizontal drag = azimuth, vertical drag = elevation).
//

import SwiftUI

/// Control panel providing simulation playback buttons and parameter sliders.
///
/// ## Layout Modes
///
/// - `showParameterControls = true` (portrait): Shows the mode switch, then either
///   the black hole toggle and 2-body sliders or the 3-body preset controls.
/// - `showParameterControls = false` (landscape): Shows only play/pause and
///   reset buttons to maximize canvas space.
///
/// ## Slider Behavior
///
/// Sliders use a logarithmic scale so that the default value (1.0) sits at the
/// visual center of the slider. Each slider change triggers `applyConfigChange`
/// which reinitializes the simulation with the new parameters.
///
/// ## Black Hole Mode Toggle
///
/// Switching to black hole mode resets the mass and separation to defaults
/// appropriate for visible event horizon effects (see `CelestialConstants`).
struct ControlPanelView: View {
    @Bindable var viewModel: SimulationViewModel
    let canvasSize: CGSize
    /// When false, hides the black hole toggle and parameter sliders (landscape mode).
    var showParameterControls: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            // Play/Pause, Reset simulation, and Reset Camera buttons
            HStack(spacing: 12) {
                Button {
                    if viewModel.isRunning {
                        viewModel.pause()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Label(
                        viewModel.isRunning ? "Pause" : "Start",
                        systemImage: viewModel.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .orange : .green)

                Button {
                    viewModel.reset(canvasSize: canvasSize)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(.gray)

                // Restores the camera to its default azimuth=0°, elevation=30° view.
                // Useful after dragging the orbit to an awkward angle.
                Button {
                    viewModel.resetCamera()
                } label: {
                    Image(systemName: "video.badge.ellipsis")
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Reset Camera")
            }

            // Mode switch and parameters (portrait only)
            if showParameterControls {
                modePicker

                if viewModel.isThreeBodyMode {
                    ThreeBodyControlsView(viewModel: viewModel, canvasSize: canvasSize)
                } else {
                    twoBodyControls
                }

                if viewModel.isRunning {
                    runningHint
                }
            }
        }
    }

    // MARK: - Mode Picker

    /// Segmented 2-Body | 3-Body switch. Disabled while running, like the other toggles.
    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            ForEach(SimulationMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.5 : 1.0)
    }

    private var modeBinding: Binding<SimulationMode> {
        Binding(
            get: { viewModel.config.mode },
            set: { viewModel.selectMode($0, canvasSize: canvasSize) }
        )
    }

    // MARK: - Two-Body Controls

    /// Black hole toggle plus mass, distance, and inclination sliders.
    @ViewBuilder
    private var twoBodyControls: some View {
        Toggle(isOn: $viewModel.config.isBlackHoleMode) {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(viewModel.config.isBlackHoleMode ? .red : .gray)
                    .font(.system(size: 8))
                Text("Black Hole Mode")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .toggleStyle(.switch)
        .tint(.red)
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.5 : 1.0)
        .onChange(of: viewModel.config.isBlackHoleMode) { _, isBlackHole in
            if isBlackHole {
                viewModel.config.mass1Multiplier = 1.0
                viewModel.config.separationAU = 1.3
            } else {
                viewModel.config.mass1Multiplier = 1.0
                viewModel.config.separationAU = 1.0
            }
            // Always reset inclination when switching mode so the user
            // starts from a flat orbit and can appreciate BH effects before
            // adding 3D complexity.
            viewModel.config.inclinationDeg = 0.0
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }

        // Parameter sliders (mass/distance use log scale; inclination uses linear)
        VStack(spacing: 8) {
            LogSlider(
                label: viewModel.config.isBlackHoleMode ? "BH Mass" : "Star Mass",
                value: $viewModel.config.mass1Multiplier,
                range: 0.1...10,
                color: viewModel.config.isBlackHoleMode ? .red : .orange,
                displayText: viewModel.config.mass1Label
            )
            LogSlider(
                label: "Planet Mass",
                value: $viewModel.config.mass2Multiplier,
                range: 0.1...10,
                color: .cyan,
                displayText: viewModel.config.mass2Label
            )
            LogSlider(
                label: "Distance",
                value: $viewModel.config.separationAU,
                range: (1.0 / 3.0)...3.0,
                color: .white,
                displayText: viewModel.config.separationLabel
            )

            // Inclination: linear 0°–90° slider.
            // Tilts the orbital plane out of the x-y plane. Drag the
            // canvas to rotate the camera and see the 3D structure.
            HStack {
                Text("Inclination")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 90, alignment: .leading)
                Slider(value: $viewModel.config.inclinationDeg, in: 0...90)
                    .tint(.purple)
                Text(viewModel.config.inclinationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.5 : 1.0)
        .onChange(of: viewModel.config.mass1Multiplier) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.mass2Multiplier) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.separationAU) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.inclinationDeg) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
    }

    // MARK: - Running Hint

    private var runningHint: some View {
        let isAbsorbed = !viewModel.isThreeBodyMode && viewModel.metrics.isAbsorbed
        return Text(isAbsorbed
            ? (viewModel.metrics.isBlackHole ? "Object crossed the event horizon" : "Planet collided with the star")
            : "Pause to adjust parameters")
            .font(.caption2)
            .foregroundStyle(isAbsorbed ? .red.opacity(0.7) : .white.opacity(0.4))
    }
}
