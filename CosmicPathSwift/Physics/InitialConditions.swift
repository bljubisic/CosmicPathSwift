//
//  InitialConditions.swift
//  CosmicPathSwift
//
//  Builds the starting bodies for every scenario: the classic star–planet
//  pair and the 3-body presets.
//
//  ## 3-Body Preset Scaling
//
//  Figure-8 and Pythagorean are defined in the standard G = 1 dimensionless
//  units of the literature and scaled to simulation units with a per-preset
//  length unit L (pixels) and mass unit M:
//
//      position × L,   mass × M,   velocity × √(G·M/L)
//
//  The units were chosen by simulating each preset with the app's own physics
//  (GR on, 5 px softening, merge radius ≥ 10 px):
//    • Figure-8 / Lagrange / Custom: L = 150, M = 25 keeps pair speeds near
//      v/c ≈ 0.06, so GR slowly distorts the orbit over a few loops instead of
//      destroying it within one period (which happens at M = 200).
//    • Pythagorean: L = 1200, M = 2.4. Its first close encounter reaches
//      r ≈ 0.0097 L, so smaller L would merge the bodies immediately.
//
//  Every 3-body result is shifted to the CoM frame with zero net momentum.
//

import Foundation

enum InitialConditions {

    private static var G: Double { GravitySimulationEngine.G }
    private static var cSquared: Double { GravitySimulationEngine.cSquared }

    // MARK: - Preset Units

    /// Length (px) and mass units used to scale a dimensionless preset.
    struct PresetUnits: Equatable {
        let length: Double
        let mass: Double

        /// Velocity unit √(G·M/L) for G = 1 dimensionless velocities.
        var velocity: Double { sqrt(GravitySimulationEngine.G * mass / length) }
    }

    /// Units for each preset (see file header for how they were chosen).
    static func units(for preset: ThreeBodyPreset, config: SimulationConfig) -> PresetUnits {
        switch preset {
        case .figureEight, .lagrangeTriangle:
            return PresetUnits(length: 150, mass: 25)
        case .custom:
            return PresetUnits(length: 150 * config.customSpreadAU, mass: 25)
        case .pythagorean:
            return PresetUnits(length: 1200, mass: 2.4)
        case .sunPlanetMoon:
            return PresetUnits(length: CelestialConstants.baseAU, mass: SunPlanetMoon.starMass)
        }
    }

    // MARK: - Two-Body

