//
//  RealisticScaleTests.swift
//  CosmicPathSwiftTests
//
//  Issue #21, PR 2: the Realistic planetary scale. Real constants in AU, M☉
//  and days must reproduce the Sun's rₛ, Earth's year and Mercury's 43″ per
//  century, while the Visual scale stays untouched.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

/// Configs and small integrators shared by the Realistic tests.
private enum Realistic {
    static let profile = ScaleProfile.realisticPlanetary

    /// Default config in the Realistic scale.
    static func config(mode: SimulationMode = .twoBody) -> SimulationConfig {
        var config = SimulationConfig()
        config.mode = mode
        config.advanced.scale = .realistic
        return config
    }

    /// Mercury: a = 0.387 AU, e = 0.2056, 0.055 M⊕, Yoshida 4.
    static var mercury: SimulationConfig {
        var config = config()
        config.separationAU = 0.387
        config.mass2Multiplier = 0.055
        config.advanced.initial.eccentricity = 0.2056
        config.advanced.engine.integrator = .yoshida4
        return config
    }

    /// Time step the view model would use for `config`.
    static func timeStep(_ config: SimulationConfig) -> Double {
        config.timeStep * ScenarioTiming.timeRatio(config: config)
    }

    static func relative(_ bodies: [CelestialBody]) -> (r: Vector3D, v: Vector3D) {
        (bodies[1].position - bodies[0].position, bodies[1].velocity - bodies[0].velocity)
    }

    /// Kepler period of the relative orbit at t = 0.
    static func period(_ bodies: [CelestialBody], profile: ScaleProfile) throws -> Double {
        let (r, v) = relative(bodies)
        let elements = OrbitalElements.osculating(
            relativePosition: r, relativeVelocity: v,
            totalMass: NBodyGravity.totalMass(bodies), constants: profile.constants
        )
        return try #require(elements.period)
    }

    /// Mean periapsis advance per orbit (radians), from the eccentricity vector
    /// at each sampled separation minimum over `orbits` orbits.
    static func precessionPerOrbit(config: SimulationConfig, grEnabled: Bool, orbits: Int) -> Double {
        let constants = config.scale.constants
        let softening = config.scale.softening(for: config.advanced.engine)
        let dt = timeStep(config)
        var bodies = NBodyGravity.withAccelerations(
            InitialConditions.twoBody(config: config), softening: softening, grEnabled: grEnabled, constants: constants
        )
        var angles: [Double] = []
        var previous = relative(bodies).r.magnitude
        var wasShrinking = true
        while angles.count <= orbits {
            bodies = IntegratorKind.yoshida4.step(
                bodies, dt: dt, softening: softening, grEnabled: grEnabled, constants: constants
            )
            let (r, v) = relative(bodies)
            let isShrinking = r.magnitude < previous
            if wasShrinking && !isShrinking {
                angles.append(OrbitalElements.periapsisAngle(
                    relativePosition: r, relativeVelocity: v,
                    totalMass: NBodyGravity.totalMass(bodies), constants: constants
                ))
            }
            wasShrinking = isShrinking
            previous = r.magnitude
        }
        let total = zip(angles, angles.dropFirst()).reduce(0.0) { sum, pair in
            sum + remainder(pair.1 - pair.0, 2 * .pi)
        }
        return total / Double(angles.count - 1)
    }

    static func arcsecondsPerCentury(radiansPerOrbit: Double, period: Double) -> Double {
        radiansPerOrbit * 180 / .pi * 3600 * SIConstants.daysPerJulianCentury / period
    }
}

// MARK: - Constants

struct RealisticConstantsTests {
    private let profile = Realistic.profile

    @Test func sunSchwarzschildRadiusIsAbout2953Meters() {
        let rs = profile.constants.schwarzschildRadius(mass: profile.solarMass) * SIConstants.astronomicalUnit
        #expect(abs(rs - 2953.25) / 2953.25 < 1e-3)
    }

