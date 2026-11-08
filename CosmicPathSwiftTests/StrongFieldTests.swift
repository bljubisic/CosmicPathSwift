//
//  StrongFieldTests.swift
//  CosmicPathSwiftTests
//
//  Issue #21, PR 3: Black Hole Mode in the Realistic scale. Geometric units
//  (G = c = 1, length GM☉/c², time GM☉/c³) must give the real horizon size,
//  the ISCO at 3 rₛ for any mass, the force law's own circular periods and
//  GR's weak-field precession, while Visual Black Hole Mode stays untouched.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private enum StrongField {
    static let profile = ScaleProfile.realisticStrongField

    /// Realistic, 2-body, Black Hole Mode on.
    static func config(massSolar: Double = 10, distanceRs: Double = 8) -> SimulationConfig {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        config.strongFieldBlackHoleMass = massSolar
        config.strongFieldDistanceRs = distanceRs
        return config
    }

    /// Black hole of `mass` at the origin and a probe at radius `r` on the x-axis,
    /// moving along y at `speedFactor` × the force law's circular speed
    /// v = √(M/(r − 3M)) (G = c = 1).
    static func circularPair(mass: Double, radius r: Double, speedFactor: Double) -> [CelestialBody] {
        let probeMass = profile.earthMass
        let totalMass = mass + probeMass
        let speed = sqrt(totalMass / (r - 3 * totalMass)) * speedFactor
        return [
            CelestialBody(id: 0, kind: .star, mass: mass, position: .zero, velocity: .zero),
            CelestialBody(id: 1, kind: .planet, mass: probeMass,
                          position: Vector3D(x: r, y: 0, z: 0), velocity: Vector3D(x: 0, y: speed, z: 0))
        ]
    }

    /// Circular period of the app's force law: 2π√(r²(r − 3M)/M).
    static func forceLawPeriod(mass: Double, radius r: Double) -> Double {
        2 * .pi * sqrt(r * r * (r - 3 * mass) / mass)
    }

    static func engine(_ bodies: [CelestialBody]) -> GravitySimulationEngine {
        let engine = GravitySimulationEngine(bodies: bodies, scale: profile)
        engine.isBlackHoleMode = true
        return engine
    }

    /// Runs `engine` for `periods` × `period` at `stepsPerPeriod`, stopping early
    /// once the probe is absorbed. Returns the largest separation seen.
    @discardableResult
    static func run(_ engine: GravitySimulationEngine, period: Double, periods: Int, stepsPerPeriod: Int) -> Double {
        let dt = period / Double(stepsPerPeriod)
        var largest = 0.0
        for _ in 0..<(periods * stepsPerPeriod) {
            engine.step(dt: dt)
            if engine.metrics.isAbsorbed { break }
            largest = max(largest, engine.metrics.separation)
        }
        return largest
    }
}

// MARK: - Units

struct StrongFieldUnitsTests {

    @Test func geometricUnitsHaveGAndCEqualToOne() {
        #expect(StrongField.profile.constants.G == 1)
        #expect(StrongField.profile.constants.c == 1)
    }

    @Test func lengthAndTimeUnitsAreGMOverCSquaredAndCubed() {
        let units = StrongField.profile.units
        #expect(abs(units.metersPerLength / 1476.6 - 1) < 1e-4)
        #expect(abs(units.secondsPerTime / 4.9255e-6 - 1) < 1e-4)
    }

    @Test func tenSolarMassHorizonIs29Point53Kilometres() {
        let rs = StrongField.profile.constants.schwarzschildRadius(mass: 10 * StrongField.profile.solarMass)
        let km = rs * StrongField.profile.units.metersPerLength / 1000
        #expect(abs(km - 29.53) < 0.01)
        #expect(RealUnitsFormatter.schwarzschildRadius(rs, units: StrongField.profile.units) == "29.5 km")
    }

    @Test func probeIsAPointMassWithoutRocheLimit() {
        let profile = StrongField.profile
        #expect(profile.rocheLimit(centralMass: 100, planetMass: profile.earthMass) == 0)
        #expect(profile.rocheLimit(centralMass: 100, planetMass: 0) == 0)
    }
}

// MARK: - Config

struct StrongFieldConfigTests {

