//
//  InitialConditionsTests.swift
//  CosmicPathSwiftTests
//
//  Starting conditions from the Advanced sheet (issue #20, PR 4): eccentric
//  2-body orbits, the periapsis angle, danger-zone warnings, and the 3-body
//  chaos nudge. The defaults must reproduce the original starting conditions.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

/// Copy of `InitialConditions.twoBody` as it was before PR 4 (circular orbit,
/// planet on the x-axis), used to check the defaults are unchanged bit for bit.
private func legacyTwoBody(config: SimulationConfig) -> [CelestialBody] {
    let G = GravitySimulationEngine.G
    let mass1 = config.simulationMass1
    let mass2 = config.simulationMass2
    let rs = 2.0 * G * mass1 / GravitySimulationEngine.cSquared
    let separation = max(config.simulationSeparation, GravitySimulationEngine.softening * 2)
    let isco = 3.0 * rs
    let orbitalSpeed = separation >= isco
        ? sqrt(G * mass1 / (separation - 1.5 * rs))
        : sqrt(G * mass1 / separation)
    let inclination = config.inclinationRad
    let planetVelocity = Vector3D(x: 0, y: orbitalSpeed * cos(inclination), z: orbitalSpeed * sin(inclination))
    let starVelocity = planetVelocity * -(mass2 / mass1)
    return [
        CelestialBody(id: 0, kind: .star, mass: mass1, position: .zero, velocity: starVelocity),
        CelestialBody(id: 1, kind: .planet, mass: mass2,
                      position: Vector3D(x: separation, y: 0, z: 0), velocity: planetVelocity)
    ]
}

private func twoBodyConfig(
    eccentricity: Double = 0,
    periapsisDeg: Double = 0,
    separationAU: Double = 1,
    inclinationDeg: Double = 0,
    blackHole: Bool = false
) -> SimulationConfig {
    var config = SimulationConfig()
    config.separationAU = separationAU
    config.inclinationDeg = inclinationDeg
    config.isBlackHoleMode = blackHole
    config.advanced.initial.eccentricity = eccentricity
    config.advanced.initial.periapsisAngleDeg = periapsisDeg
    return config
}

/// Configurations covering both speed branches, black hole mode, and inclination.
private let legacyCases: [SimulationConfig] = {
    var heavy = SimulationConfig()
    heavy.mass1Multiplier = 7
    heavy.mass2Multiplier = 3
    return [
        SimulationConfig(),
        twoBodyConfig(blackHole: true),                    // 1.3 AU default is inside the ISCO
        twoBodyConfig(separationAU: 1.0 / 3.0, blackHole: true),
        twoBodyConfig(separationAU: 2.5, inclinationDeg: 40),
        heavy
    ]
}()

// MARK: - Two-Body

struct EccentricOrbitTests {

    @Test(arguments: legacyCases)
    func defaultsMatchTheOriginalStartBitForBit(config: SimulationConfig) {
        let current = InitialConditions.twoBody(config: config)
        let legacy = legacyTwoBody(config: config)
        #expect(current.map(\.position) == legacy.map(\.position))
        #expect(current.map(\.velocity) == legacy.map(\.velocity))
        #expect(current.map(\.mass) == legacy.map(\.mass))
    }

    @Test(arguments: [0.1, 0.5, 0.9])
    func planetStartsAtPeriapsis(eccentricity: Double) {
        let config = twoBodyConfig(eccentricity: eccentricity)
        let bodies = InitialConditions.twoBody(config: config)
        let expected = CelestialConstants.baseAU * (1 - eccentricity)
        #expect(abs(bodies[1].position.magnitude - expected) < 1e-9)
        #expect(InitialConditions.periapsisDistance(config: config) == bodies[1].position.magnitude)
    }

    /// Over one orbit the separation swings between a(1 − e) and a(1 + e) with
    /// the real engine (GR on, star free to move). The starting speed solves for
    /// those turning points exactly, so only integration error remains.
    @Test func orbitSpansPeriapsisToApoapsis() {
        let eccentricity = 0.5
        let semiMajorAxis = CelestialConstants.baseAU
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(
            config: twoBodyConfig(eccentricity: eccentricity)
        ))

        var minimum = Double.infinity
        var maximum = 0.0
        for _ in 0..<2500 {   // ~1.4 orbits at dt = 0.02
            engine.step(dt: 0.02)
            let separation = (engine.bodies[1].position - engine.bodies[0].position).magnitude
            minimum = min(minimum, separation)
            maximum = max(maximum, separation)
        }