    @Test func speedOfLightConvertsBackToSI() {
        let c = profile.constants.c * SIConstants.astronomicalUnit / SIConstants.secondsPerDay
        #expect(abs(c - SIConstants.speedOfLight) / SIConstants.speedOfLight < 1e-12)
    }

    @Test func gravitationalConstantMatchesSI() {
        let au = SIConstants.astronomicalUnit
        let gmSun = profile.constants.G * au * au * au / (SIConstants.secondsPerDay * SIConstants.secondsPerDay)
        let siGMSun = SIConstants.gravitationalConstant * SIConstants.solarMass
        #expect(abs(gmSun - siGMSun) / siGMSun < 1e-4)
    }

    @Test func unitsAreAUSolarMassAndDay() {
        #expect(profile.au == 1)
        #expect(profile.solarMass == 1)
        #expect(abs(profile.earthMass - 3.0035e-6) < 1e-9)
        #expect(profile.units.secondsPerTime == 86_400)
        #expect(profile.units.lengthSymbol == "AU")
        #expect(profile.unitsDescription == "AU, M☉, day (G = k², c = 173.14 AU/day)")
    }

    @Test func softeningIsFixedAt150Kilometres() {
        var settings = EngineSettings()
        settings.softening = 20
        #expect(profile.softening(for: settings) == 1e-6)
        #expect(ScaleProfile.visual.softening(for: settings) == 20)
        settings.softening = 0.1
        #expect(ScaleProfile.visual.softening(for: settings) == settings.effectiveSoftening)
    }

    @Test func starsTouchAtTheSumOfTheirRadii() {
        let radius = profile.starSurfaceRadius(mass: 1, softening: 1e-6)
        #expect(abs(radius - SIConstants.solarRadius / SIConstants.astronomicalUnit) < 1e-12)
        let distance = profile.collisionDistance(massA: 4, massB: 5, softening: 1e-6)
        #expect(abs(distance - radius * (pow(4, 0.8) + pow(5, 0.8))) < 1e-12)
        #expect(distance < 0.032)
    }
}

// MARK: - Orbits

struct RealisticOrbitTests {

    @Test func sunEarthPeriodIsOneSiderealYear() throws {
        let config = Realistic.config()
        let dt = Realistic.timeStep(config)
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), settings: config.advanced.engine,
            scale: config.scale, timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        var unwrapped = 0.0
        var previousAngle = 0.0
        var time = 0.0
        var period: Double?
        while period == nil, time < 400 {
            engine.step(dt: dt)
            time += dt
            let r = engine.bodies[1].position - engine.bodies[0].position
            let angle = atan2(r.y, r.x)
            let advance = remainder(angle - previousAngle, 2 * .pi)
            if unwrapped + advance >= 2 * .pi {
                let fraction = (2 * .pi - unwrapped) / advance
                period = time - dt + fraction * dt
            }
            unwrapped += advance
            previousAngle = angle
        }
        let year = try #require(period)
        #expect(abs(year - 365.256) / 365.256 < 1e-3)
    }

    @Test func mercuryGRPrecessionIs43ArcsecondsPerCentury() throws {
        let config = Realistic.mercury
        let period = try Realistic.period(InitialConditions.twoBody(config: config), profile: config.scale)
        let withGR = Realistic.precessionPerOrbit(config: config, grEnabled: true, orbits: 50)
        let withoutGR = Realistic.precessionPerOrbit(config: config, grEnabled: false, orbits: 50)
        let perCentury = Realistic.arcsecondsPerCentury(radiansPerOrbit: withGR - withoutGR, period: period)
        #expect(abs(perCentury - 43.0) / 43.0 < 0.03)
    }

    @Test func engineWithYoshidaMeasuresMercuryPrecession() throws {
        let config = Realistic.mercury
        let bodies = InitialConditions.twoBody(config: config)
        let period = try Realistic.period(bodies, profile: config.scale)
        let engine = GravitySimulationEngine(
            bodies: bodies, settings: config.advanced.engine, scale: config.scale,
            timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        // Yoshida's own precession at the default step (~480 steps per Mercury
        // orbit) is larger than GR's; Accuracy ×¼ cuts it 256-fold.
        let dt = Realistic.timeStep(config) * 0.25
        while engine.metrics.orbitsCompleted < 50 {
            engine.step(dt: dt)
        }
        let degreesPerOrbit = engine.metrics.precessionAngle / Double(engine.metrics.orbitsCompleted)
        let perCentury = Realistic.arcsecondsPerCentury(radiansPerOrbit: degreesPerOrbit * .pi / 180, period: period)
        #expect(abs(perCentury - 43.0) / 43.0 < 0.05)
    }

    @Test(arguments: [PhysicsScale.visual, .realistic])
    func energyDriftStaysBoundedOver100Orbits(scale: PhysicsScale) throws {
        var config = SimulationConfig()
        config.advanced.scale = scale
        let constants = config.scale.constants
        let softening = config.scale.softening(for: config.advanced.engine)
        let dt = Realistic.timeStep(config)
        var bodies = NBodyGravity.withAccelerations(
            InitialConditions.twoBody(config: config), softening: softening, grEnabled: false, constants: constants
        )
        let steps = Int(100 * (try Realistic.period(bodies, profile: config.scale)) / dt)
        let initial = NBodyGravity.newtonianEnergy(bodies, softening: softening, constants: constants)
        var worst = 0.0
        for _ in 0..<steps {
            bodies = IntegratorKind.velocityVerlet.step(
                bodies, dt: dt, softening: softening, grEnabled: false, constants: constants
            )
            let energy = NBodyGravity.newtonianEnergy(bodies, softening: softening, constants: constants)
            worst = max(worst, abs((energy - initial) / initial))
        }
        #expect(worst < 1e-4)
    }
}