    @Test func realisticBlackHoleModeSelectsTheStrongFieldProfile() {
        let config = StrongField.config()
        #expect(config.isStrongField)
        #expect(config.scale == .realisticStrongField)
        #expect(config.simulationMass1 == 10)
        // 8 rₛ, rₛ = 2M = 20.
        #expect(abs(config.simulationSeparation - 160) < 1e-9)
    }

    @Test func strongFieldNeedsRealisticTwoBodyAndBlackHoleMode() {
        var visual = StrongField.config()
        visual.advanced.scale = .visual
        #expect(!visual.isStrongField)
        #expect(visual.scale == .visual)
        #expect(visual.simulationMass1 == ScaleProfile.visual.blackHoleBaseMass)

        var threeBody = StrongField.config()
        threeBody.mode = .threeBody
        #expect(!threeBody.isStrongField)
        #expect(threeBody.scale == .realisticPlanetary)

        var planetary = StrongField.config()
        planetary.isBlackHoleMode = false
        #expect(planetary.scale == .realisticPlanetary)
    }

    @Test func defaultStrongFieldOrbitStartsCircularOutsideTheISCO() {
        let bodies = InitialConditions.twoBody(config: StrongField.config())
        let r = (bodies[1].position - bodies[0].position).magnitude
        let v = bodies[1].velocity.magnitude
        // Circular speed √(M/(r − 1.5 rₛ)) = √(10/130).
        #expect(abs(r - 160) < 1e-9)
        #expect(abs(v - sqrt(10.0 / 130)) < 1e-6)
    }

    @Test func periapsisWarningUsesSchwarzschildRadii() {
        var config = StrongField.config(distanceRs: 4)
        config.advanced.initial.eccentricity = 0.4
        let warning = InitialConditions.periapsisWarning(config: config)
        #expect(warning?.contains("2.40 r\u{209B}") == true)
    }

    @Test func resetStrongFieldParametersRestoresDefaults() {
        var config = StrongField.config(massSolar: 50, distanceRs: 20)
        config.resetStrongFieldParameters()
        #expect(config.strongFieldBlackHoleMass == 10)
        #expect(config.strongFieldDistanceRs == 8)
    }
}

// MARK: - Dynamics

struct StrongFieldDynamicsTests {

    /// Steps per force-law period in the ISCO tests: fine enough that the
    /// integrator's energy error is far below the 3.3 rₛ well's depth.
    private static let iscoStepsPerPeriod = 4000

    /// The same 0.1% speed deficit is a small oscillation outside the ISCO and
    /// a plunge inside it, for any mass: the ISCO is at 3 rₛ = 6GM/c².
    /// (A speed excess is a poor plunge test: just inside the ISCO it pushes
    /// the probe outward onto a marginally bound orbit.)
    @Test(arguments: [5.0, 50.0])
    func iscoSitsAtThreeSchwarzschildRadii(massSolar: Double) {
        let rs = 2 * massSolar

        let outsideRadius = 3.3 * rs
        let outside = StrongField.engine(
            StrongField.circularPair(mass: massSolar, radius: outsideRadius, speedFactor: 0.999)
        )
        let largest = StrongField.run(
            outside, period: StrongField.forceLawPeriod(mass: massSolar, radius: outsideRadius),
            periods: 20, stepsPerPeriod: Self.iscoStepsPerPeriod
        )
        #expect(!outside.metrics.isAbsorbed)
        #expect(largest < outsideRadius * 1.01)

        let insideRadius = 2.7 * rs
        let inside = StrongField.engine(
            StrongField.circularPair(mass: massSolar, radius: insideRadius, speedFactor: 0.999)
        )
        StrongField.run(
            inside, period: StrongField.forceLawPeriod(mass: massSolar, radius: insideRadius),
            periods: 20, stepsPerPeriod: Self.iscoStepsPerPeriod
        )
        #expect(inside.metrics.isAbsorbed)
    }

