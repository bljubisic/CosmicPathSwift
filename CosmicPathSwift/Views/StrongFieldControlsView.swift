//
//  StrongFieldControlsView.swift
//  CosmicPathSwift
//
//  Sliders for the Realistic strong-field setup (issue #21, PR 3): the black
//  hole's mass in real M☉ and the probe's distance in Schwarzschild radii.
//  Shown by `ControlPanelView` in place of the star, planet and distance
//  sliders when Black Hole Mode is on in the Realistic scale.
//

import SwiftUI

struct StrongFieldControlsView: View {
    @Bindable var viewModel: SimulationViewModel
    let canvasSize: CGSize

    private typealias Ranges = ScaleProfile.StrongField

    var body: some View {
        VStack(spacing: 8) {
            LogSlider(
                label: "BH Mass",
                value: $viewModel.config.strongFieldBlackHoleMass,
                range: Ranges.blackHoleMassRange,
                color: .red,
                displayText: viewModel.config.strongFieldMassLabel
            )
            LogSlider(
                label: "Distance",
                value: $viewModel.config.strongFieldDistanceRs,
                range: Ranges.distanceRangeRs,
                color: .white,
                displayText: viewModel.config.strongFieldDistanceLabel
            )
            caption(Self.probeCaption)
            caption(Self.accuracyCaption)
        }
        .onChange(of: viewModel.config.strongFieldBlackHoleMass) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.strongFieldDistanceRs) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
    }

    /// Why there is no planet slider.
    static let probeCaption =
        "Probe: a compact test mass. An Earth-like planet would be torn apart ~40,000 r\u{209B} out."

    /// What is exact and what is approximate in this setup.
    static let accuracyCaption =
        "Horizon, photon sphere and ISCO radii are exact. Orbital periods near the hole are approximate "
        + "(about 30% short at the ISCO)."

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