// MARK: - Timing

struct ScenarioTimingTests {

    @Test(arguments: SimulationMode.allCases)
    func visualTimeRatioIsExactlyOne(mode: SimulationMode) {
        var config = SimulationConfig()
        config.mode = mode
        #expect(ScenarioTiming.timeRatio(config: config) == 1)
    }

    @Test func realisticKeepsVisualStepsPerOrbit() throws {
        // A light planet, so both orbits are circular: Visual gives the planet
        // the circular speed for the star's mass alone, so its 40:1 default
        // pair starts slightly eccentric (e ≈ 0.025) and takes ~4% longer.
        var visual = SimulationConfig()
        visual.mass2Multiplier = 0.1
        var realistic = Realistic.config()
        realistic.mass2Multiplier = 0.1
        let visualSteps = try Self.stepsPerOrbit(visual)
        let realisticSteps = try Self.stepsPerOrbit(realistic)
        #expect(abs(realisticSteps - visualSteps) / visualSteps < 0.01)
        // Earth: dt ≈ 0.208 days, about 1,760 steps per year.
        #expect(abs(Realistic.timeStep(Realistic.config()) - 0.2079) < 0.001)
    }

    /// Steps the engine takes until the planet's angle has turned by 2π,
    /// interpolated within the last step.
    private static func stepsPerOrbit(_ config: SimulationConfig) throws -> Double {
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.twoBody(config: config), settings: config.advanced.engine, scale: config.scale
        )
        let dt = Realistic.timeStep(config)
        var turned = 0.0
        var previousAngle = 0.0
        var steps = 0
        while steps < 100_000 {
            engine.step(dt: dt)
            steps += 1
            let r = engine.bodies[1].position - engine.bodies[0].position
            let angle = atan2(r.y, r.x)
            let advance = remainder(angle - previousAngle, 2 * .pi)
            if turned + advance >= 2 * .pi {
                return Double(steps - 1) + (2 * .pi - turned) / advance
            }
            turned += advance
            previousAngle = angle
        }
        Issue.record("No full orbit within \(steps) steps")
        return 0
    }

    @Test func referenceTimeUsesTheFastestPair() {
        var config = Realistic.config(mode: .threeBody)
        config.threeBodyPreset = .sunPlanetMoon
        let bodies = InitialConditions.threeBody(preset: .sunPlanetMoon, config: config)
        let earthMoon = Array(bodies[1...2])
        let constants = config.scale.constants
        #expect(ScenarioTiming.referenceTime(bodies: bodies, constants: constants)
                == ScenarioTiming.referenceTime(bodies: earthMoon, constants: constants))
    }

    @Test func oneDayPerSecondGivesAFractionOfAStepPerFrame() {
        var planner = FrameStepPlanner()
        let frames = 1000
        let total = (0..<frames).reduce(0) { sum, _ in
            sum + planner.steps(rateSecondsPerSecond: 86_400, timeStep: 0.2026, secondsPerTime: 86_400)
        }
        #expect(abs(Double(total) / Double(frames) - 0.0823) < 0.001)
        #expect(!planner.isSpeedLimited)
    }

    @Test func capLimitsTheRateAndReportsTheAchievedRate() {
        var planner = FrameStepPlanner()
        let steps = planner.steps(
            rateSecondsPerSecond: RealTimeRate.hundredYears.simulatedSecondsPerSecond,
            timeStep: 0.2026, secondsPerTime: 86_400, maxSteps: 10
        )
        #expect(steps == 10)
        #expect(planner.isSpeedLimited)
        let achieved = FrameStepPlanner.achievedRate(steps: 10, timeStep: 0.2026, secondsPerTime: 86_400)
        #expect(abs(achieved - 10 * 0.2026 * 86_400 * 60) < 1e-6)
    }

    @Test func defaultRateIsOneMonth() {
        #expect(TimeSettings().realisticRate == .oneMonth)
        #expect(RealTimeRate.oneMonth.label == "1 s = 1 month")
        #expect(abs(RealTimeRate.oneMonth.simulatedSecondsPerSecond / 86_400 - 30.4375) < 1e-9)
    }
}

