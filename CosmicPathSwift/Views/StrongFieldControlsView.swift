//
//  StrongFieldControlsView.swift
//  CosmicPathSwift
//
//  Sliders for the Realistic strong-field setup (issue #21, PR 3): the black
//  hole's mass in real M☉ and the probe's distance in Schwarzschild radii.
//  Shown by `ControlPanelView` in place of the star, planet and distance
//  sliders when Black Hole Mode is on in the Realistic scale.
//
//  A scenario picker chooses what orbits the hole: a point-mass probe a few
//  rₛ out (strong-field GR), a rocky planet thousands of rₛ out (tides), or
//  S2 around Sagittarius A*, whose values are fixed by observation.
//

import SwiftUI

struct StrongFieldControlsView: View {
    @Bindable var viewModel: SimulationViewModel
    let canvasSize: CGSize

    private typealias Ranges = ScaleProfile.StrongField

    var body: some View {
        VStack(spacing: 8) {
            Picker("Scenario", selection: $viewModel.config.strongFieldScenario) {
                ForEach(StrongFieldScenario.allCases, id: \.self) { scenario in
                    Text(scenario.displayName).tag(scenario)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.config.strongFieldScenario {
            case .stellarBlackHole:
                blackHoleMassSlider
                LogSlider(
                    label: "Distance",
                    value: $viewModel.config.strongFieldDistanceRs,
                    range: Ranges.distanceRangeRs,
                    color: .white,
                    displayText: viewModel.config.strongFieldDistanceLabel
                )
                caption(Self.probeCaption)
                caption(Self.accuracyCaption)
            case .blackHolePlanet:
                blackHoleMassSlider
                // The ControlPanelView's onChange(of: mass2Multiplier) restarts the setup.
                LogSlider(
                    label: "Planet Mass",
                    value: $viewModel.config.mass2Multiplier,
                    range: 0.1...10,
                    color: .cyan,
                    displayText: viewModel.config.mass2Label
                )
                LogSlider(
                    label: "Distance",
                    value: $viewModel.config.strongFieldPlanetDistanceRs,
                    range: Ranges.planetDistanceRangeRs,
                    color: .white,
                    displayText: viewModel.config.strongFieldPlanetDistanceLabel
                )
                caption(rocheCaption)
                caption(Self.planetCaption)
            case .sagittariusAStar:
                caption(Self.galacticCenterCaption)
                caption(Self.galacticCenterPrecessionCaption)
            }
        }
        .onChange(of: viewModel.config.strongFieldScenario) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.strongFieldBlackHoleMass) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.strongFieldDistanceRs) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        .onChange(of: viewModel.config.strongFieldPlanetDistanceRs) { _, _ in
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
    }

    private var blackHoleMassSlider: some View {
        LogSlider(
            label: "BH Mass",
            value: $viewModel.config.strongFieldBlackHoleMass,
            range: Ranges.blackHoleMassRange,
            color: .red,
            displayText: viewModel.config.strongFieldMassLabel
        )
    }

    /// Where tides start tearing this planet apart, for the current masses.
    private var rocheCaption: String {
        let config = viewModel.config
        let limit = config.blackHolePlanetRocheLimitRs
        let kilometres = limit * config.strongFieldSchwarzschildRadius * config.scale.units.metersPerLength / 1_000
        let inside = config.strongFieldPlanetDistanceRs < limit
        return "Roche limit: \(SimulationConfig.groupedInteger(limit)) r\u{209B} "
            + "(\(SimulationConfig.groupedInteger(kilometres)) km). "
            + (inside ? "The planet starts inside it: tides will tear it apart."
                      : "Move the planet inside it to watch tides tear it apart.")
    }

    /// Why there is no planet slider.
    static let probeCaption =
        "Probe: a compact test mass, so it can orbit a few r\u{209B} out. A planet would be torn apart "
        + "thousands of r\u{209B} away: see the Planet scenario."

    /// What the Planet scenario shows, and what it doesn't.
    static let planetCaption =
        "A rocky planet. Far from the hole the orbit looks Newtonian; GR shows up as a precession of "
        + "arcseconds per orbit under Advanced \u{2192} Diagnostics."

    /// What is exact and what is approximate in this setup.
    static let accuracyCaption =
        "Horizon, photon sphere and ISCO radii are exact. Orbital periods near the hole are approximate "
        + "(about 30% short at the ISCO)."

    /// The observed values S2 runs with.
    static let galacticCenterCaption =
        "Sagittarius A*, 4.3 million M\u{2609}. S2: a = 1031 AU, e = 0.884, one orbit every 16 years; "
        + "closest approach 120 AU (about 1,400 r\u{209B})."

    /// What to look for, and that it has been measured.
    static let galacticCenterPrecessionCaption =
        "GR turns the ellipse by about 12\u{2032} per orbit. The GRAVITY collaboration measured this in 2020, "
        + "in agreement with GR."

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
