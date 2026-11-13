//
//  ControlPanelView.swift
//  CosmicPathSwift
//
//  Simulation controls: start/pause, reset, the 2-Body | 3-Body mode switch,
//  black hole mode toggle, habitable-zone toggle, and parameter sliders for
//  mass, separation, orbital inclination, and (BH mode) accretion rate
//  (3-body parameters live in ThreeBodyControlsView).
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
    /// Opens the Advanced sheet (owned by `ContentView`).
    var onShowAdvanced: () -> Void = {}

    /// Opt-in that reveals the Advanced button. Persisted across launches.
    @AppStorage(AdvancedSettings.optInStorageKey) private var isAdvancedEnabled = false

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

                if isAdvancedEnabled {
                    Button(action: onShowAdvanced) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .help("Advanced")
                    .accessibilityLabel("Advanced")
                }
            }

            // Mode switch and parameters (portrait only)
            if showParameterControls {
                modePicker

                if viewModel.isThreeBodyMode {
                    ThreeBodyControlsView(viewModel: viewModel, canvasSize: canvasSize)
                } else {
                    twoBodyControls
                }

                advancedOptInToggle

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

    /// Black hole toggle plus mass, distance, and inclination sliders. In the
    /// Realistic scale, Black Hole Mode swaps in the strong-field sliders.
    @ViewBuilder
    private var twoBodyControls: some View {
        blackHoleToggle
        habitableZoneToggle
        if viewModel.config.isStrongField {
            StrongFieldControlsView(viewModel: viewModel, canvasSize: canvasSize)
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.5 : 1.0)
        }
        parameterSliders
    }

    private var blackHoleToggle: some View {
        // The side effects run from the binding (user taps only), not from an
        // onChange on the config, so deep links and screenshot scenes that turn
        // Black Hole Mode on keep their own distances (#33).
        Toggle(isOn: Binding(
            get: { viewModel.config.isBlackHoleMode },
            set: { viewModel.setBlackHoleMode($0, canvasSize: canvasSize) }
        )) {
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
    }

    /// Mass and distance use a log scale; inclination is linear. In strong
    /// field only inclination is shown (`StrongFieldControlsView` has the rest).
    private var parameterSliders: some View {
        VStack(spacing: 8) {
            if !viewModel.config.isStrongField {
                massAndDistanceSliders
            }
            inclinationSlider
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
        .onChange(of: viewModel.config.accretionEddingtonFraction) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
    }

    /// Star (or BH) mass, planet mass, distance and, in BH mode, accretion.
    @ViewBuilder
    private var massAndDistanceSliders: some View {
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
            // BH mode reaches 5 AU so the planet can sit in the BH's habitable zone.
            range: (1.0 / 3.0)...(viewModel.config.isBlackHoleMode ? 5.0 : 3.0),
            color: .white,
            displayText: viewModel.config.separationLabel
        )
        if viewModel.config.isBlackHoleMode {
            // Accretion-disk brightness as a fraction of the Eddington limit;
            // sets the black hole's luminosity and so its habitable zone.
            LogSlider(
                label: "Accretion",
                value: $viewModel.config.accretionEddingtonFraction,
                range: 1e-5...1e-3,
                color: .yellow,
                displayText: viewModel.config.accretionLabel
            )
        }
    }

    private var inclinationSlider: some View {
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

    // MARK: - Habitable Zone Toggle

    /// Shows or hides the habitable-zone band. Purely visual, so it stays
    /// enabled while the simulation runs.
    private var habitableZoneToggle: some View {
        Toggle(isOn: habitableZoneBinding) {
            HStack(spacing: 6) {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(viewModel.config.showHabitableZone ? .green : .gray)
                    .font(.system(size: 10))
                Text("Habitable Zone")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .toggleStyle(.switch)
        .tint(.green)
    }

    private var habitableZoneBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.showHabitableZone },
            set: { viewModel.setHabitableZoneVisible($0) }
        )
    }

    // MARK: - Advanced Opt-In

    /// Shows or hides the Advanced button. Off by default so casual users see
    /// no change; once on, the button also appears in landscape and while running.
    private var advancedOptInToggle: some View {
        Toggle(isOn: $isAdvancedEnabled) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(isAdvancedEnabled ? .purple : .gray)
                    .font(.system(size: 10))
                Text("Advanced Controls")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .toggleStyle(.switch)
        .tint(.purple)
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