// MARK: - 3-Body Presets

struct RealisticPresetTests {

    private static func config(_ preset: ThreeBodyPreset) -> SimulationConfig {
        var config = Realistic.config(mode: .threeBody)
        config.threeBodyPreset = preset
        config.timeStep = preset.timeStep
        config.stepsPerFrame = preset.stepsPerFrame
        return config
    }

    @Test(arguments: ThreeBodyPreset.allCases)
    func presetsStartInTheCoMFrameApart(preset: ThreeBodyPreset) {
        let config = Self.config(preset)
        let bodies = InitialConditions.threeBody(preset: preset, config: config)
        let scale = config.scale
        let softening = scale.softening(for: config.advanced.engine)
        #expect(NBodyGravity.centerOfMass(bodies).magnitude < 1e-12)
        let momentumScale = bodies.map { $0.mass * $0.velocity.magnitude }.max() ?? 1
        #expect(NBodyGravity.totalMomentum(bodies).magnitude <= 1e-12 * momentumScale)
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let distance = (bodies[i].position - bodies[j].position).magnitude
                #expect(distance > scale.collisionDistance(
                    massA: bodies[i].mass, massB: bodies[j].mass, softening: softening
                ))
            }
        }
    }

    @Test func pythagoreanSurvivesItsFirstCloseEncounter() {
        let config = Self.config(.pythagorean)
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.threeBody(preset: .pythagorean, config: config),
            settings: config.advanced.engine, scale: config.scale,
            timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        let dt = Realistic.timeStep(config)
        // The first close encounter comes at about 1.9 time units of √(L³/GM) ≈ 1,840 days.
        while engine.systemMetrics.elapsedTime < 5_000 {
            engine.step(dt: dt)
        }
        #expect(engine.systemMetrics.closestApproach < 0.3)
        #expect(engine.systemMetrics.collision == nil)
        #expect(engine.bodies.count == 3)
    }

    @Test func moonStaysBoundToEarthForAYear() {
        let config = Self.config(.sunPlanetMoon)
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.threeBody(preset: .sunPlanetMoon, config: config),
            settings: config.advanced.engine, scale: config.scale,
            timeRatio: ScenarioTiming.timeRatio(config: config)
        )
        let dt = Realistic.timeStep(config)
        let lunarMonth = 27.32
        let initialDistance = InitialConditions.SunEarthMoon.moonDistanceAU
        var farthest = 0.0
        while engine.systemMetrics.elapsedTime < 12 * lunarMonth {
            engine.step(dt: dt)
            let distance = (engine.bodies[2].position - engine.bodies[1].position).magnitude
            farthest = max(farthest, distance)
        }
        #expect(engine.bodies.count == 3)
        #expect(farthest < 1.2 * initialDistance)
    }
}

