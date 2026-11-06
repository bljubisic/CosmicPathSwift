//
//  GravitySimulationEngine+TwoBody.swift
//  CosmicPathSwift
//
//  Star–planet features that only make sense with exactly two bodies:
//  event-horizon / star-surface absorption, Roche-limit tidal stripping with
//  bleed particles, perihelion precession tracking, and proper time.
//
//  Body index 0 is the central body (star / black hole) and index 1 the planet.
//

import Foundation

extension GravitySimulationEngine {

    // MARK: - Tuning Constants

    /// Simulated time between 2-body trail points. Equals the default `dt`, so
    /// standard settings record exactly one point per step, as before.
    static let twoBodyTrailSampleInterval: Double = 0.02

    /// Simulated time between bleed particles (4 default steps, ~60 ms on screen at 1×).
    static let bleedEmissionInterval: Double = 0.08

    // MARK: - State

    /// Bookkeeping used only by the 2-body scenario.
    struct TwoBodyState {
        /// Initial mass of body2, used to compute the minimum bleed-out threshold
        /// and to track how much mass has been lost to tidal stripping.
        var body2InitialMass: Double = 0
        /// Schedules trail points by simulated time, so trails look the same at any `dt`.
        var trailSampler = TrailSampler(interval: GravitySimulationEngine.twoBodyTrailSampleInterval)
        /// Throttles bleed emission by simulated time (only advanced inside the Roche limit).
        var bleedSampler = TrailSampler(interval: GravitySimulationEngine.bleedEmissionInterval)

        // Perihelion precession tracking.
        //
        // In Newtonian gravity, bound orbits are closed ellipses. The GR correction
        // term -3GML²/(c²r⁴) causes the perihelion (closest approach point) to
        // advance each orbit. We detect perihelion passages by monitoring when the
        // separation stops decreasing, then measure the angular shift between
        // successive perihelion positions.

        /// Previous frame's body separation, used to detect perihelion (local minimum)
        var previousSeparation: Double = .infinity
        /// Whether the separation was decreasing last frame
        var wasShrinking: Bool = true
        /// Angle (radians) of the most recent perihelion passage, measured in x-y plane
        var lastPerihelionAngle: Double?
        /// Total accumulated precession in radians (converted to degrees in metrics)
        var accumulatedPrecession: Double = 0
        /// Number of complete orbits detected
        var orbitsCompleted: Int = 0

        /// Accumulated proper time of body2 (always ≤ coordinate time).
        /// dτ/dt = √((1 - rₛ/r) - v²/c²) combines gravitational and velocity dilation.
        var accumulatedProperTime: Double = 0

        // Diagnostics (issue #20, PR 6).

        /// Coordinate time integrated so far.
        var elapsedTime: Double = 0
        /// Relative-orbit energy at t = 0, the baseline for ΔE/E.
        var initialEnergy: Double = 0
        /// Relative-orbit |r × v| at t = 0, the baseline for ΔL/L.
        var initialAngularMomentum: Double = 0
        /// Sum of the energy jumps caused by tidal mass loss (which changes M),
        /// excluded from the drift like merges are in 3-body mode.
        var strippingEnergyChange: Double = 0
        /// Separation at the most recent periapsis.
        var lastPeriapsis: Double?
        /// Separation at the most recent apoapsis.
        var lastApoapsis: Double?
    }

    // MARK: - Step

    /// One 2-body step: integrate, then apply absorption, tidal stripping,
    /// proper time, trails, precession tracking, and metrics.
    func stepTwoBody(dt: Double) {
        // Always advance bleed particles so they continue to spiral in and
        // fade out even after the planet has been absorbed or destroyed.
        advanceBleedParticles(dt: dt)

        guard !metrics.isAbsorbed else { return }

        let previousPositions = bodies.map(\.position)
        integrate(dt: dt)
        twoBodyState.elapsedTime += dt

        // Separation uses the full 3D distance so inclined orbits are handled correctly.
        let rs = 2.0 * Self.G * bodies[0].mass / Self.cSquared
        let sep = (bodies[1].position - bodies[0].position).magnitude

        if checkAbsorption(schwarzschildRadius: rs, separation: sep) { return }
        if applyTidalStripping(separation: sep, dt: dt) { return }

        accumulateProperTime(schwarzschildRadius: rs, separation: sep, dt: dt)
        let fractions = twoBodyState.trailSampler.sampleFractions(forStep: dt)
        appendTrailPoints(from: previousPositions, atFractions: fractions)
        trackPrecession()
        updateMetrics()
    }