    /// Just outside the ISCO the measured period matches the force law's
    /// 2π√(r²(r − 3M)/M). GR's Schwarzschild period is 2π√(r³/M) (coordinate
    /// time), about 29% longer at the ISCO itself: the app's force law has the
    /// exact Schwarzschild radii but short periods near the hole.
    @Test func periodNearTheISCOMatchesTheForceLaw() throws {
        let mass = 10.0
        let r = 3.05 * 2 * mass
        let expected = StrongField.forceLawPeriod(mass: mass, radius: r)
        let engine = StrongField.engine(StrongField.circularPair(mass: mass, radius: r, speedFactor: 1))

        let dt = expected / 4000
        var swept = 0.0
        var time = 0.0
        var previousAngle = 0.0
        while swept < 2 * .pi, time < 2 * expected {
            engine.step(dt: dt)
            time += dt
            let relative = engine.bodies[1].position - engine.bodies[0].position
            let angle = atan2(relative.y, relative.x)
            swept += remainder(angle - previousAngle, 2 * .pi)
            previousAngle = angle
        }
        #expect(!engine.metrics.isAbsorbed)
        #expect(abs(time / expected - 1) < 0.02)

        let grPeriod = 2 * .pi * sqrt(r * r * r / mass)
        #expect(grPeriod > expected * 1.2)
    }

    /// Far from the hole the precession per orbit is GR's 6πM/(a(1 − e²)).
    @Test func weakFieldPrecessionMatchesGR() throws {
        var config = StrongField.config(distanceRs: 100)
        config.advanced.initial.eccentricity = 0.2
        let bodies = InitialConditions.twoBody(config: config)
        let engine = GravitySimulationEngine(
            bodies: bodies, settings: config.advanced.engine, scale: config.scale,
            timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        engine.isBlackHoleMode = true

        let mass = config.simulationMass1 + config.simulationMass2
        let a = config.simulationSeparation
        let e = 0.2
        let period = 2 * .pi * sqrt(a * a * a / mass)
        StrongField.run(engine, period: period, periods: 8, stepsPerPeriod: 4000)

        let orbits = engine.metrics.orbitsCompleted
        try #require(orbits >= 5)
        let measured = engine.metrics.precessionAngle * .pi / 180 / Double(orbits)
        let predicted = 6 * .pi * mass / (a * (1 - e * e))
        #expect(abs(measured / predicted - 1) < 0.05)
    }

    /// A probe started inside the photon sphere falls through the horizon, and
    /// as a point mass it sheds no bleed particles on the way.
    @Test func probeInsideThePhotonSphereIsAbsorbedWithoutBleeding() {
        let config = StrongField.config(distanceRs: 1.5)
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), scale: config.scale,
            timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        engine.isBlackHoleMode = true
        let mass = config.simulationMass1
        StrongField.run(engine, period: StrongField.forceLawPeriod(mass: mass, radius: 8 * mass),
                        periods: 5, stepsPerPeriod: 2000)
        #expect(engine.metrics.isAbsorbed)
        #expect(engine.metrics.isBlackHole)
        #expect(engine.bleedParticles.isEmpty)
    }
}

// MARK: - Timing

struct StrongFieldTimingTests {

    @Test func timeRatioKeepsVisualStepsPerOrbit() {
        let config = StrongField.config()
        let ratio = ScenarioTiming.timeRatio(config: config)
        let strongTime = ScenarioTiming.referenceTime(
            bodies: InitialConditions.twoBody(config: config), constants: config.scale.constants
        )
        let visualTime = ScenarioTiming.referenceTime(
            bodies: InitialConditions.twoBody(config: SimulationConfig()), constants: ScaleProfile.visual.constants
        )
        let strongStepsPerOrbit = strongTime / (config.timeStep * ratio)
        let visualStepsPerOrbit = visualTime / SimulationConfig().timeStep
        #expect(abs(strongStepsPerOrbit / visualStepsPerOrbit - 1) < 1e-12)

        // ≈ 10 µs per step at 8 rₛ around 10 M☉.
        let stepSeconds = config.timeStep * ratio * config.scale.units.secondsPerTime
        #expect(abs(stepSeconds - 10.2e-6) < 0.3e-6)
    }

    @Test func tenMillisecondsPerSecondPlansAboutSixteenStepsPerFrame() {
        let config = StrongField.config()
        let timeStep = config.timeStep * ScenarioTiming.timeRatio(config: config)
        let rate = config.advanced.time.activeRate(strongField: true)
        #expect(rate == .tenMilliseconds)

        var planner = FrameStepPlanner()
        let frames = 60
        let total = (0..<frames).reduce(0) { sum, _ in
            sum + planner.steps(
                rateSecondsPerSecond: rate.simulatedSecondsPerSecond, timeStep: timeStep,
                secondsPerTime: config.scale.units.secondsPerTime
            )
        }
        let exactPerFrame = 0.01 / 60 / (timeStep * config.scale.units.secondsPerTime)
        #expect(abs(Double(total) - exactPerFrame * Double(frames)) <= 1)
        #expect((15...18).contains(total / frames))
    }