        let periapsis = semiMajorAxis * (1 - eccentricity)
        let apoapsis = semiMajorAxis * (1 + eccentricity)
        #expect(abs(minimum - periapsis) / periapsis < 0.02, "periapsis \(minimum) vs \(periapsis)")
        #expect(abs(maximum - apoapsis) / apoapsis < 0.02, "apoapsis \(maximum) vs \(apoapsis)")
    }

    /// Far from the mass, GR is negligible and the speed is Newtonian vis-viva.
    @Test func periapsisSpeedReducesToVisVivaFarAway() {
        let mass = 200.0
        let rp = 1e5, ra = 3e5
        let speed = InitialConditions.periapsisSpeed(totalMass: mass, periapsis: rp, apoapsis: ra)
        let visViva = sqrt(2 * GravitySimulationEngine.G * mass * ra / (rp * (rp + ra)))
        #expect(abs(speed! - visViva) / visViva < 1e-4)
    }

    /// As the turning points merge, the speed tends to the GR circular speed.
    @Test func periapsisSpeedReducesToCircularSpeed() {
        let mass = 200.0
        let r = 150.0
        let speed = InitialConditions.periapsisSpeed(totalMass: mass, periapsis: r, apoapsis: r * (1 + 1e-6))
        let rs = 2 * GravitySimulationEngine.G * mass / GravitySimulationEngine.cSquared
        let circular = sqrt(GravitySimulationEngine.G * mass / (r - 1.5 * rs))
        #expect(abs(speed! - circular) / circular < 1e-4)
    }

    /// Deep inside the ISCO no orbit has both turning points.
    @Test func periapsisSpeedIsNilWhenNoSuchOrbitExists() {
        // M = 5000 → rₛ = 125; turning points at 140 and 300 can't both exist.
        #expect(InitialConditions.periapsisSpeed(totalMass: 5000, periapsis: 140, apoapsis: 300) == nil)
    }

    @Test func periapsisAngleRotatesTheStartWithinThePlane() {
        let bodies = InitialConditions.twoBody(config: twoBodyConfig(eccentricity: 0.3, periapsisDeg: 90))
        let planet = bodies[1]
        let angle = atan2(planet.position.y, planet.position.x) * 180 / .pi
        #expect(abs(angle - 90) < 1e-9)
        #expect(abs(planet.position.dot(planet.velocity)) < 1e-9)
    }

    @Test(arguments: [0.0, 45.0, 135.0, 270.0])
    func speedDoesNotDependOnPeriapsisAngle(periapsisDeg: Double) {
        let reference = InitialConditions.twoBody(config: twoBodyConfig(eccentricity: 0.4))
        let rotated = InitialConditions.twoBody(config: twoBodyConfig(eccentricity: 0.4, periapsisDeg: periapsisDeg))
        #expect(abs(rotated[1].velocity.magnitude - reference[1].velocity.magnitude) < 1e-9)
        #expect(abs(rotated[1].position.magnitude - reference[1].position.magnitude) < 1e-9)
    }

    @Test func inclinedOrbitStaysInItsPlane() {
        let inclination = 30.0 * .pi / 180
        let bodies = InitialConditions.twoBody(
            config: twoBodyConfig(eccentricity: 0.4, periapsisDeg: 45, inclinationDeg: 30)
        )
        let planeNormal = Vector3D(x: 1, y: 0, z: 0).cross(Vector3D(x: 0, y: cos(inclination), z: sin(inclination)))
        #expect(abs(bodies[1].position.dot(planeNormal)) < 1e-9)
        #expect(abs(bodies[1].velocity.dot(planeNormal)) < 1e-9)
        #expect(abs(NBodyGravity.totalMomentum(bodies).magnitude) < 1e-9)
    }

    @Test func eccentricityIsClampedToItsRange() {
        let tooHigh = InitialConditions.twoBody(config: twoBodyConfig(eccentricity: 5))
        let maximum = InitialConditions.twoBody(config: twoBodyConfig(eccentricity: 0.9))
        #expect(tooHigh.map(\.position) == maximum.map(\.position))
    }
}

// MARK: - Warnings

struct PeriapsisWarningTests {

    @Test func noWarningByDefault() {
        #expect(InitialConditions.periapsisWarning(config: SimulationConfig()) == nil)
        #expect(InitialConditions.periapsisWarning(config: twoBodyConfig(blackHole: true)) == nil)
    }