// MARK: - Scale Toggle

@MainActor
struct ScaleToggleTests {

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

    @Test func selectingRealisticRestartsWithTheRealisticProfile() {
        let (viewModel, log) = makeViewModel()
        viewModel.selectScale(.realistic)
        let setup = log.setups.last
        #expect(log.setups.count == 2)
        #expect(setup?.scale == .realisticPlanetary)
        #expect((setup?.timeRatio ?? 1) > 1)
        #expect(abs(viewModel.effectiveTimeStep - 0.2079) < 0.001)
    }

    /// PR 3: Black Hole Mode survives the switch and selects the strong-field profile.
    @Test func selectingRealisticKeepsBlackHoleModeInStrongField() {
        let (viewModel, log) = makeViewModel()
        viewModel.config.isBlackHoleMode = true
        viewModel.config.separationAU = 1.3
        viewModel.selectScale(.realistic)
        #expect(viewModel.config.isBlackHoleMode)
        #expect(viewModel.config.isStrongField)
        #expect(log.setups.last?.scale == .realisticStrongField)
    }

    @Test func restoreDefaultsReturnsToVisualAndResetKeepsTheScale() {
        let (viewModel, log) = makeViewModel()
        viewModel.selectScale(.realistic)
        viewModel.reset(canvasSize: CGSize(width: 400, height: 400))
        #expect(viewModel.config.advanced.scale == .realistic)
        #expect(log.setups.last?.scale == .realisticPlanetary)
        viewModel.restoreAdvancedDefaults()
        #expect(viewModel.config.advanced.scale == .visual)
        #expect(log.setups.last?.scale == .visual)
        #expect(viewModel.effectiveTimeStep == SimulationConfig().timeStep)
    }

    @Test func realisticRunsAtTheChosenRate() {
        let (viewModel, _) = makeViewModel()
        viewModel.selectScale(.realistic)
        viewModel.config.advanced.time.realisticRate = .oneYear
        for _ in 0..<FrameStepPlanner.framesPerSecond {
            viewModel.tick()
        }
        // One second of frames at 1 s = 1 year advances 365.25 days, to within a step.
        #expect(abs(viewModel.metrics.elapsedTime - 365.25) < viewModel.effectiveTimeStep * 1.01)
    }
}

// MARK: - Formatting

struct RealUnitsFormatterTests {
    private let units = ScaleProfile.realisticPlanetary.units

    @Test(arguments: [
        (30.0 / 86_400, "30 s"),
        (0.0025, "3.6 min"),
        (0.25, "6.0 h"),
        (27.32, "27.3 days"),
        (365.25 * 1.5, "1.50 years"),
        (365.25 * 300, "300 years")
    ])
    func durations(days: Double, expected: String) {
        #expect(RealUnitsFormatter.duration(days, units: units) == expected)
    }

    @Test(arguments: [
        (0.387, "0.387 AU"),
        (0.0025695, "384392 km"),
        (1.974e-8, "2.95 km")
    ])
    func lengths(au: Double, expected: String) {
        #expect(RealUnitsFormatter.length(au, units: units) == expected)
    }