    /// Records one trail point per fraction for every body, linearly interpolated
    /// between its position at the start of the step and now (fraction 1 = now).
    /// Trails are capped at `CelestialBody.trailBufferLength`.
    ///
    /// If the body count changed during the step (a merge), the start positions no
    /// longer line up, so the current positions are recorded instead.
    func appendTrailPoints(from previousPositions: [Vector3D], atFractions fractions: [Double]) {
        guard !fractions.isEmpty else { return }
        let canInterpolate = previousPositions.count == bodies.count
        for i in bodies.indices {
            let current = bodies[i].position
            let points = fractions.map { fraction in
                canInterpolate ? Self.interpolate(previousPositions[i], current, fraction) : current
            }
            bodies[i].trail.append(contentsOf: points)
            let overflow = bodies[i].trail.count - CelestialBody.trailBufferLength
            if overflow > 0 {
                bodies[i].trail.removeFirst(overflow)
            }
        }
    }

    /// Linear interpolation that returns `end` exactly at fraction 1.
    private static func interpolate(_ start: Vector3D, _ end: Vector3D, _ fraction: Double) -> Vector3D {
        fraction >= 1 ? end : start + (end - start) * fraction
    }

    // MARK: - Absorption

    /// Ends the simulation if the planet crossed the event horizon (BH mode) or
    /// hit the star's surface (normal mode). Returns true if absorbed.
    private func checkAbsorption(schwarzschildRadius rs: Double, separation sep: Double) -> Bool {
        if isBlackHoleMode && rs >= Self.blackHoleThreshold && sep <= rs {
            // BH mode: planet crossed the event horizon — absorbed.
            absorbPlanet()
            return true
        }

        if !isBlackHoleMode && sep <= Self.starSurfaceRadius(schwarzschildRadius: rs, softening: softeningLength) {
            // Normal mode: the planet reached the star's surface.
            absorbPlanet()
            return true
        }
        return false
    }

    /// Radius at which the planet hits the star in normal mode: max(2 rₛ, 2 × softening).
    /// It scales with stellar mass while never falling below the softening length.
    /// For a 1 M☉ star this is ~10 sim-pixels; for a 10 M☉ star it's ~100.
    static func starSurfaceRadius(
        schwarzschildRadius rs: Double,
        softening: Double = GravitySimulationEngine.softening
    ) -> Double {
        max(2.0 * rs, softening * 2)
    }

    /// Proxy for the planet's physical radius used by the Roche limit (sim-pixels).
    static let planetProxyRadius: Double = 10.0

    /// Roche limit r = R_planet × (2 M₁ / M₂)^⅓, inside which tides strip the planet.
    static func rocheLimit(centralMass: Double, planetMass: Double) -> Double {
        planetProxyRadius * pow(2.0 * centralMass / max(planetMass, 0.1), 1.0 / 3.0)
    }

    /// Freezes the planet at the central body's position and flags absorption.
    private func absorbPlanet() {
        bodies[1].position = bodies[0].position
        bodies[1].velocity = .zero
        metrics.isAbsorbed = true
        updateMetrics()
    }

    // MARK: - Tidal Stripping

    /// Strips mass from the planet inside the Roche limit and emits bleed particles.
    /// Returns true if the planet was fully disrupted.
    ///
    /// The Roche limit is the distance at which tidal forces from body1
    /// overcome the planet's self-gravity. We use a 10-pixel proxy for the
    /// planet's physical radius; the limit then scales as (M1/M2)^(1/3).
    ///
    ///   r_Roche = R_planet × (2 M1 / M2)^(1/3)
    ///
    /// Inside this limit, the planet loses mass at a rate proportional to how
    /// deeply it is embedded (tideFraction = 1 − r/r_Roche). As M2 shrinks the
    /// Roche limit grows, creating a runaway stripping effect. When mass drops
    /// to 0.5 % of its initial value the planet is considered fully disrupted.
    private func applyTidalStripping(separation sep: Double, dt: Double) -> Bool {
        let rocheLimit = Self.rocheLimit(centralMass: bodies[0].mass, planetMass: bodies[1].mass)
        guard sep < rocheLimit else { return false }

        let initialMass = twoBodyState.body2InitialMass
        let tideFraction = max(0.0, 1.0 - sep / rocheLimit)
        let massLossRate = bodies[1].mass * 0.08 * tideFraction
        let energyBefore = relativeOrbitEnergy()
        bodies[1].mass = max(bodies[1].mass - massLossRate * dt, initialMass * 0.005)
        twoBodyState.strippingEnergyChange += relativeOrbitEnergy() - energyBefore

        emitBleedParticlesIfDue(dt: dt)

        // Planet fully disrupted — trigger destruction.
        if bodies[1].mass <= initialMass * 0.005 {
            absorbPlanet()
            return true
        }
        return false
    }

