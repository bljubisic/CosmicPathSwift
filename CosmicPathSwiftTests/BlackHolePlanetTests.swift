//
//  BlackHolePlanetTests.swift
//  CosmicPathSwiftTests
//
//  Issue #21, PR 5: a rocky planet around a stellar black hole, the third
//  strong-field scenario. The planet has a real radius, so the Roche limit
//  (≈ 40,600 rₛ for Earth around 10 M☉) decides whether tides tear it apart;
//  the probe scenario stays a point mass.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private enum Planet {
    static let profile = ScaleProfile.realisticStrongFieldPlanet

    /// Realistic, 2-body, Black Hole Mode on, Planet scenario.
    static func config(distanceRs: Double? = nil, eccentricity: Double = 0) -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldScenario = .blackHolePlanet
        if let distanceRs { config.strongFieldPlanetDistanceRs = distanceRs }
        config.advanced.initial.eccentricity = eccentricity
        return config
    }

    static func engine(_ config: SimulationConfig) -> GravitySimulationEngine {
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), settings: config.advanced.engine,
            scale: config.scale, timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        engine.isBlackHoleMode = true
        return engine
    }

    /// The step the app uses: Visual step × time ratio × Accuracy multiplier.
    static func timeStep(_ config: SimulationConfig) -> Double {
        config.timeStep * ScenarioTiming.timeRatio(config: config) * config.advanced.time.timeStepMultiplier
    }

    /// Kepler period 2π√(a³/GM) of the configured orbit, in simulation time.
    static func period(_ config: SimulationConfig) -> Double {
        let a = config.simulationSeparation
        return 2 * .pi * sqrt(a * a * a / (config.simulationMass1 + config.simulationMass2))
    }

    /// Steps `engine` until `orbits` periapsis passages after the first, or the time limit.
    static func run(_ engine: GravitySimulationEngine, config: SimulationConfig, orbits: Int) {
        let dt = timeStep(config)
        let maxSteps = Int(Double(orbits + 1) * period(config) / dt)
        for _ in 0..<maxSteps {
            engine.step(dt: dt)
            if engine.metrics.isAbsorbed || engine.metrics.orbitsCompleted >= orbits { break }
        }
    }
}

// MARK: - Setup

struct BlackHolePlanetSetupTests {

    @Test func planetScenarioUsesTheRockyPlanetProfile() {
        let config = Planet.config()
        #expect(config.isStrongField)
        #expect(config.isBlackHolePlanet)
        #expect(!config.isGalacticCenter)
        #expect(config.scale == .realisticStrongFieldPlanet)
        #expect(config.rateRegime == .blackHolePlanet)
    }

    /// The probe scenario keeps the point-mass profile.
    @Test func probeScenarioIsUnchanged() {
        var config = Planet.config()
        config.strongFieldScenario = .stellarBlackHole
        #expect(config.scale == .realisticStrongField)
        #expect(config.scale.rocheLimit(centralMass: 10, planetMass: config.scale.earthMass) == 0)
        #expect(abs(config.simulationSeparation - 8 * 20) < 1e-9)
    }

    @Test func planetMassAndDistanceComeFromTheSliders() {
        var config = Planet.config(distanceRs: 25_000)
        config.mass2Multiplier = 2
        #expect(config.simulationMass1 == 10)
        #expect(config.simulationMass2 == 2 * Planet.profile.earthMass)
        #expect(abs(config.simulationSeparation - 25_000 * 20) < 1e-6)
    }

    /// R⊕ × (2 × 10 M☉ / M⊕)^⅓ = 1.2 million km = 40,625 rₛ.
    @Test func earthRocheLimitAroundTenSolarMassesIsAbout40600Rs() {
        let limit = Planet.config().blackHolePlanetRocheLimitRs
        #expect(abs(limit / 40_625 - 1) < 0.005)
    }

    /// A heavier rocky planet is also larger, so the limit barely moves: R ∝ M^0.27 against M^-⅓.
    @Test func rocheLimitBarelyDependsOnPlanetMass() {
        var config = Planet.config()
        let earth = config.blackHolePlanetRocheLimitRs
        config.mass2Multiplier = 10
        let heavy = config.blackHolePlanetRocheLimitRs
        config.mass2Multiplier = 0.1
        let light = config.blackHolePlanetRocheLimitRs
        #expect(abs(heavy / earth - pow(10, 0.27 - 1.0 / 3)) < 1e-9)
        #expect(heavy < earth && earth < light)
        #expect(light / heavy < 1.4)
    }