    @Test(arguments: [
        (9.9e-9, "9.9×10⁻⁹"),
        (9.97e-9, "1.0×10⁻⁸"),
        (0.5, "0.5"),
        (1.69e6, "1.7×10⁶"),
        (-2.5e-5, "−2.5×10⁻⁵"),
        (0.0, "0")
    ])
    func scientific(value: Double, expected: String) {
        #expect(RealUnitsFormatter.scientific(value) == expected)
    }

    @Test func deviationsFromOne() {
        #expect(RealUnitsFormatter.deviation(fromOne: 1 - 9.9e-9) == "1 − 9.9×10⁻⁹")
        #expect(RealUnitsFormatter.deviation(fromOne: 1) == "1")
    }

    @Test func precessionPerCentury() {
        // Mercury: 0.1035″ per 87.97-day orbit is 43.0″ per century.
        let degrees = 0.1035 / 3600
        let value = RealUnitsFormatter.arcsecondsPerCentury(degreesPerOrbit: degrees, period: 87.969, units: units)
        #expect(abs((value ?? 0) - 42.97) < 0.05)
        #expect(RealUnitsFormatter.perCentury(degreesPerOrbit: degrees, period: 87.969, units: units) == "43.0″/century")
        #expect(RealUnitsFormatter.arcseconds(degrees: 0.1036 / 3600) == "0.104″")
        #expect(RealUnitsFormatter.isTooSmallToSee(precessionDegreesPerOrbit: degrees))
        #expect(!RealUnitsFormatter.isTooSmallToSee(precessionDegreesPerOrbit: 2))
    }

    @Test func smallRelativisticQuantitiesAvoidCancellation() {
        let beta = 1e-4
        #expect(abs(RealUnitsFormatter.gammaMinusOne(beta: beta) - 5e-9) / 5e-9 < 1e-6)
        let x = 2e-8
        #expect(abs(RealUnitsFormatter.oneMinusSqrtOneMinus(x) - 1e-8) / 1e-8 < 1e-6)
    }

    @Test func speedAndSchwarzschildRadius() {
        let earthSpeed = 2 * Double.pi / 365.25   // AU/day
        #expect(RealUnitsFormatter.speed(earthSpeed, units: units) == "29.8 km/s")
        let rs = ScaleProfile.realisticPlanetary.constants.schwarzschildRadius(mass: 1)
        #expect(RealUnitsFormatter.schwarzschildRadius(rs, units: units) == "2.95 km")
    }

    @Test func magnification() {
        #expect(RealUnitsFormatter.magnification(1.69e6) == "1.7 million×")
        #expect(RealUnitsFormatter.magnification(2.1e5) == "210 thousand×")
    }
}

// MARK: - GR Magnification

struct ScaleComparisonTests {

    @Test func oneSolarMassStarIsMagnifiedAbout1point69Million() {
        let factor = ScaleComparison.grMagnification(config: SimulationConfig())
        #expect(abs(factor - 1.69e6) / 1.69e6 < 0.01)
        var realistic = SimulationConfig()
        realistic.advanced.scale = .realistic
        #expect(ScaleComparison.grMagnification(config: realistic) == factor)
    }

    @Test func blackHoleModeIsMagnifiedMore() {
        var config = SimulationConfig()
        config.isBlackHoleMode = true
        let factor = ScaleComparison.grMagnification(config: config)
        #expect(abs(factor / ScaleComparison.grMagnification(config: SimulationConfig()) - 25) < 1e-9)
    }
}

// MARK: - Labels

struct RealisticLabelTests {

    @Test func csvHeaderDescribesTheRealisticUnits() {
        let header = DiagnosticsCSV.header(config: Realistic.config())
        #expect(header.contains("# units: AU, M☉, day (G = k², c = 173.14 AU/day)"))
        #expect(header.contains("# scale: realistic"))
        let softening = header.first { $0.hasPrefix("# softening_AU: ") }?.split(separator: " ").last
        #expect(softening.flatMap { Double($0) } == 1e-6)
        #expect(header.contains { $0.hasPrefix("# time_step: 0.20") })
    }