    /// Emits one bleed particle per `bleedEmissionInterval` of simulated time
    /// spent inside the Roche limit, so the density doesn't depend on `dt`.
    private func emitBleedParticlesIfDue(dt: Double) {
        let due = twoBodyState.bleedSampler.sampleFractions(forStep: dt).count
        for _ in 0..<due {
            emitBleedParticle()
        }
    }

    /// Emits one bleed particle at the planet, capping the total at 300.
    private func emitBleedParticle() {
        // Initial velocity: planet's velocity scaled down so the particle
        // is sub-circular and spirals inward, plus a small inward nudge.
        let planet = bodies[1]
        let inward = (bodies[0].position - planet.position).normalized
        let particleVel = planet.velocity * 0.75 + inward * (planet.velocity.magnitude * 0.15)
        bleedParticles.append(BleedParticle(position: planet.position, velocity: particleVel, life: 1.0))
        if bleedParticles.count > 300 {
            bleedParticles.removeFirst()
        }
    }

    /// Advances every bleed particle one time step under body1's Newtonian gravity
    /// and decrements their lifetimes, removing fully-faded ones.
    ///
    /// Uses simple Newtonian (not Schwarzschild) gravity for performance — particles
    /// are visual only and don't need GR precision.
    private func advanceBleedParticles(dt: Double) {
        let center = bodies[0].position
        let bleedGM = Self.G * bodies[0].mass
        for i in bleedParticles.indices.reversed() {
            let toBody1 = center - bleedParticles[i].position
            let d = max(toBody1.magnitude, softeningLength)
            // a = GM/d² × r̂  (toward body1)
            let acc = (bleedGM / (d * d * d)) * toBody1
            bleedParticles[i].velocity = bleedParticles[i].velocity + acc * dt
            bleedParticles[i].position = bleedParticles[i].position + bleedParticles[i].velocity * dt
            bleedParticles[i].life -= BleedParticle.decayRate * dt
            if bleedParticles[i].life <= 0 {
                bleedParticles.remove(at: i)
            }
        }
    }

    // MARK: - Proper Time

    /// Accumulates proper time from the Schwarzschild metric: dτ/dt = √((1 − rₛ/r) − v²/c²).
    private func accumulateProperTime(schwarzschildRadius rs: Double, separation sep: Double, dt: Double) {
        let rsOverR = min(rs / max(sep, softeningLength), 0.99)
        let v2OverC2 = min(bodies[1].velocity.magnitudeSquared / Self.cSquared, 0.99)
        let metricFactor = max(1.0 - rsOverR - v2OverC2, 0.001)
        twoBodyState.accumulatedProperTime += dt * sqrt(metricFactor)
    }

    // MARK: - Precession Tracking

    /// Detects perihelion passages and measures the accumulated precession angle.
    /// Also records the separation at each periapsis and apoapsis, for the
    /// predicted precession in the Advanced sheet.
    ///
    /// A perihelion (closest approach) occurs when the separation transitions from
    /// decreasing to increasing — a local minimum in r(t). At each perihelion we
    /// record θ = atan2(y, x) in the x-y plane (the projection approximates the true
    /// in-plane angle for small inclinations). The angular difference between
    /// successive perihelions is exactly 2π for a closed Newtonian orbit; any excess
    /// is the precession caused by the GR correction term −3GML²/(c²r⁴). Since
    /// atan2 wraps, that excess is the angle difference itself, wrapped to (−π, π].
    private func trackPrecession() {
        let r = bodies[1].position - bodies[0].position
        let currentSep = r.magnitude
        let isShrinking = currentSep < twoBodyState.previousSeparation

        if !twoBodyState.wasShrinking && isShrinking {
            // Growing → shrinking: the previous sample was an apoapsis.
            twoBodyState.lastApoapsis = max(twoBodyState.previousSeparation, currentSep)
        }

        if twoBodyState.wasShrinking && !isShrinking {
            twoBodyState.lastPeriapsis = min(twoBodyState.previousSeparation, currentSep)
            let angle = atan2(r.y, r.x)
            if let lastAngle = twoBodyState.lastPerihelionAngle {
                // After one full turn the periapsis is back near the same angle, so the
                // wrapped difference is the advance itself. Wrapping to (−π, π] keeps
                // its sign (prograde > 0) for any advance below 180° per orbit.
                twoBodyState.accumulatedPrecession += remainder(angle - lastAngle, 2.0 * .pi)
                twoBodyState.orbitsCompleted += 1
            }
            twoBodyState.lastPerihelionAngle = angle
        }

        twoBodyState.wasShrinking = isShrinking
        twoBodyState.previousSeparation = currentSep
    }

