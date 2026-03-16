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

            // Black hole mode toggle
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
                    viewModel.config.mass1 = 5000.0
                    viewModel.config.initialSeparation = 200.0
                } else {
                    viewModel.config.mass1 = 200.0
                    viewModel.config.initialSeparation = 150.0
                }
                viewModel.applyConfigChange(canvasSize: canvasSize)
            }

            // Parameter sliders
            VStack(spacing: 8) {
                parameterSlider(
                    label: viewModel.config.isBlackHoleMode ? "BH Mass" : "Mass 1 (heavy)",
                    value: $viewModel.config.mass1,
                    range: viewModel.config.isBlackHoleMode ? 2000...20000 : 50...500,
                    color: viewModel.config.isBlackHoleMode ? .red : .orange
                )
                parameterSlider(
                    label: "Mass 2 (light)",
                    value: $viewModel.config.mass2,
                    range: 1...50,
                    color: .cyan
                )
                parameterSlider(
                    label: "Separation",
                    value: $viewModel.config.initialSeparation,
                    range: viewModel.config.isBlackHoleMode ? 80...400 : 60...300,
                    color: .white
                )
            }
            .disabled(viewModel.isRunning)
            .opacity(viewModel.isRunning ? 0.5 : 1.0)
            .onChange(of: viewModel.config.mass1) { _, _ in
                viewModel.applyConfigChange(canvasSize: canvasSize)
            }
            .onChange(of: viewModel.config.mass2) { _, _ in
                viewModel.applyConfigChange(canvasSize: canvasSize)
            }
            .onChange(of: viewModel.config.initialSeparation) { _, _ in
                viewModel.applyConfigChange(canvasSize: canvasSize)
            }

            if viewModel.isRunning {
                Text(viewModel.metrics.isAbsorbed ? "Object crossed the event horizon" : "Pause to adjust parameters")
                    .font(.caption2)
                    .foregroundStyle(viewModel.metrics.isAbsorbed ? .red.opacity(0.7) : .white.opacity(0.4))
            }
        }
    }

    // MARK: - Slider Helper

    private func parameterSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        color: Color
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: range)
                .tint(color)
            Text("\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 46, alignment: .trailing)
        }
    }
}
