//
//  ThreeBodyControlsView.swift
//  CosmicPathSwift
//
//  3-body parameter controls: preset picker, plus mass / spread / velocity
//  sliders for the Custom preset.
//

import SwiftUI

/// Preset picker and Custom-preset sliders shown in 3-body mode.
///
/// Every change restarts the simulation via `selectPreset` / `applyConfigChange`,
/// matching how the 2-body sliders behave. Disabled while the simulation runs.
struct ThreeBodyControlsView: View {
    @Bindable var viewModel: SimulationViewModel
    let canvasSize: CGSize

    var body: some View {
        VStack(spacing: 8) {
            presetPicker
            if viewModel.config.threeBodyPreset == .custom {
                customSliders
            }
        }
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.5 : 1.0)
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        HStack {
            Text("Preset")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Picker("Preset", selection: presetBinding) {
                ForEach(ThreeBodyPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
    }

    private var presetBinding: Binding<ThreeBodyPreset> {
        Binding(
            get: { viewModel.config.threeBodyPreset },
            set: { viewModel.selectPreset($0, canvasSize: canvasSize) }
        )
    }

    // MARK: - Custom Sliders

    private var customSliders: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                LogSlider(
                    label: "Mass \(SystemMetrics.letter(for: index))",
                    value: massBinding(index),
                    range: 0.1...10,
                    color: BodyView.paletteColor(for: index),
                    displayText: String(format: "%.2g×", viewModel.config.customMassMultipliers[index])
                )
            }
            LogSlider(
                label: "Spread",
                value: $viewModel.config.customSpreadAU,
                range: 0.5...2,
                color: .white,
                displayText: String(format: "%.2f AU", viewModel.config.customSpreadAU)
            )
            velocitySlider
        }
        .onChange(of: viewModel.config.customMassMultipliers) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.customSpreadAU) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.customVelocityFactor) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
    }

    /// Linear 0–1.5× slider: 1.0 is rigid Lagrange rotation; anything else is chaotic.
    private var velocitySlider: some View {
        HStack {
            Text("Velocity")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            Slider(value: $viewModel.config.customVelocityFactor, in: 0...1.5)
                .tint(.purple)
            Text(String(format: "%.2f×", viewModel.config.customVelocityFactor))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .trailing)
        }
    }

    /// Binding to one entry of `customMassMultipliers`, replacing the whole array
    /// on write so the change is observed as a single config update.
    private func massBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { viewModel.config.customMassMultipliers[index] },
            set: { newValue in
                var multipliers = viewModel.config.customMassMultipliers
                multipliers[index] = newValue
                viewModel.config.customMassMultipliers = multipliers
            }
        )
    }
}