    // MARK: - Metrics

    /// Recomputes all observable relativistic metrics from the current state.
    ///
    /// - **Schwarzschild radius** rₛ = 2GM/c², **photon sphere** 1.5 rₛ, **ISCO** 3 rₛ.
    /// - **Gravitational time dilation** √(1 − rₛ/r) from the g₀₀ metric component.
    /// - **Lorentz gamma** γ = 1/√(1 − v²/c²).
    /// - **Precession** in degrees, **proper time** τ, and the orbit count.
    ///
    /// All distances use the full 3D separation, so inclined orbits are handled correctly.
    func updateMetrics() {
        let r = (bodies[1].position - bodies[0].position).magnitude
        let v2Speed = bodies[1].velocity.magnitude

        let rs = 2.0 * Self.G * bodies[0].mass / Self.cSquared
        metrics.schwarzschildRadius = rs
        metrics.photonSphereRadius = 1.5 * rs   // 3GM/c²
        metrics.iscoRadius = 3.0 * rs           // 6GM/c²
        metrics.isBlackHole = isBlackHoleMode && rs >= Self.blackHoleThreshold

        // dτ/dt = √(1 - rₛ/r) for a stationary observer at radius r
        let ratio = min(rs / max(r, softeningLength), 0.99)
        metrics.timeDilationFactor = sqrt(1.0 - ratio)

        metrics.velocityFractionOfC = v2Speed / Self.c

        // γ = 1/√(1 - β²) where β = v/c
        let beta2 = min((v2Speed * v2Speed) / Self.cSquared, 0.99)
        metrics.lorentzGamma = 1.0 / sqrt(1.0 - beta2)

        metrics.precessionAngle = twoBodyState.accumulatedPrecession * 180.0 / .pi
        metrics.separation = r
        metrics.properTime = twoBodyState.accumulatedProperTime
        metrics.orbitsCompleted = twoBodyState.orbitsCompleted
        updateDiagnosticMetrics()
    }

    // MARK: - Diagnostics

    /// Relative position and velocity of the planet with respect to the central body.
    private var relativeState: (r: Vector3D, v: Vector3D) {
        (bodies[1].position - bodies[0].position, bodies[1].velocity - bodies[0].velocity)
    }

    /// GR-corrected energy of the relative orbit, conserved by the force law.
    func relativeOrbitEnergy() -> Double {
        let (r, v) = relativeState
        return RelativeOrbit.energy(r: r, v: v, totalMass: bodies[0].mass + bodies[1].mass, softening: softeningLength)
    }

    /// Specific angular momentum |r × v| of the relative orbit.
    func relativeOrbitAngularMomentum() -> Double {
        let (r, v) = relativeState
        return RelativeOrbit.angularMomentum(r: r, v: v)
    }

    /// Stores the t = 0 baselines for the drift metrics.
    func recordInitialInvariants() {
        twoBodyState.initialEnergy = relativeOrbitEnergy()
        twoBodyState.initialAngularMomentum = relativeOrbitAngularMomentum()
    }

    /// Refreshes coordinate time, ΔE/E, ΔL/L and the turning points. The drifts
    /// keep their last values once the planet is absorbed (its state is frozen).
    private func updateDiagnosticMetrics() {
        metrics.elapsedTime = twoBodyState.elapsedTime
        metrics.periapsisDistance = twoBodyState.lastPeriapsis
        metrics.apoapsisDistance = twoBodyState.lastApoapsis
        guard !metrics.isAbsorbed else { return }

        let initialEnergy = twoBodyState.initialEnergy
        if initialEnergy != 0 {
            let energy = relativeOrbitEnergy() - twoBodyState.strippingEnergyChange
            metrics.energyDrift = (energy - initialEnergy) / abs(initialEnergy)
        }
        let initialL = twoBodyState.initialAngularMomentum
        if initialL > 0 {
            metrics.angularMomentumDrift = abs(relativeOrbitAngularMomentum() - initialL) / initialL
        }
    }
}
