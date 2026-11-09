//
//  GalacticCenterTests.swift
//  CosmicPathSwiftTests
//
//  Issue #21, PR 4: S2 around Sagittarius A*. The scenario must start S2 on
//  its observed orbit (4.30×10⁶ M☉, a = 1031 AU, e = 0.884), reproduce the
//  16-year period and GR's ≈ 12′ precession per orbit, and run at year-scale
//  rates, while the stellar black hole scenario stays as it was.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private enum S2 {
    static let profile = ScaleProfile.realisticStrongField

    /// Realistic, 2-body, Black Hole Mode on, S2 scenario.
    static func config() -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldScenario = .sagittariusAStar
        return config
    }

    /// Kepler period 2π√(a³/GM) with M = Sgr A* + S2, in years.
    static var keplerPeriodYears: Double {
        let gm = profile.constants.G * (GalacticCenter.blackHoleMass + GalacticCenter.starMass) * profile.solarMass
        let a = GalacticCenter.semiMajorAxisAU * profile.au
        return 2 * .pi * sqrt(a * a * a / gm) * profile.units.secondsPerTime / SIConstants.julianYear
    }

    /// The step the app uses for S2: the Visual step × the scenario's time ratio.
    static func timeStep(_ config: SimulationConfig) -> Double {
        config.timeStep * ScenarioTiming.timeRatio(config: config)
    }
}

// MARK: - Setup

struct GalacticCenterSetupTests {

    @Test func s2IsAStrongFieldScenario() {
        let config = S2.config()
        #expect(config.isStrongField)
        #expect(config.isGalacticCenter)
        #expect(config.scale == .realisticStrongField)
        #expect(config.rateRegime == .galacticCenter)
    }

    @Test func s2NeedsTheStrongFieldSetup() {
        var config = S2.config()
        config.isBlackHoleMode = false
        #expect(!config.isGalacticCenter)
        #expect(config.rateRegime == .planetary)

        config = S2.config()
        config.advanced.scale = .visual
        #expect(!config.isGalacticCenter)
    }

    @Test func usesTheObservedMassesAndOrbit() {
        let config = S2.config()
        #expect(config.simulationMass1 == 4.30e6)
        #expect(config.simulationMass2 == 14)
        #expect(config.orbitEccentricity == 0.884)
        let semiMajorAxisAU = config.simulationSeparation / S2.profile.au
        #expect(abs(semiMajorAxisAU - 1031) < 1e-9)
    }

    /// S2 starts at periapsis, a(1 − e) = 119.6 AU ≈ 1,409 rₛ from the hole.
    @Test func startsAtPeriapsis() throws {
        let config = S2.config()
        let bodies = InitialConditions.twoBody(config: config)
        try #require(bodies.count == 2)
        let distance = (bodies[1].position - bodies[0].position).magnitude
        #expect(abs(distance / S2.profile.au - 1031 * (1 - 0.884)) < 1e-6)
        #expect(abs(distance / config.strongFieldSchwarzschildRadius - 1409) < 1)
    }

    /// The Advanced sheet's eccentricity doesn't change S2's observed orbit.
    @Test func ignoresTheAdvancedEccentricity() {
        var config = S2.config()
        config.advanced.initial.eccentricity = 0.3
        #expect(config.orbitEccentricity == 0.884)

        config.strongFieldScenario = .stellarBlackHole
        #expect(config.orbitEccentricity == 0.3)
    }

    @Test func noPeriapsisWarning() {
        #expect(InitialConditions.periapsisWarning(config: S2.config()) == nil)
    }

    /// 6πGM/(c²a(1−e²)) with the issue's values is 12.2′.
    @Test func predictedPrecessionIsAboutTwelveArcminutes() {
        let arcminutes = GalacticCenter.predictedPrecessionPerOrbit * 180 / .pi * 60
        #expect(abs(arcminutes - 12.2) < 0.1)
    }

    @Test func keplerPeriodIsSixteenYears() {
        #expect(abs(S2.keplerPeriodYears - 15.97) < 0.01)
    }

    @Test func labelsUseMillionsAndAU() {
        let config = S2.config()
        #expect(config.strongFieldMassLabel == "4.3 million M\u{2609}")
        #expect(config.distanceLabel(simulationLength: 1031 * S2.profile.au) == "1031.00 AU")
    }

    /// The stellar black hole scenario is unchanged by the new setting.
    @Test func stellarBlackHoleIsUnchanged() {
        var config = S2.config()
        config.strongFieldScenario = .stellarBlackHole
        #expect(config.simulationMass1 == 10)
        #expect(config.simulationMass2 == S2.profile.earthMass)
        #expect(abs(config.simulationSeparation - 8 * 20) < 1e-9)
        #expect(config.distanceLabel(simulationLength: 160) == "8.00 r\u{209B}")
        #expect(config.rateRegime == .stellarBlackHole)
    }
}

