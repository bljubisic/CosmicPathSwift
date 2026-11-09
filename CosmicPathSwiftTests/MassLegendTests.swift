//
//  MassLegendTests.swift
//  CosmicPathSwiftTests
//
//  Issue #24: the 2-body mass legend must show the masses that are actually
//  simulated. In the Realistic strong-field scenarios those come from the BH
//  Mass slider, the Planet Mass slider or S2's observed values, not from the
//  Visual star and planet sliders.
//

import Testing
import Foundation
@testable import CosmicPathSwift

private enum Legend {
    /// Realistic, 2-body, Black Hole Mode on, with `scenario`.
    static func strongField(_ scenario: StrongFieldScenario) -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldScenario = scenario
        return config
    }
}

// MARK: - Strong Field

struct StrongFieldLegendTests {

    @Test func probeShowsTheBlackHoleMassAndProbe() {
        var config = Legend.strongField(.stellarBlackHole)
        #expect(config.twoBodyLegendLabels == ["10 M\u{2609}", "Probe"])

        config.strongFieldBlackHoleMass = 60
        #expect(config.twoBodyLegendLabels == ["60 M\u{2609}", "Probe"])
    }

    /// The hidden Visual sliders must not leak into the probe's legend.
    @Test func probeIgnoresTheVisualSliders() {
        var config = Legend.strongField(.stellarBlackHole)
        config.mass1Multiplier = 5
        config.mass2Multiplier = 3
        #expect(config.twoBodyLegendLabels == ["10 M\u{2609}", "Probe"])
    }

    @Test func planetShowsTheBlackHoleAndPlanetMassSliders() {
        var config = Legend.strongField(.blackHolePlanet)
        #expect(config.twoBodyLegendLabels == ["10 M\u{2609}", "1 M\u{2295}"])

        config.strongFieldBlackHoleMass = 4.5
        config.mass2Multiplier = 2
        #expect(config.twoBodyLegendLabels == ["4.5 M\u{2609}", "2.0 M\u{2295}"])
    }

    @Test func s2ShowsSgrAStarAndS2ByName() {
        var config = Legend.strongField(.sagittariusAStar)
        let expected = ["Sgr A* · 4.3 million M\u{2609}", "S2 · 14 M\u{2609}"]
        #expect(config.twoBodyLegendLabels == expected)

        // S2's values are fixed by observation: the sliders don't change them.
        config.strongFieldBlackHoleMass = 60
        config.mass1Multiplier = 5
        config.mass2Multiplier = 3
        #expect(config.twoBodyLegendLabels == expected)
    }
}

// MARK: - Unchanged Setups

struct UnchangedLegendTests {

    @Test func visualTwoBodyShowsTheSliders() {
        var config = SimulationConfig()
        #expect(config.twoBodyLegendLabels == ["1 M\u{2609}", "1 M\u{2295}"])
        config.mass1Multiplier = 2.5
        config.mass2Multiplier = 10
        #expect(config.twoBodyLegendLabels == ["2.5 M\u{2609}", "10 M\u{2295}"])
    }

    /// Visual Black Hole Mode keeps its BH Mass slider's own label.
    @Test func visualBlackHoleModeShowsTheSliders() {
        var config = SimulationConfig()
        config.isBlackHoleMode = true
        config.mass1Multiplier = 3
        #expect(config.twoBodyLegendLabels == ["3.0 M\u{2609}", "1 M\u{2295}"])
    }

    /// In the Realistic planetary scale the sliders are the real masses.
    @Test func realisticPlanetaryShowsTheSliders() {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.mass1Multiplier = 2
        config.mass2Multiplier = 0.5
        #expect(config.twoBodyLegendLabels == ["2.0 M\u{2609}", "0.5 M\u{2295}"])
    }

    /// The scenario setting only matters in strong field.
    @Test func scenarioIsIgnoredOutsideStrongField() {
        var config = SimulationConfig()
        config.strongFieldScenario = .sagittariusAStar
        #expect(config.twoBodyLegendLabels == ["1 M\u{2609}", "1 M\u{2295}"])
    }
}

// MARK: - View Model

@MainActor
struct MassLegendViewModelTests {
    private let canvas = CGSize(width: 400, height: 400)

    @Test func bodyLabelsFollowTheStrongFieldScenario() {
        let viewModel = SimulationViewModel { MockSimulationEngine(bodies: $0.bodies) }
        viewModel.selectScale(.realistic)
        viewModel.config.isBlackHoleMode = true
        viewModel.setup(canvasSize: canvas)
        #expect(viewModel.bodyLabels == ["10 M\u{2609}", "Probe"])

        viewModel.config.strongFieldScenario = .sagittariusAStar
        viewModel.applyConfigChange(canvasSize: canvas)
        #expect(viewModel.bodyLabels == ["Sgr A* · 4.3 million M\u{2609}", "S2 · 14 M\u{2609}"])
    }
}