    @Test func rateChoicesDependOnTheRegime() {
        #expect(RealTimeRate.choices(strongField: true).contains(.tenMilliseconds))
        #expect(!RealTimeRate.choices(strongField: true).contains(.oneMonth))
        #expect(RealTimeRate.choices(strongField: false).contains(.oneMonth))
        #expect(!RealTimeRate.choices(strongField: false).contains(.oneMillisecond))
        #expect(abs(RealTimeRate.tenMicroseconds.simulatedSecondsPerSecond - 1e-5) < 1e-18)
        #expect(RealTimeRate.oneMillisecond.label == "1 s = 1 ms")
    }
}

// MARK: - Formatting

struct StrongFieldFormattingTests {

    @Test(arguments: [
        (4.5e-3, "4.5 ms"),
        (820e-6, "820 µs"),
        (0.25, "250 ms"),
        (0.0, "0 s")
    ])
    func subSecondDurations(seconds: Double, expected: String) {
        let units = StrongField.profile.units
        #expect(RealUnitsFormatter.duration(seconds / units.secondsPerTime, units: units) == expected)
    }

    @Test func badgeNamesTheBlackHoleAndTheRate() {
        let text = ScaleBadgeView.text(config: StrongField.config(), achievedRate: nil)
        #expect(text == "Realistic · 10 M☉ black hole · 1 s = 10 ms · sizes not to scale")
    }

    @Test func metricsShowKilometresAndDegrees() {
        let config = StrongField.config()
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 20
        metrics.separation = 160
        metrics.precessionAngle = 42.5
        metrics.isBlackHole = true
        let text = MetricsText(config: config)
        #expect(text.schwarzschildRadius(metrics).value == "29.5 km")
        #expect(text.precession(metrics) == "42.50°")
        // τ/t = √(1 − 1/8) = 0.935.
        #expect(text.timeDilation(metrics) == "\u{03C4}/t = 0.935")
    }
}

// MARK: - View Model

@MainActor
struct StrongFieldViewModelTests {

    private final class SetupLog: @unchecked Sendable {
        var setups: [EngineSetup] = []
    }

    private func makeViewModel() -> (SimulationViewModel, SetupLog) {
        let log = SetupLog()
        let viewModel = SimulationViewModel { setup in
            log.setups.append(setup)
            return MockSimulationEngine(bodies: setup.bodies, settings: setup.settings, scale: setup.scale)
        }
        viewModel.setup(canvasSize: CGSize(width: 400, height: 400))
        return (viewModel, log)
    }

    @Test func togglingBlackHoleModeInRealisticSwitchesProfiles() {
        let (viewModel, log) = makeViewModel()
        viewModel.selectScale(.realistic)
        #expect(log.setups.last?.scale == .realisticPlanetary)

        viewModel.config.isBlackHoleMode = true
        viewModel.applyConfigChange(canvasSize: CGSize(width: 400, height: 400))
        #expect(log.setups.last?.scale == .realisticStrongField)
        #expect(log.setups.last?.bodies.first?.mass == 10)
        #expect(viewModel.activeRealTimeRate == .tenMilliseconds)

        viewModel.config.isBlackHoleMode = false
        viewModel.applyConfigChange(canvasSize: CGSize(width: 400, height: 400))
        #expect(log.setups.last?.scale == .realisticPlanetary)
        #expect(viewModel.activeRealTimeRate == .oneMonth)
    }

    @Test func resetRestoresTheStrongFieldSliders() {
        let (viewModel, _) = makeViewModel()
        viewModel.config.strongFieldBlackHoleMass = 60
        viewModel.config.strongFieldDistanceRs = 25
        viewModel.reset(canvasSize: CGSize(width: 400, height: 400))
        #expect(viewModel.config.strongFieldBlackHoleMass == 10)
        #expect(viewModel.config.strongFieldDistanceRs == 8)
    }
}
