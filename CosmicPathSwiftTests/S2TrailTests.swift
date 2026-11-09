//
//  S2TrailTests.swift
//  CosmicPathSwiftTests
//
//  Issue #27: S2 around Sgr A* drew no orbit trail. Its fine time step
//  (≈ 44,500 steps per orbit) made a step-spaced 800-point trail cover ~2% of
//  the orbit. S2's trail is now spaced by its period, so the default trail
//  traces one full orbit; every other scenario keeps step-spaced trails.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private enum S2Trail {
    static let profile = ScaleProfile.realisticStrongField

    /// Realistic, 2-body, Black Hole Mode on, with the given strong-field scenario.
    static func config(_ scenario: StrongFieldScenario = .sagittariusAStar) -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldScenario = scenario
        return config
    }

    /// Semi-major axis in simulation units.
    static var semiMajorAxis: Double { GalacticCenter.semiMajorAxisAU * profile.au }

    /// Kepler period 2π√(a³/GM), M = Sgr A* + S2, in simulation time.
    static var keplerPeriod: Double {
        let gm = profile.constants.G * (GalacticCenter.blackHoleMass + GalacticCenter.starMass) * profile.solarMass
        let a = semiMajorAxis
        return 2 * .pi * sqrt(a * a * a / gm)
    }

    /// The app's S2 engine, with the trail interval the view model passes.
    static func engine(config: SimulationConfig) -> GravitySimulationEngine {
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), settings: config.advanced.engine,
            scale: config.scale, timeRatio: ScenarioTiming.timeRatio(config: config),
            trailSampleInterval: ScenarioTiming.trailSampleInterval(config: config)
        )
        engine.isBlackHoleMode = true
        return engine
    }

    /// Sum of the angles between successive trail points as seen from `center`.
    static func sweptAngle(_ trail: ArraySlice<Vector3D>, around center: Vector3D) -> Double {
        zip(trail, trail.dropFirst()).reduce(0) { total, pair in
            let a = (pair.0 - center).normalized
            let b = (pair.1 - center).normalized
            return total + acos(min(max(a.dot(b), -1), 1))
        }
    }
}

// MARK: - Interval

struct S2TrailIntervalTests {

    @Test func s2SpacesItsTrailByThePeriod() throws {
        let interval = try #require(ScenarioTiming.trailSampleInterval(config: S2Trail.config()))
        let expected = S2Trail.keplerPeriod / Double(DisplaySettings.baseTrailPoints)
        #expect(abs(interval / expected - 1) < 0.001)
    }

    @Test func otherScenariosKeepTheDefaultSpacing() {
        var realisticPlanetary = SimulationConfig()
        realisticPlanetary.advanced.scale = .realistic

        #expect(ScenarioTiming.trailSampleInterval(config: SimulationConfig()) == nil)
        #expect(ScenarioTiming.trailSampleInterval(config: realisticPlanetary) == nil)
        #expect(ScenarioTiming.trailSampleInterval(config: S2Trail.config(.stellarBlackHole)) == nil)
        #expect(ScenarioTiming.trailSampleInterval(config: S2Trail.config(.blackHolePlanet)) == nil)
    }

    @Test func s2NeedsBlackHoleMode() {
        var config = S2Trail.config()
        config.isBlackHoleMode = false
        #expect(ScenarioTiming.trailSampleInterval(config: config) == nil)
    }
}

// MARK: - Engine

struct S2TrailCoverageTests {

    /// Runs S2 at its own step for 1.02 periods: the last period's 800 points
    /// reach periapsis and apoapsis and go all the way around the hole.
    @Test func defaultTrailCoversOneFullOrbit() throws {
        let config = S2Trail.config()
        let engine = S2Trail.engine(config: config)
        let dt = config.timeStep * ScenarioTiming.timeRatio(config: config)
        let period = S2Trail.keplerPeriod
        let steps = Int((1.02 * period / dt).rounded(.up))
        for _ in 0..<steps { engine.step(dt: dt) }
        try #require(!engine.metrics.isAbsorbed)

        let trail = engine.bodies[1].trail
        let pointsPerOrbit = DisplaySettings.baseTrailPoints
        let expectedCount = Double(steps) * dt / period * Double(pointsPerOrbit)
        #expect(abs(Double(trail.count) - expectedCount) <= 2)
        try #require(trail.count > pointsPerOrbit)

        let lastOrbit = trail.suffix(pointsPerOrbit + 1)
        let hole = engine.bodies[0].position
        let distances = lastOrbit.map { ($0 - hole).magnitude }
        let a = S2Trail.semiMajorAxis
        let e = GalacticCenter.eccentricity
        let periapsis = try #require(distances.min())
        let apoapsis = try #require(distances.max())
        #expect(abs(periapsis / (a * (1 - e)) - 1) < 0.02)
        #expect(abs(apoapsis / (a * (1 + e)) - 1) < 0.02)

        let swept = S2Trail.sweptAngle(lastOrbit, around: hole) * 180 / .pi
        #expect(swept >= 355)
    }

    /// The probe keeps one trail point per default step.
    @Test func probeTrailFollowsTheTimeStep() {
        let config = S2Trail.config(.stellarBlackHole)
        let engine = S2Trail.engine(config: config)
        let dt = config.timeStep * ScenarioTiming.timeRatio(config: config)
        for _ in 0..<100 { engine.step(dt: dt) }
        #expect(abs(engine.bodies[1].trail.count - 100) <= 1)
    }
}

// MARK: - View Model

@MainActor
struct S2TrailViewModelTests {

    private final class SetupLog: @unchecked Sendable {
        var setups: [EngineSetup] = []
    }

    private let canvas = CGSize(width: 400, height: 400)

    @Test func passesTheIntervalOnlyForS2() throws {
        let log = SetupLog()
        let viewModel = SimulationViewModel { setup in
            log.setups.append(setup)
            return MockSimulationEngine(bodies: setup.bodies, settings: setup.settings, scale: setup.scale)
        }
        viewModel.selectScale(.realistic)
        viewModel.config.isBlackHoleMode = true
        viewModel.setup(canvasSize: canvas)
        #expect(log.setups.last?.trailSampleInterval == nil)

        viewModel.config.strongFieldScenario = .sagittariusAStar
        viewModel.applyConfigChange(canvasSize: canvas)
        let interval = try #require(log.setups.last?.trailSampleInterval)
        #expect(interval == ScenarioTiming.trailSampleInterval(config: viewModel.config))

        viewModel.config.strongFieldScenario = .stellarBlackHole
        viewModel.applyConfigChange(canvasSize: canvas)
        #expect(log.setups.last?.trailSampleInterval == nil)
    }
}
