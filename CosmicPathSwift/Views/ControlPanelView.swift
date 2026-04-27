//
//  ControlPanelView.swift
//  CosmicPathSwift
//
//  Simulation controls: start/pause, reset, black hole mode toggle,
//  and parameter sliders for mass, separation, and orbital inclination.
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
/// - `showParameterControls = true` (portrait): Shows black hole toggle and
///   logarithmic sliders for star mass, planet mass, and orbital distance.
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

            // Black hole mode toggle and sliders (portrait only)
            if showParameterControls {
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
                    logSlider(
                        label: viewModel.config.isBlackHoleMode ? "BH Mass" : "Star Mass",
                        value: $viewModel.config.mass1Multiplier,
                        range: 0.1...10,
                        color: viewModel.config.isBlackHoleMode ? .red : .orange,
                        displayText: viewModel.config.mass1Label
                    )
                    logSlider(
                        label: "Planet Mass",
                        value: $viewModel.config.mass2Multiplier,
                        range: 0.1...10,
                        color: .cyan,
                        displayText: viewModel.config.mass2Label
                    )
                    logSlider(
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

                if viewModel.isRunning {
                    Text(viewModel.metrics.isAbsorbed
                        ? (viewModel.metrics.isBlackHole ? "Object crossed the event horizon" : "Planet collided with the star")
                        : "Pause to adjust parameters")
                        .font(.caption2)
                        .foregroundStyle(viewModel.metrics.isAbsorbed ? .red.opacity(0.7) : .white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Logarithmic Slider

    /// A slider that maps a linear 0...1 thumb position to a logarithmic value range.
    ///
    /// ## Why Logarithmic?
    ///
    /// Physical parameters like mass span orders of magnitude (0.1× to 10×).
    /// A linear slider would compress the useful 0.5–2.0 range into a tiny portion
    /// of the track. The log mapping ensures equal thumb travel for equal multiplicative
    /// changes: moving from 1× to 2× takes the same distance as 2× to 4×.
    ///
    /// The default value (1.0) sits at the geometric center of the range when
    /// `min × max = 1.0` (e.g. 0.1...10), so the thumb starts in the middle.
    private func logSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        color: Color,
        displayText: String
    ) -> some View {
        let logMin = log(range.lowerBound)
        let logMax = log(range.upperBound)

        let normalizedBinding = Binding<Double>(
            get: {
                let clamped = min(max(value.wrappedValue, range.lowerBound), range.upperBound)
                return (log(clamped) - logMin) / (logMax - logMin)
            },
            set: { normalized in
                value.wrappedValue = exp(logMin + normalized * (logMax - logMin))
            }
        )

        return HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            Slider(value: normalizedBinding, in: 0...1)
                .tint(color)
            Text(displayText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .trailing)
        }
    }
}