    @Test func warnsWhenPeriapsisEntersTheRocheLimit() {
        // a = 1 AU, e = 0.9 → rₚ = 15 px, inside the 43 px Roche limit but outside the 10 px surface.
        let warning = InitialConditions.periapsisWarning(config: twoBodyConfig(eccentricity: 0.9))
        #expect(warning?.contains("Roche") == true)
    }

    @Test func warnsWhenPeriapsisIsInsideTheStar() {
        // a = ⅓ AU, e = 0.9 → rₚ = 5 px, below the 10 px star surface.
        let config = twoBodyConfig(eccentricity: 0.9, separationAU: 1.0 / 3.0)
        #expect(InitialConditions.periapsisWarning(config: config)?.contains("inside the star") == true)
    }

    @Test func warnsWhenPeriapsisIsInsideTheISCO() {
        // a = 3 AU = 450 px is outside the 375 px ISCO; e = 0.3 → rₚ = 315 px is inside.
        let config = twoBodyConfig(eccentricity: 0.3, separationAU: 3, blackHole: true)
        #expect(InitialConditions.periapsisWarning(config: config)?.contains("ISCO") == true)
    }

    @Test func warnsWhenPeriapsisCrossesTheEventHorizon() {
        // Default BH orbit 195 px, e = 0.9 → rₚ = 19.5 px, inside rₛ = 125 px.
        let config = twoBodyConfig(eccentricity: 0.9, separationAU: 1.3, blackHole: true)
        #expect(InitialConditions.periapsisWarning(config: config)?.contains("event horizon") == true)
    }

    /// The default black hole orbit is inside the ISCO on purpose; a small e that
    /// keeps it in the same zone shouldn't warn about something e didn't cause.
    @Test func noWarningWhenTheCircularOrbitIsAlreadyInTheSameZone() {
        let config = twoBodyConfig(eccentricity: 0.1, separationAU: 1.3, blackHole: true)
        #expect(InitialConditions.periapsisWarning(config: config) == nil)
    }

    @Test func noWarningInThreeBodyMode() {
        var config = twoBodyConfig(eccentricity: 0.9)
        config.mode = .threeBody
        #expect(InitialConditions.periapsisWarning(config: config) == nil)
    }
}

// MARK: - Chaos Nudge

struct ChaosNudgeTests {

    private func config(epsilon: Double, preset: ThreeBodyPreset = .figureEight) -> SimulationConfig {
        var config = SimulationConfig()
        config.mode = .threeBody
        config.threeBodyPreset = preset
        config.advanced.initial.chaosEpsilon = epsilon
        return config
    }

    @Test(arguments: ThreeBodyPreset.allCases)
    func zeroEpsilonLeavesEveryPresetUnchanged(preset: ThreeBodyPreset) {
        let nudged = InitialConditions.threeBody(preset: preset, config: config(epsilon: 0, preset: preset))
        let plain = InitialConditions.threeBody(preset: preset, config: config(epsilon: 0, preset: preset),
                                                applyingNudge: false)
        #expect(nudged.map(\.position) == plain.map(\.position))
        #expect(nudged.map(\.velocity) == plain.map(\.velocity))
    }

    @Test func nudgeMovesBodyARelativeToTheOthers() {
        let epsilon = 1e-2
        let lengthUnit = InitialConditions.units(for: .figureEight, config: SimulationConfig()).length
        let nudged = InitialConditions.threeBody(preset: .figureEight, config: config(epsilon: epsilon))
        let plain = InitialConditions.threeBody(preset: .figureEight, config: config(epsilon: epsilon),
                                                applyingNudge: false)

        let shift = (nudged[0].position - nudged[1].position) - (plain[0].position - plain[1].position)
        #expect(abs(shift.x - epsilon * lengthUnit) < 1e-9)
        #expect(abs(shift.y) < 1e-12 && abs(shift.z) < 1e-12)
        // Bodies B and C keep their relative positions.
        let otherShift = (nudged[1].position - nudged[2].position) - (plain[1].position - plain[2].position)
        #expect(otherShift.magnitude < 1e-9)
    }

    @Test func nudgedSystemStaysInTheCenterOfMassFrame() {
        let bodies = InitialConditions.threeBody(preset: .pythagorean, config: config(epsilon: 1e-4, preset: .pythagorean))
        #expect(NBodyGravity.centerOfMass(bodies).magnitude < 1e-9)
        #expect(NBodyGravity.totalMomentum(bodies).magnitude < 1e-9)
    }
}
