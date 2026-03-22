//
//  ControlPanelView.swift
//  CosmicPathSwift
//
//  Simulation controls: start/pause, reset, black hole mode toggle,
//  and parameter sliders for mass and separation.
//

import SwiftUI

struct ControlPanelView: View {
    @Bindable var viewModel: SimulationViewModel
    let canvasSize: CGSize
    var showParameterControls: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            // Play/Pause and Reset buttons
            HStack(spacing: 20) {
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
                    .frame(minWidth: 100)
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
                    viewModel.applyConfigChange(canvasSize: canvasSize)
                }

                // Parameter sliders
                VStack(spacing: 8) {
                    parameterSlider(
                        label: viewModel.config.isBlackHoleMode ? "BH Mass" : "Star Mass",
                        value: $viewModel.config.mass1Multiplier,
                        range: 0.1...100,
                        color: viewModel.config.isBlackHoleMode ? .red : .orange,
                        displayText: viewModel.config.mass1Label
                    )
                    parameterSlider(
                        label: "Planet Mass",
                        value: $viewModel.config.mass2Multiplier,
                        range: 0.1...100,
                        color: .cyan,
                        displayText: viewModel.config.mass2Label
                    )
                    parameterSlider(
                        label: "Distance",
                        value: $viewModel.config.separationAU,
                        range: 0.3...3.0,
                        color: .white,
                        displayText: viewModel.config.separationLabel
                    )
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

                if viewModel.isRunning {
                    Text(viewModel.metrics.isAbsorbed ? "Object crossed the event horizon" : "Pause to adjust parameters")
                        .font(.caption2)
                        .foregroundStyle(viewModel.metrics.isAbsorbed ? .red.opacity(0.7) : .white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Slider Helper

    private func parameterSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        color: Color,
        displayText: String
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
                .tint(color)
            Text(displayText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .trailing)
        }
    }
}