// MARK: - Physics

struct GalacticCenterPhysicsTests {

    /// Runs S2 with the app's own step for two full orbits, then checks the
    /// period against Kepler's 15.97 years and the precession against GR's 12.2′.
    @Test func periodAndPrecessionMatchTheory() throws {
        let config = S2.config()
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), settings: config.advanced.engine,
            scale: config.scale, timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        engine.isBlackHoleMode = true

        let dt = S2.timeStep(config)
        let yearsPerStep = dt * S2.profile.units.secondsPerTime / SIConstants.julianYear
        let maxSteps = Int(2.5 * S2.keplerPeriodYears / yearsPerStep)
        var orbitEndSteps: [Int] = []
        for step in 1...maxSteps {
            engine.step(dt: dt)
            if engine.metrics.orbitsCompleted > orbitEndSteps.count {
                orbitEndSteps.append(step)
                if orbitEndSteps.count == 2 { break }
            }
        }
        try #require(orbitEndSteps.count == 2)
        #expect(!engine.metrics.isAbsorbed)

        let periodYears = Double(orbitEndSteps[1] - orbitEndSteps[0]) * yearsPerStep
        #expect(abs(periodYears / S2.keplerPeriodYears - 1) < 0.005)

        let measured = engine.metrics.precessionAngle * .pi / 180 / 2
        let predicted = GalacticCenter.predictedPrecessionPerOrbit
        #expect(abs(measured / predicted - 1) < 0.03)
    }
}

// MARK: - Timing

struct GalacticCenterTimingTests {

    @Test func defaultRateIsOneYearPerSecond() {
        let config = S2.config()
        #expect(config.advanced.time.activeRate(for: config.rateRegime) == .oneYear)
        #expect(RealTimeRate.choices(for: .galacticCenter) == [.oneWeek, .oneMonth, .oneYear, .tenYears])
    }

    /// At 1 s = 1 year the 16-year orbit takes 16 s, at a few dozen steps per frame.
    @Test func oneYearPerSecondFitsTheFrameBudget() {
        let config = S2.config()
        let timeStep = S2.timeStep(config)
        let secondsPerTime = config.scale.units.secondsPerTime
        var planner = FrameStepPlanner()
        let frames = 60
        let total = (0..<frames).reduce(0) { sum, _ in
            sum + planner.steps(
                rateSecondsPerSecond: RealTimeRate.oneYear.simulatedSecondsPerSecond,
                timeStep: timeStep, secondsPerTime: secondsPerTime
            )
        }
        #expect((30...70).contains(total / frames))
        #expect(total / frames * 10 < TimeSettings.maxStepsPerFrame)   // 10 years per second still fits
    }

    @Test func eachRegimeKeepsItsOwnRate() {
        var time = TimeSettings()
        time.galacticCenterRate = .tenYears
        #expect(time.activeRate(for: .galacticCenter) == .tenYears)
        #expect(time.activeRate(for: .stellarBlackHole) == .tenMilliseconds)
        #expect(time.activeRate(for: .planetary) == .oneMonth)
    }
}

// MARK: - View Model & Display

@MainActor
struct GalacticCenterViewModelTests {

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

    @Test func switchingScenarioRestartsWithSgrAStar() {
        let (viewModel, log) = makeViewModel()
        viewModel.config.strongFieldScenario = .sagittariusAStar
        viewModel.applyConfigChange(canvasSize: canvas)
        #expect(log.setups.last?.scale == .realisticStrongField)
        #expect(log.setups.last?.bodies.first?.mass == 4.30e6)
        #expect(viewModel.activeRealTimeRate == .oneYear)
    }

    @Test func resetKeepsTheScenario() {
        let (viewModel, _) = makeViewModel()
        viewModel.config.strongFieldScenario = .sagittariusAStar
        viewModel.reset(canvasSize: canvas)
        #expect(viewModel.config.strongFieldScenario == .sagittariusAStar)
    }

    @Test func noHabitableZoneAroundSgrAStar() {
        let (viewModel, _) = makeViewModel()
        #expect(viewModel.habitableZone != nil)
        viewModel.config.strongFieldScenario = .sagittariusAStar
        #expect(viewModel.habitableZone == nil)
    }

    @Test func badgeNamesS2AndTheRate() {
        let text = ScaleBadgeView.text(config: S2.config(), achievedRate: nil)
        #expect(text == "Realistic · S2 around Sgr A* · 1 s = 1 year · sizes not to scale")
    }

    @Test func precessionIsShownInArcminutes() {
        #expect(RealUnitsFormatter.arcminutes(degrees: 12.2 / 60) == "12.2\u{2032}")
    }
}