    /// The slider reaches both sides of the Roche limit at every black hole mass.
    @Test(arguments: [3.0, 10.0, 100.0])
    func distanceRangeSpansTheRocheLimit(massSolar: Double) {
        var config = Planet.config()
        config.strongFieldBlackHoleMass = massSolar
        let range = ScaleProfile.StrongField.planetDistanceRangeRs
        #expect(range.contains(config.blackHolePlanetRocheLimitRs))
    }

    @Test func defaultOrbitIsOutsideTheRocheLimit() {
        let config = Planet.config()
        #expect(config.strongFieldPlanetDistanceRs > config.blackHolePlanetRocheLimitRs * 1.4)
        #expect(InitialConditions.periapsisWarning(config: config) == nil)
    }

    /// An eccentric orbit that dips inside the Roche limit gets the existing warning.
    @Test func eccentricOrbitIntoTheRocheLimitIsWarned() {
        let config = Planet.config(eccentricity: 0.5)   // periapsis 30,000 rₛ
        #expect(InitialConditions.periapsisWarning(config: config)?.contains("Roche") == true)
    }

    @Test func labelsGroupThousands() {
        let config = Planet.config()
        #expect(config.strongFieldPlanetDistanceLabel == "60,000 r\u{209B}")
        #expect(config.distanceLabel(simulationLength: 60_000 * 20) == "60,000 r\u{209B}")
        #expect(config.distanceLabel(simulationLength: 160) == "8.00 r\u{209B}")
        #expect(SimulationConfig.groupedInteger(1_234_567.4) == "1,234,567")
        #expect(SimulationConfig.groupedInteger(999) == "999")
    }
}

// MARK: - Physics

struct BlackHolePlanetPhysicsTests {

    /// Outside the Roche limit the planet keeps its mass and orbits undisturbed.
    @Test func defaultPlanetSurvives() {
        let config = Planet.config()
        let engine = Planet.engine(config)
        let startMass = config.simulationMass2
        Planet.run(engine, config: config, orbits: 3)
        #expect(!engine.metrics.isAbsorbed)
        #expect(engine.bodies[1].mass == startMass)
        #expect(engine.bleedParticles.isEmpty)
    }

    /// Inside the Roche limit, tides strip the planet and shed debris.
    @Test func planetInsideTheRocheLimitIsStripped() {
        let config = Planet.config(distanceRs: 20_000)
        let engine = Planet.engine(config)
        let startMass = config.simulationMass2
        let dt = Planet.timeStep(config)
        var sawDebris = false
        for _ in 0..<Int(Planet.period(config) / dt) {
            engine.step(dt: dt)
            sawDebris = sawDebris || !engine.bleedParticles.isEmpty
            if engine.metrics.isAbsorbed { break }
        }
        #expect(engine.metrics.isAbsorbed || engine.bodies[1].mass < startMass * 0.9)
        #expect(sawDebris)
    }

    /// GR's weak-field precession, 6πGM/(c²a(1−e²)) ≈ 34″ per orbit at 60,000 rₛ
    /// and e = 0.2, measured with Yoshida 4 at Accuracy ×¼.
    @Test func precessionMatchesGR() throws {
        var config = Planet.config(eccentricity: 0.2)
        config.advanced.engine.integrator = .yoshida4
        config.advanced.time.timeStepMultiplier = 0.25
        let engine = Planet.engine(config)
        Planet.run(engine, config: config, orbits: 3)
        let orbits = engine.metrics.orbitsCompleted
        try #require(orbits >= 3)

        let mass = config.simulationMass1 + config.simulationMass2
        let a = config.simulationSeparation
        let predicted = 6 * .pi * mass / (a * (1 - 0.04))
        let measured = engine.metrics.precessionAngle * .pi / 180 / Double(orbits)
        #expect(abs(measured / predicted - 1) < 0.05)
    }

