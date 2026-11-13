//
//  MetricsFormattingTests.swift
//  CosmicPathSwiftTests
//
//  Issue #28: S2's metrics row showed "1.46e+03″", "12699359 km" and a
//  time dilation cut off at "τ/t = 1 − 2.2×10…". Precession now steps
//  through arcseconds, arcminutes and degrees, large kilometre values use
//  millions, and Realistic moves "τ/t" into the label.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private enum Metrics28 {
    /// Realistic, 2-body, Black Hole Mode on, S2 scenario.
    static func s2Config() -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldScenario = .sagittariusAStar
        return config
    }

    static var planetaryConfig: SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        return config
    }

    static func metrics(precessionDegrees: Double, orbits: Int = 1) -> RelativisticMetrics {
        var metrics = RelativisticMetrics()
        metrics.precessionAngle = precessionDegrees
        metrics.orbitsCompleted = orbits
        return metrics
    }
}

// MARK: - Precession

struct PrecessionFormattingTests {

    private let text = MetricsText(config: Metrics28.planetaryConfig)

    @Test func arcsecondsBelowOneArcminute() {
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 59.9 / 3600)) == "59.9″")
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 0.1 / 3600)) == "0.1″")
    }

    /// 1460″ used to print as "1.46e+03″".
    @Test func arcminutesFromOneArcminuteToOneDegree() {
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 1460.0 / 3600)) == "24.3′")
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 1.0 / 60)) == "1.0′")
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 0.999)) == "59.9′")
    }

    @Test func degreesFromOneDegree() {
        #expect(text.precession(Metrics28.metrics(precessionDegrees: 1.02)) == "1.02°")
    }

    /// Two S2 orbits at GR's 12.2′ each.
    @Test func s2AfterTwoOrbits() {
        let s2Text = MetricsText(config: Metrics28.s2Config())
        let metrics = Metrics28.metrics(precessionDegrees: 2 * 12.2 / 60, orbits: 2)
        #expect(s2Text.precession(metrics) == "24.4′")
        #expect(s2Text.precessionLabel(metrics) == "Precession")
    }

    @Test func visualKeepsDegrees() {
        let visual = MetricsText(config: SimulationConfig())
        #expect(visual.precession(Metrics28.metrics(precessionDegrees: 0.4)) == "0.40°")
    }

    @Test func arcminuteFormatter() {
        #expect(RealUnitsFormatter.arcminutes(degrees: 12.2 / 60) == "12.2′")
    }
}

// MARK: - Schwarzschild radius

struct SchwarzschildRadiusFormattingTests {

    private let units = ScaleProfile.realisticStrongField.units

    /// rₛ = 2M in geometric units (G = c = 1, length GM☉/c²).
    @Test func sgrAStarInMillionsOfKilometres() {
        let rs = 2 * GalacticCenter.blackHoleMass
        #expect(RealUnitsFormatter.schwarzschildRadius(rs, units: units) == "12.7 million km")
    }

    @Test func stellarBlackHoleStaysInKilometres() {
        #expect(RealUnitsFormatter.schwarzschildRadius(20, units: units) == "29.5 km")
    }

    @Test func belowOneMillionKilometresIsUnchanged() {
        let planetary = ScaleProfile.realisticPlanetary.units
        let moonDistance = 384_400 * SIConstants.kilometer / planetary.metersPerLength
        #expect(RealUnitsFormatter.length(moonDistance, units: planetary) == "384400 km")
    }

    @Test func metricsPanelSlotForS2() {
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 2 * GalacticCenter.blackHoleMass
        let slot = MetricsText(config: Metrics28.s2Config()).schwarzschildRadius(metrics)
        #expect(slot.label == "r\u{209B}")
        #expect(slot.value == "12.7 million km")
    }
}

// MARK: - Time dilation

struct TimeDilationFormattingTests {

    /// At S2's periapsis (1,409 rₛ) the deficit is ≈ rₛ/2r = 3.5×10⁻⁴.
    @Test func s2AtPeriapsisFits() {
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 2 * GalacticCenter.blackHoleMass
        metrics.separation = 1409 * metrics.schwarzschildRadius
        let text = MetricsText(config: Metrics28.s2Config())
        #expect(text.timeDilation(metrics) == "1 − 3.5×10⁻⁴")
        #expect(text.timeDilationLabel == "Time Dilation τ/t")
    }

    @Test func visualKeepsTheEquation() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.983
        let text = MetricsText(config: SimulationConfig())
        #expect(text.timeDilation(metrics) == "τ/t = 0.983")
        #expect(text.timeDilationLabel == "Time Dilation")
    }
}

// MARK: - Orbit count (issue #33)

struct OrbitCountFormattingTests {

    private let text = MetricsText(config: Metrics28.planetaryConfig)

    /// Realistic used to label a single orbit "1 orbits".
    @Test func singularAndPlural() {
        #expect(text.orbits(Metrics28.metrics(precessionDegrees: 0, orbits: 1)).label == "1 orbit")
        #expect(text.orbits(Metrics28.metrics(precessionDegrees: 0, orbits: 2)).label == "2 orbits")
        #expect(text.orbits(Metrics28.metrics(precessionDegrees: 0, orbits: 0)).label == "0 orbits")
    }

    @Test func visualKeepsOrbitsLabel() {
        let visual = MetricsText(config: SimulationConfig())
        #expect(visual.orbits(Metrics28.metrics(precessionDegrees: 0, orbits: 1)).label == "Orbits")
    }
}