    @Test func csvHeaderKeepsTheVisualValues() {
        let header = DiagnosticsCSV.header(config: SimulationConfig())
        #expect(header.contains("# time_step: 0.02"))
        #expect(header.contains("# softening_px: 5"))
        #expect(header.contains("# scale: visual"))
    }

    @Test func badgeSaysWhichScaleIsActive() {
        #expect(ScaleBadgeView.text(config: SimulationConfig(), achievedRate: nil)
                == "Visual · GR magnified ≈ 1.7 million×")
        #expect(ScaleBadgeView.text(config: Realistic.config(), achievedRate: nil)
                == "Realistic · 1 s = 1 month · sizes not to scale")
        #expect(ScaleBadgeView.text(config: Realistic.config(), achievedRate: 3.2 * 86_400)
                == "Realistic · 1 s = 3.2 days (CPU-limited) · sizes not to scale")
    }

    @Test func visualMetricsKeepTheirOriginalFormat() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.983
        metrics.precessionAngle = 12.345
        metrics.lorentzGamma = 1.0123
        let text = MetricsText(config: SimulationConfig())
        #expect(text.timeDilation(metrics) == "τ/t = 0.983")
        #expect(text.precession(metrics) == "12.35°")
        #expect(text.velocityFraction(0.1234) == "0.123")
        #expect(text.lorentz(metrics).value == "1.0123")
        #expect(text.orbits(metrics).label == "Orbits")
    }

    @Test func realisticMetricsShowDeviationsAndRealUnits() {
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 1.974e-8
        metrics.separation = 1
        metrics.velocityFractionOfC = 9.9e-5
        metrics.precessionAngle = 0.1 / 3600
        metrics.orbitsCompleted = 1
        metrics.elapsedTime = 365.25
        let text = MetricsText(config: Realistic.config())
        #expect(text.timeDilation(metrics) == "τ/t = 1 − 9.9×10⁻⁹")
        #expect(text.precession(metrics) == "0.1″")
        #expect(text.precessionLabel(metrics) == "Precession (too small to see)")
        #expect(text.velocityFraction(metrics.velocityFractionOfC) == "9.9×10⁻⁵")
        #expect(text.orbits(metrics).value == "1.00 years")
    }
}

// MARK: - Mass Legend

/// The 3-body legend shows real units in Realistic mode, picking M☉ or M⊕ so
/// labels stay short (they used to read e.g. "B 3e-06" and wrapped on a phone).
@MainActor
struct RealisticLegendTests {
    private let canvas = CGSize(width: 400, height: 300)

    private func legend(for preset: ThreeBodyPreset) -> [String] {
        let viewModel = SimulationViewModel { MockSimulationEngine(bodies: $0.bodies) }
        viewModel.config.mode = .threeBody
        viewModel.config.threeBodyPreset = preset
        viewModel.selectScale(.realistic)
        viewModel.setup(canvasSize: canvas)
        return viewModel.bodyLabels
    }

    @Test func massLabelsPickSolarOrEarthMasses() {
        let scale = ScaleProfile.realisticPlanetary
        #expect(RealUnitsFormatter.mass(3 * scale.solarMass, scale: scale) == "3 M\u{2609}")
        #expect(RealUnitsFormatter.mass(scale.earthMass, scale: scale) == "1 M\u{2295}")
        #expect(RealUnitsFormatter.mass(0.0123 * scale.earthMass, scale: scale) == "0.0123 M\u{2295}")
    }

    @Test func sunEarthMoonLegendUsesRealUnits() {
        #expect(legend(for: .sunPlanetMoon) == ["A 1 M\u{2609}", "B 1 M\u{2295}", "C 0.0123 M\u{2295}"])
    }

    @Test func pythagoreanLegendIsInSolarMasses() {
        #expect(legend(for: .pythagorean) == ["A 3 M\u{2609}", "B 4 M\u{2609}", "C 5 M\u{2609}"])
    }
}