    /// Star at the origin and planet on the x-axis, with a near-circular orbit.
    ///
    /// ## Initial Speed
    ///
    /// Above the ISCO (r ≥ 3 rₛ) the planet gets the Schwarzschild circular speed
    ///     v = √(GM / (r − 1.5 rₛ))
    /// which exactly balances the GR-corrected pull. Below the ISCO that formula
    /// diverges toward the photon sphere, so the Newtonian √(GM/r) is used instead;
    /// it is sub-circular in GR terms and the orbit plunges.
    ///
    /// ## Inclination
    ///
    /// The tangential velocity is rotated from the y-axis toward z by angle i:
    ///     v₂ = (0, v·cos i, v·sin i)
    ///
    /// ## Momentum
    ///
    /// The star gets the counter-velocity −(m₂/m₁)·v₂ so total momentum is zero.
    static func twoBody(config: SimulationConfig) -> [CelestialBody] {
        let mass1 = config.simulationMass1
        let mass2 = config.simulationMass2

        // Only prevent numerical blow-up at very small separations; no ISCO floor,
        // so the user can create genuinely unstable/plunging orbits.
        let rs = 2.0 * G * mass1 / cSquared
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

    // MARK: - Three-Body

    /// Bodies for a 3-body preset, in the CoM frame with zero net momentum.
    static func threeBody(preset: ThreeBodyPreset, config: SimulationConfig) -> [CelestialBody] {
        let units = units(for: preset, config: config)
        let bodies: [CelestialBody]
        switch preset {
        case .figureEight:
            bodies = figureEight(units: units)
        case .lagrangeTriangle:
            bodies = lagrange(massMultipliers: [1, 1, 1], velocityFactor: 1, units: units)
        case .custom:
            bodies = lagrange(massMultipliers: config.customMassMultipliers,
                              velocityFactor: config.customVelocityFactor, units: units)
        case .pythagorean:
            bodies = pythagorean(units: units)
        case .sunPlanetMoon:
            bodies = SunPlanetMoon.bodies()
        }
        return NBodyGravity.centerOfMassFrame(bodies)
    }

    /// Chenciner–Montgomery figure-eight choreography (equal masses, G = 1).
    private static func figureEight(units: PresetUnits) -> [CelestialBody] {
        let x1 = Vector3D(x: 0.97000436, y: -0.24308753, z: 0)
        let v3 = Vector3D(x: -0.93240737, y: -0.86473146, z: 0)
        let positions = [x1, -x1, .zero]
        let velocities = [v3 * -0.5, v3 * -0.5, v3]
        return (0..<3).map { index in
            CelestialBody(id: index, kind: .star, mass: units.mass,
                          position: positions[index] * units.length,
                          velocity: velocities[index] * units.velocity)
        }
    }

    /// Burrau's Pythagorean problem: masses 3, 4, 5 at rest on a 3-4-5 triangle.
    private static func pythagorean(units: PresetUnits) -> [CelestialBody] {
        let masses = [3.0, 4.0, 5.0]
        let positions = [Vector3D(x: 1, y: 3, z: 0), Vector3D(x: -2, y: -1, z: 0), Vector3D(x: 1, y: -1, z: 0)]
        return (0..<3).map { index in
            CelestialBody(id: index, kind: .star, mass: masses[index] * units.mass,
                          position: positions[index] * units.length, velocity: .zero)
        }
    }

    /// Lagrange equilateral configuration with side `units.length`, rotating
    /// rigidly about the CoM when `velocityFactor == 1`.
    ///
    /// In rigid rotation every pair's GR term scales its Newtonian pull by the same
    /// factor 3ω²a²/c², so the configuration stays an exact equilibrium with GR on if
    ///     ω² = (GM/a³) / (1 − 3GM/(a c²))
    /// The bracket is clamped so extreme masses can't produce an imaginary ω.
    ///
    /// Equal masses violate Routh's criterion 27(m₁m₂ + m₂m₃ + m₃m₁) < (Σm)², so
    /// the triangle breaks up after a few turns; one dominant mass keeps it stable.
    static func lagrange(massMultipliers: [Double], velocityFactor: Double, units: PresetUnits) -> [CelestialBody] {
        let side = units.length
        let circumradius = side / sqrt(3.0)
        let masses = (0..<3).map { index in
            units.mass * (massMultipliers.indices.contains(index) ? massMultipliers[index] : 1.0)
        }
        let placed = (0..<3).map { index -> CelestialBody in
            let angle = Double.pi / 2 + Double(index) * 2 * Double.pi / 3
            let position = Vector3D(x: circumradius * cos(angle), y: circumradius * sin(angle), z: 0)
            return CelestialBody(id: index, kind: .star, mass: masses[index], position: position, velocity: .zero)
        }

        let totalMass = NBodyGravity.totalMass(placed)
        let newtonianOmegaSquared = G * totalMass / (side * side * side)
        let grFactor = max(1.0 - 3.0 * G * totalMass / (side * cSquared), 0.1)
        let omega = sqrt(newtonianOmegaSquared / grFactor) * velocityFactor

        let com = NBodyGravity.centerOfMass(placed)
        let spin = Vector3D(x: 0, y: 0, z: omega)
        return placed.map { body in
            var moving = body
            moving.velocity = spin.cross(body.position - com)
            return moving
        }
    }

    // MARK: - Sun–Planet–Moon

    /// A stable hierarchical triple: a moon on a tight prograde orbit around a
    /// planet that orbits a star at 1 AU.
    ///
    /// Mass ratios follow star : planet : moon = 1 : ¼ : 1/80 (the plan's
    /// 1 M☉ / 10 M⊕ / 0.5 M⊕ with the compressed 40:1 Earth scale), but the
    /// whole system is 8× lighter. At full mass the planet's v/c ≈ 0.15 makes
    /// the non-conservative GR term pump the moon into the planet within a few
    /// years; at ⅛ mass it stays bound for hundreds of orbits.
    enum SunPlanetMoon {
        static let starMass = CelestialConstants.baseSolarMass / 8
        static let planetMass = starMass / 4
        static let moonMass = planetMass / 20
        /// Moon distance from the planet as a fraction of the planet's Hill radius.
        static let hillFraction = 0.35

        static func bodies() -> [CelestialBody] {
            let orbitRadius = CelestialConstants.baseAU
            let hillRadius = orbitRadius * pow(planetMass / (3 * starMass), 1.0 / 3.0)
            let moonDistance = hillFraction * hillRadius

            let planetSpeed = circularSpeed(mass: starMass + planetMass + moonMass, radius: orbitRadius)
            let moonSpeed = circularSpeed(mass: planetMass + moonMass, radius: moonDistance)

            return [
                CelestialBody(id: 0, kind: .star, mass: starMass, position: .zero, velocity: .zero),
                CelestialBody(id: 1, kind: .planet, mass: planetMass,
                              position: Vector3D(x: orbitRadius, y: 0, z: 0),
                              velocity: Vector3D(x: 0, y: planetSpeed, z: 0)),
                CelestialBody(id: 2, kind: .moon, mass: moonMass,
                              position: Vector3D(x: orbitRadius + moonDistance, y: 0, z: 0),
                              velocity: Vector3D(x: 0, y: planetSpeed + moonSpeed, z: 0))
            ]
        }

        /// GR-corrected circular speed √(GM / (r − 3GM/c²)) for the app's force law.
        private static func circularSpeed(mass: Double, radius: Double) -> Double {
            let gm = GravitySimulationEngine.G * mass
            let denominator = max(radius - 3 * gm / GravitySimulationEngine.cSquared, radius * 0.1)
            return sqrt(gm / denominator)
        }
    }
}
