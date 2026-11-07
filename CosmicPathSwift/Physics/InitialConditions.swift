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

    /// Star at the origin and planet at periapsis of an orbit with semi-major
    /// axis a (the Distance slider) and eccentricity e (Advanced sheet, default 0).
    ///
    /// ## Initial Speed (circular, e = 0)
    ///
    /// Above the ISCO (r ≥ 3 rₛ) the planet gets the Schwarzschild circular speed
    ///     v = √(GM / (r − 1.5 rₛ))
    /// which exactly balances the GR-corrected pull. Below the ISCO that formula
    /// diverges toward the photon sphere, so the Newtonian √(GM/r) is used instead;
    /// it is sub-circular in GR terms and the orbit plunges. This is the original
    /// start and is kept unchanged.
    ///
    /// ## Initial Speed (eccentric, e > 0)
    ///
    /// The planet starts at periapsis rₚ = a(1 − e) with the speed that makes
    /// rₐ = a(1 + e) the other turning point under the app's own force law
    /// (see `periapsisSpeed`).
    ///
    /// ## Orientation
    ///
    /// The orbital plane is spanned by p̂ = x̂ and q̂ = (0, cos i, sin i), where i
    /// is the inclination. Periapsis lies at angle ω from p̂:
    ///     r̂ = cos ω·p̂ + sin ω·q̂,   v̂ = cos ω·q̂ − sin ω·p̂
    /// At ω = 0 the planet starts on the x-axis moving along q̂, as before.
    ///
    /// ## Momentum
    ///
    /// The star gets the counter-velocity −(m₂/m₁)·v₂ so total momentum is zero.
    static func twoBody(config: SimulationConfig) -> [CelestialBody] {
        let mass1 = config.simulationMass1
        let mass2 = config.simulationMass2
        let initial = config.advanced.initial

        // Only prevent numerical blow-up at very small separations; no ISCO floor,
        // so the user can create genuinely unstable/plunging orbits.
        let rs = 2.0 * G * mass1 / cSquared
        let eccentricity = clampedEccentricity(initial.eccentricity)
        let separation = periapsisDistance(config: config)

        let orbitalSpeed: Double
        if eccentricity == 0 {
            let isco = 3.0 * rs
            orbitalSpeed = separation >= isco
                ? sqrt(G * mass1 / (separation - 1.5 * rs))
                : sqrt(G * mass1 / separation)
        } else {
            orbitalSpeed = eccentricPlanetSpeed(config: config, periapsis: separation, eccentricity: eccentricity)
        }

        let inclination = config.inclinationRad
        let inPlaneX = Vector3D(x: 1, y: 0, z: 0)
        let inPlaneY = Vector3D(x: 0, y: cos(inclination), z: sin(inclination))
        let omega = initial.periapsisAngleRad
        let radialDirection = inPlaneX * cos(omega) + inPlaneY * sin(omega)
        let tangentialDirection = inPlaneY * cos(omega) - inPlaneX * sin(omega)

        let planetVelocity = tangentialDirection * orbitalSpeed
        let starVelocity = planetVelocity * -(mass2 / mass1)

        return [
            CelestialBody(id: 0, kind: .star, mass: mass1, position: .zero, velocity: starVelocity),
            CelestialBody(id: 1, kind: .planet, mass: mass2,
                          position: radialDirection * separation, velocity: planetVelocity)
        ]
    }

    /// Planet speed at periapsis for an eccentric orbit.
    ///
    /// The relative orbit of the pair moves like a test particle around the total
    /// mass M = m₁ + m₂ (both the Newtonian and the GR term add up that way), so
    /// the relative speed comes from `periapsisSpeed` with M. The planet carries
    /// m₁/M of it; the star's counter-velocity in `twoBody` supplies the rest.
    ///
    /// If no orbit with those turning points exists (deep inside the ISCO), the
    /// Newtonian periapsis speed √(GM(1+e)/rₚ) is used; the planet then plunges,
    /// and the Advanced sheet warns about it.
    private static func eccentricPlanetSpeed(config: SimulationConfig, periapsis: Double, eccentricity: Double) -> Double {
        let mass1 = config.simulationMass1
        let totalMass = mass1 + config.simulationMass2
        let semiMajorAxis = max(config.simulationSeparation, minimumStartDistance(config: config))
        let apoapsis = semiMajorAxis * (1 + eccentricity)
        let relativeSpeed = periapsisSpeed(totalMass: totalMass, periapsis: periapsis, apoapsis: apoapsis)
            ?? sqrt(G * totalMass * (1 + eccentricity) / periapsis)
        return relativeSpeed * mass1 / totalMass
    }

    /// Speed at periapsis rₚ of the orbit whose other turning point is rₐ, under
    /// the app's force law a = (−GM/r² − 3GML²/(c²r⁴)) r̂.
    ///
    /// That force has the effective potential
    ///     V(r) = −GM/r + L²/(2r²) − GML²/(c²r³)
    /// and both turning points have the same energy, V(rₚ) = V(rₐ). Solving for L²:
    ///     L² = GM(1/rₚ − 1/rₐ) / [½(1/rₚ² − 1/rₐ²) − (GM/c²)(1/rₚ³ − 1/rₐ³)]
    /// and the speed at periapsis is L/rₚ. As c → ∞ this is the Newtonian
    /// vis-viva speed; as rₐ → rₚ it tends to the circular √(GM/(r − 1.5 rₛ)).
    ///
    /// - Returns: nil when no such orbit exists (the bracket is not positive).
    static func periapsisSpeed(totalMass: Double, periapsis rp: Double, apoapsis ra: Double) -> Double? {
        let gm = G * totalMass
        let numerator = gm * (1 / rp - 1 / ra)
        let denominator = 0.5 * (1 / (rp * rp) - 1 / (ra * ra))
            - (gm / cSquared) * (1 / (rp * rp * rp) - 1 / (ra * ra * ra))
        guard numerator > 0, denominator > 0 else { return nil }
        return sqrt(numerator / denominator) / rp
    }

    /// Closest allowed starting distance: twice the configured softening length.
    static func minimumStartDistance(config: SimulationConfig) -> Double {
        2 * config.advanced.engine.effectiveSoftening
    }

    /// Starting (periapsis) distance a(1 − e), never below twice the softening length.
    static func periapsisDistance(config: SimulationConfig) -> Double {
        let minimum = minimumStartDistance(config: config)
        let semiMajorAxis = max(config.simulationSeparation, minimum)
        let eccentricity = clampedEccentricity(config.advanced.initial.eccentricity)
        return max(semiMajorAxis * (1 - eccentricity), minimum)
    }

    private static func clampedEccentricity(_ value: Double) -> Double {
        let range = InitialConditionSettings.eccentricityRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Periapsis Warning

    /// A plain-language warning when the eccentricity brings the planet's closest
    /// approach inside a danger radius it wouldn't reach on a circular orbit.
    ///
    /// Radii are checked from most to least severe: the event horizon or star
    /// surface (immediate end), the Roche limit (tidal disruption), and in black
    /// hole mode the ISCO (plunge). A circular orbit that is already inside one of
    /// these (e.g. the default black hole orbit, inside the ISCO on purpose) gives
    /// no warning, since the eccentricity isn't what causes it.
    static func periapsisWarning(config: SimulationConfig) -> String? {
        guard config.mode == .twoBody, config.advanced.initial.eccentricity > 0 else { return nil }
        var circular = config
        circular.advanced.initial.eccentricity = 0

        let periapsis = periapsisDistance(config: config)
        guard let danger = dangerZone(at: periapsis, config: config),
              dangerZone(at: periapsisDistance(config: circular), config: config) != danger else {
            return nil
        }
        let distance = String(format: "%.2f AU", periapsis / CelestialConstants.baseAU)
        return "Closest approach \(distance) is \(danger.description)."
    }

    /// Radii that end or disrupt a 2-body orbit, most severe first.
    enum DangerZone: Equatable {
        case eventHorizon, starSurface, rocheLimit, insideISCO

        var description: String {
            switch self {
            case .eventHorizon: return "inside the event horizon: the planet is absorbed"
            case .starSurface: return "inside the star: the planet collides"
            case .rocheLimit: return "inside the Roche limit: tides tear the planet apart"
            case .insideISCO: return "inside the ISCO: no stable orbit, the planet plunges"
            }
        }
    }

    /// The most severe danger zone containing distance `r`, if any.
    /// Uses the same thresholds as `GravitySimulationEngine+TwoBody`.
    static func dangerZone(at r: Double, config: SimulationConfig) -> DangerZone? {
        let rs = 2.0 * G * config.simulationMass1 / cSquared
        let isBlackHole = config.isBlackHoleMode && rs >= GravitySimulationEngine.blackHoleThreshold
        let roche = GravitySimulationEngine.rocheLimit(centralMass: config.simulationMass1,
                                                       planetMass: config.simulationMass2)
        if isBlackHole && r <= rs { return .eventHorizon }
        let surface = GravitySimulationEngine.starSurfaceRadius(
            schwarzschildRadius: rs, softening: config.advanced.engine.effectiveSoftening
        )
        if !config.isBlackHoleMode && r <= surface {
            return .starSurface
        }
        if r < roche { return .rocheLimit }
        if isBlackHole && r < 3 * rs { return .insideISCO }
        return nil
    }

    // MARK: - Three-Body

    /// Bodies for a 3-body preset, in the CoM frame with zero net momentum.
    ///
    /// The Advanced chaos nudge ε is applied unless `applyingNudge` is false,
    /// which gives the unperturbed system for the chaos twin.
    static func threeBody(
        preset: ThreeBodyPreset,
        config: SimulationConfig,
        applyingNudge: Bool = true
    ) -> [CelestialBody] {
        let units = units(for: preset, config: config)
        let bodies: [CelestialBody]
        switch preset {
        case .figureEight:
            bodies = figureEight(units: units)
        case .lagrangeTriangle:
            bodies = lagrange(massMultipliers: [1, 1, 1], velocityFactor: 1, units: units)
        case .custom:
            bodies = custom(config: config, units: units)
        case .pythagorean:
            bodies = pythagorean(units: units)
        case .sunPlanetMoon:
            bodies = SunPlanetMoon.bodies()
        }
        let framed = NBodyGravity.centerOfMassFrame(bodies)
        let epsilon = applyingNudge ? config.advanced.initial.chaosEpsilon : 0
        return nudged(framed, epsilon: epsilon, lengthUnit: units.length)
    }

    /// The Custom preset in the layout chosen in the Advanced sheet.
    private static func custom(config: SimulationConfig, units: PresetUnits) -> [CelestialBody] {
        let initial = config.advanced.initial
        switch initial.customLayout {
        case .triangle:
            return lagrange(massMultipliers: config.customMassMultipliers,
                            velocityFactor: config.customVelocityFactor, units: units)
        case .random:
            return randomLayout(massMultipliers: config.customMassMultipliers, seed: initial.customSeed,
                                velocityFactor: config.customVelocityFactor, units: units)
        }
    }

    // MARK: - Chaos Nudge

    /// Moves body A (index 0) by ε × `lengthUnit` along x̂, then returns to the
    /// CoM frame. Velocities are untouched, so net momentum stays zero.
    /// With ε = 0 the bodies are returned unchanged.
    static func nudged(_ bodies: [CelestialBody], epsilon: Double, lengthUnit: Double) -> [CelestialBody] {
        guard epsilon != 0, !bodies.isEmpty else { return bodies }
        var moved = bodies
        moved[0].position = moved[0].position + Vector3D(x: epsilon * lengthUnit, y: 0, z: 0)
        return NBodyGravity.centerOfMassFrame(moved)
    }

    // MARK: - Random Layout

    /// Closest two bodies may start, as a fraction of the length unit, so the
    /// layout never begins with an immediate merge.
    static let randomLayoutMinimumSeparation = 0.3

    /// Range of the virial ratio K / |U| drawn for a random layout. Any value
    /// below 1 makes the total energy negative, so the system starts bound.
    static let randomLayoutVirialRange: ClosedRange<Double> = 0.1...0.5

    /// Seeded random layout for the Custom preset, using the user's masses.
    ///
    /// 1. Each body is placed uniformly in a disk of radius L; layouts with two
    ///    bodies closer than 0.3 L are redrawn.
    /// 2. Each body gets a random in-plane velocity; the system is moved to the
    ///    CoM frame.
    /// 3. Velocities are scaled to a seeded virial ratio K/|U| in 0.1–0.5, so the
    ///    system starts bound (E < 0), then by `velocityFactor`. Factors above 1
    ///    can unbind it, which is the point of that slider.
    ///
    /// The same seed and masses always give the same layout.
    static func randomLayout(
        massMultipliers: [Double],
        seed: UInt64,
        velocityFactor: Double,
        units: PresetUnits
    ) -> [CelestialBody] {
        var generator = SeededGenerator(seed: seed)
        let positions = randomPositions(count: 3, radius: units.length, generator: &generator)
        let placed = (0..<3).map { index -> CelestialBody in
            let multiplier = massMultipliers.indices.contains(index) ? massMultipliers[index] : 1.0
            let angle = 2 * Double.pi * generator.nextUnit()
            let speed = generator.nextUnit()
            let velocity = Vector3D(x: speed * cos(angle), y: speed * sin(angle), z: 0)
            return CelestialBody(id: index, kind: .star, mass: units.mass * multiplier,
                                 position: positions[index], velocity: velocity)
        }
        let framed = NBodyGravity.centerOfMassFrame(placed)

        let virial = randomLayoutVirialRange.lowerBound
            + (randomLayoutVirialRange.upperBound - randomLayoutVirialRange.lowerBound) * generator.nextUnit()
        let scale = virialVelocityScale(framed, virialRatio: virial) * velocityFactor
        return framed.map { body in
            var scaled = body
            scaled.velocity = body.velocity * scale
            return scaled
        }
    }

    /// Uniform points in a disk, redrawn until every pair is at least
    /// `randomLayoutMinimumSeparation × radius` apart.
    private static func randomPositions(
        count: Int,
        radius: Double,
        generator: inout SeededGenerator
    ) -> [Vector3D] {
        let minimumSeparation = randomLayoutMinimumSeparation * radius
        while true {
            let points = (0..<count).map { _ -> Vector3D in
                let r = radius * sqrt(generator.nextUnit())
                let angle = 2 * Double.pi * generator.nextUnit()
                return Vector3D(x: r * cos(angle), y: r * sin(angle), z: 0)
            }
            let wellSeparated = points.indices.allSatisfy { i in
                points.indices.allSatisfy { j in j <= i || (points[i] - points[j]).magnitude >= minimumSeparation }
            }
            if wellSeparated { return points }
        }
    }

    /// Factor that scales the bodies' velocities so that K = virialRatio × |U|.
    private static func virialVelocityScale(_ bodies: [CelestialBody], virialRatio: Double) -> Double {
        let atRest = bodies.map { body -> CelestialBody in
            var still = body
            still.velocity = .zero
            return still
        }
        let potential = NBodyGravity.newtonianEnergy(atRest)
        let kinetic = NBodyGravity.newtonianEnergy(bodies) - potential
        guard kinetic > 0, potential < 0 else { return 0 }
        return sqrt(virialRatio * -potential / kinetic)
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