    /// At the default accuracy Verlet's own error takes about 15% off the
    /// measured precession (28.9″ against 33.8″), as the Diagnostics caption says.
    @Test func defaultAccuracyIsAboutFifteenPercentLow() throws {
        let config = Planet.config(eccentricity: 0.2)
        let engine = Planet.engine(config)
        Planet.run(engine, config: config, orbits: 3)
        let orbits = engine.metrics.orbitsCompleted
        try #require(orbits >= 3)
        let mass = config.simulationMass1 + config.simulationMass2
        let predicted = 6 * .pi * mass / (config.simulationSeparation * (1 - 0.04)) * 180 / .pi * 3600
        let measured = engine.metrics.precessionAngle * 3600 / Double(orbits)
        let ratio = measured / predicted
        #expect(ratio > 0.8 && ratio < 0.9)
    }
}

// MARK: - Timing

struct BlackHolePlanetTimingTests {

    /// The default orbit takes about 3.6 hours.
    @Test func defaultOrbitTakesAboutThreeAndAHalfHours() {
        let config = Planet.config()
        let hours = Planet.period(config) * config.scale.units.secondsPerTime / 3_600
        #expect(abs(hours - 3.57) < 0.05)
    }

    @Test func defaultRateIsTenMinutesPerSecond() {
        let config = Planet.config()
        #expect(config.advanced.time.activeRate(for: config.rateRegime) == .tenMinutes)
        #expect(RealTimeRate.choices(for: .blackHolePlanet) == [.oneMinute, .tenMinutes, .oneHour, .sixHours])
        #expect(RealTimeRate.tenMinutes.label == "1 s = 10 min")
        #expect(RealTimeRate.oneMinute.simulatedSecondsPerSecond == 60)
    }

    /// The fastest rate at the closest orbit stays within the step budget.
    @Test func fastestRateAtTheClosestOrbitFitsTheBudget() {
        let config = Planet.config(distanceRs: ScaleProfile.StrongField.planetDistanceRangeRs.lowerBound)
        let stepSeconds = Planet.timeStep(config) * config.scale.units.secondsPerTime
        let stepsPerFrame = RealTimeRate.oneMinute.simulatedSecondsPerSecond / 60 / stepSeconds
        #expect(stepsPerFrame < Double(TimeSettings.maxStepsPerFrame))
    }
}

// MARK: - View Model

@MainActor
struct BlackHolePlanetViewModelTests {

    private final class SetupLog: @unchecked Sendable {
        var setups: [EngineSetup] = []
    }

    private let canvas = CGSize(width: 400, height: 400)

    private func makeViewModel() -> (SimulationViewModel, SetupLog) {
        let log = SetupLog()
        let viewModel = SimulationViewModel { setup in
            log.setups.append(setup)
            return MockSimulationEngine(bodies: setup.bodies, settings: setup.settings, scale: setup.scale)
        }
        viewModel.selectScale(.realistic)
        viewModel.config.isBlackHoleMode = true
        viewModel.setup(canvasSize: canvas)
        return (viewModel, log)
    }

    @Test func switchingToPlanetRestartsWithTheRockyPlanetProfile() {
        let (viewModel, log) = makeViewModel()
        viewModel.config.strongFieldScenario = .blackHolePlanet
        viewModel.applyConfigChange(canvasSize: canvas)
        #expect(log.setups.last?.scale == .realisticStrongFieldPlanet)
        #expect(log.setups.last?.bodies.last?.mass == ScaleProfile.realisticStrongFieldPlanet.earthMass)
        #expect(viewModel.activeRealTimeRate == .tenMinutes)
    }

    @Test func blackHoleModeResetRestoresThePlanetDistance() {
        var config = Planet.config(distanceRs: 5_000)
        config.resetStrongFieldParameters()
        #expect(config.strongFieldPlanetDistanceRs == 60_000)
    }

    @Test func resetKeepsThePlanetScenario() {
        let (viewModel, _) = makeViewModel()
        viewModel.config.strongFieldScenario = .blackHolePlanet
        viewModel.reset(canvasSize: canvas)
        #expect(viewModel.config.strongFieldScenario == .blackHolePlanet)
    }

    @Test func precessionIsShownInArcsecondsForThePlanet() {
        #expect(DiagnosticsSection.angleText(degrees: 31.0 / 3600, arcseconds: true) == "31\u{2033}")
        #expect(DiagnosticsSection.angleText(degrees: 12.5, arcseconds: false) == "12.50°")
    }
}
