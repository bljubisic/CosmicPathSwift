//
//  SimulationEngineProtocol.swift
//  CosmicPathSwift
//
//  Defines the contract for a simulation engine and provides the production
//  implementation using Schwarzschild geodesic equations from general relativity.
//
//  ## Physics Background
//
//  The Schwarzschild metric describes the curved spacetime around a
//  non-rotating, uncharged spherically symmetric mass M:
//
//      ds² = -(1 - rₛ/r)c²dt² + dr²/(1 - rₛ/r) + r²dΩ²
//
//  where rₛ = 2GM/c² is the Schwarzschild radius. The geodesic equations
//  (equations of motion for a free particle in this curved spacetime) yield
//  two conserved quantities — specific energy E and specific angular
//  momentum L — and a radial equation of motion (in the radial coordinate r):
//
//      d²r/dt² = -GM/r² + L²/r³ - 3GML²/(c²r⁴)
//
//  However, since we integrate in Cartesian coordinates with Velocity-Verlet,
//  the centrifugal term L²/r³ is handled implicitly by the integrator (it
//  arises naturally from tangential velocity in Cartesian frame). The actual
//  Cartesian acceleration applied is:
//
//      a = (-GM/r² - 3GML²/(c²r⁴)) × r̂
//
//  Term breakdown:
//    • -GM/r²           Newtonian gravitational attraction (same as Newton)
//    • -3GML²/(c²r⁴)   General-relativistic correction from spacetime curvature.
//                        This term has no Newtonian analogue. It deepens the
//                        effective potential at small r, causing:
//                          – Perihelion precession (orbits do not close)
//                          – The ISCO at r = 6GM/c² = 3rₛ
//                          – Plunge orbits below the ISCO
//
//  ## Key Radii
//
//    • Schwarzschild radius:  rₛ  = 2GM/c²    (event horizon)
//    • Photon sphere:         rₚₕ = 3GM/c²    (1.5 rₛ, unstable photon orbits)
//    • ISCO:                  rᵢₛ = 6GM/c²    (3 rₛ, innermost stable circular orbit)
//
//  ## Proper Time
//
//  The relationship between coordinate time t and proper time τ for a
//  body at distance r moving at speed v is derived from the metric:
//
//      dτ/dt = √((1 - rₛ/r) - v²/c²)
//
//  This combines gravitational time dilation (1 - rₛ/r) from the
//  Schwarzschild metric with velocity-based time dilation (v²/c²)
//  from special relativity, both unified in the metric tensor.
//
//  ## Numerical Integration
//
//  The engine uses the Velocity-Verlet (Störmer-Verlet) symplectic
//  integrator, which is second-order accurate and conserves energy
//  over long timescales — essential for stable orbital simulations.
//

import Foundation

// MARK: - Protocol

/// Contract for a two-body gravitational simulation engine.
/// Enables dependency injection and testability in the ViewModel.
protocol SimulationEngineProtocol: AnyObject {
    var body1: CelestialBody { get }
    var body2: CelestialBody { get }
    var metrics: RelativisticMetrics { get }
    var isBlackHoleMode: Bool { get set }

    func step(dt: Double)
}

// MARK: - GravitySimulationEngine

/// Production simulation engine using Schwarzschild geodesic equations.
///
/// Computes gravitational acceleration from the geodesic equation of the
/// Schwarzschild metric rather than Newtonian gravity with post-Newtonian
/// corrections. This means the simulation traces actual curved-spacetime
/// paths (geodesics) rather than applying perturbative force corrections
/// to flat-space trajectories.
///
/// The Cartesian acceleration on a test particle orbiting mass M:
///
///     a = (-GM/r² - 3GML²/(c²r⁴)) × r̂
///
/// where L = |r × v| is the specific orbital angular momentum and r̂ points
/// outward from the source. The centrifugal term L²/r³ from the polar
/// geodesic equation is not applied explicitly — the Cartesian Velocity-Verlet
/// integrator handles it naturally through tangential velocity.
///
/// For the two-body case, each body moves on the geodesic of the other
/// body's Schwarzschild metric, with accelerations scaled by the
/// respective source mass.
class GravitySimulationEngine: SimulationEngineProtocol {

    // MARK: - Physics Constants
    //
    // These constants are scaled for visual simulation dynamics, not SI units.
    // The ratios between them (e.g., G/c²) determine the strength of GR effects.
    // With G=500 and c=200: rₛ = 2GM/c² = M/40, so a mass of 200 gives rₛ=5.
    // This makes relativistic effects visible at simulation-scale distances.

    /// Gravitational constant (simulation units, not SI 6.674×10⁻¹¹ m³/kg·s²)
    static let G: Double = 500.0

    /// Speed of light (simulation units, not SI 3×10⁸ m/s)
    static let c: Double = 200.0

    /// c² precomputed for efficiency in metric calculations
    static let cSquared: Double = c * c  // 40,000

    /// Softening length to prevent numerical divergence at r→0.
    /// Acts as a minimum effective distance in force calculations.
    static let softening: Double = 5.0

    /// Visual threshold for black hole classification.
    /// Body1 is rendered as a black hole when its Schwarzschild radius
    /// exceeds this value in simulation-space pixels.
    static let blackHoleThreshold: Double = 8.0

    private(set) var body1: CelestialBody
    private(set) var body2: CelestialBody
    private(set) var metrics = RelativisticMetrics()

    /// When true, enables black hole rendering and event horizon absorption.
    /// When false, body1 is never classified as a black hole regardless of mass.
    var isBlackHoleMode: Bool = false

    // MARK: - Perihelion Precession Tracking
    //
    // In Newtonian gravity, bound orbits are closed ellipses. The GR correction
    // term -3GML²/(c²r⁴) causes the perihelion (closest approach point) to
    // advance each orbit. We detect perihelion passages by monitoring when the
    // separation stops decreasing, then measure the angular shift between
    // successive perihelion positions. This accumulated angular excess is the
    // perihelion precession — the same effect famously measured for Mercury
    // (43 arcseconds/century).

    /// Previous frame's body separation, used to detect perihelion (local minimum)
    private var previousSeparation: Double = .infinity
    /// Whether the separation was decreasing last frame
    private var wasShrinking: Bool = true
    /// Angle (radians) of the most recent perihelion passage
    private var lastPerihelionAngle: Double?
    /// Total accumulated precession in radians (converted to degrees in metrics)
    private var accumulatedPrecession: Double = 0
    /// Number of complete orbits detected
    private var orbitsCompleted: Int = 0

    // MARK: - Proper Time Accumulation
    //
    // Proper time τ is the time measured by a clock traveling with body2.
    // It runs slower than coordinate time t due to both gravitational
    // time dilation (being in a gravity well) and velocity-based time
    // dilation (moving through space). Both effects emerge naturally
    // from the Schwarzschild metric: dτ/dt = √((1 - rₛ/r) - v²/c²).

    /// Accumulated proper time of body2 (always ≤ coordinate time)
    private var accumulatedProperTime: Double = 0

    init(body1: CelestialBody, body2: CelestialBody) {
        self.body1 = body1
        self.body2 = body2
        let (a1, a2) = Self.computeAccelerations(body1: body1, body2: body2)
        self.body1.acceleration = a1
        self.body2.acceleration = a2
        previousSeparation = (body2.position - body1.position).magnitude
        updateMetrics()
    }

    // MARK: - Acceleration Computation

    /// Computes gravitational accelerations on both bodies using their
    /// respective Schwarzschild geodesic equations.
    ///
    /// Each body moves on the geodesic of the other body's metric:
    /// - body2's acceleration comes from body1's Schwarzschild metric (source mass = body1.mass)
    /// - body1's acceleration comes from body2's Schwarzschild metric (source mass = body2.mass)
    ///
    /// The `separation` vector for each call points **from the source toward the body**
    /// (outward from the gravitating center). This convention means the Newtonian
    /// term (-GM/r²) produces inward acceleration when multiplied by the outward r̂.
    ///
    /// - Returns: A tuple (a1, a2) of acceleration vectors in simulation coordinates.
    static func computeAccelerations(
        body1: CelestialBody,
        body2: CelestialBody
    ) -> (Vector2D, Vector2D) {
        let r12 = body2.position - body1.position
        let dist = max(r12.magnitude, softening)
        let rHat = r12.normalized

        // Acceleration on body2 from body1's gravity (geodesic of body1's metric)
        // separation points from source (body1) to body (body2) = r12
        let a2 = schwarzschildAcceleration(
            sourceMass: body1.mass,
            separation: r12,
            distance: dist,
            rHat: rHat,
            velocity: body2.velocity
        )

        // Acceleration on body1 from body2's gravity (geodesic of body2's metric)
        // separation points from source (body2) to body (body1) = -r12
        let a1 = schwarzschildAcceleration(
            sourceMass: body2.mass,
            separation: Vector2D(x: -r12.x, y: -r12.y),
            distance: dist,
            rHat: Vector2D(x: -rHat.x, y: -rHat.y),
            velocity: body1.velocity
        )

        return (a1, a2)
    }

    /// Computes the Schwarzschild GR-corrected acceleration on a single body
    /// in Cartesian coordinates.
    ///
    /// ## Derivation
    ///
    /// The Schwarzschild geodesic radial equation (in coordinate time) is:
    ///
    ///     d²r/dt² = -GM/r² + L²/r³ - 3GML²/(c²r⁴)
    ///
    /// where r is the radial coordinate and L is the specific angular momentum.
    /// However, `d²r/dt²` is NOT the radial component of Cartesian acceleration.
    /// In polar coordinates, the Cartesian radial acceleration aᵣ relates to
    /// the radial coordinate acceleration r̈ by:
    ///
    ///     r̈ = aᵣ + r·φ̇² = aᵣ + L²/r³
    ///
    /// Solving for the Cartesian acceleration:
    ///
    ///     aᵣ = r̈ - L²/r³ = -GM/r² + L²/r³ - 3GML²/(c²r⁴) - L²/r³
    ///        = -GM/r² - 3GML²/(c²r⁴)
    ///
    /// The centrifugal term L²/r³ cancels out — it is a coordinate artifact of
    /// polar decomposition. The Cartesian Velocity-Verlet integrator naturally
    /// produces the centrifugal effect through the tangential velocity component.
    /// Similarly, the Coriolis term (-2ṙφ̇) is handled implicitly.
    ///
    /// ## Cartesian Acceleration
    ///
    /// The acceleration applied in Cartesian coordinates is purely radial:
    ///
    ///     a = (-GM/r² - 3GML²/(c²r⁴)) × r̂
    ///
    /// - **-GM/r²**: Newtonian gravity (always inward)
    /// - **-3GML²/(c²r⁴)**: GR curvature correction from the Schwarzschild metric.
    ///   This term has no Newtonian analogue. It deepens the effective potential
    ///   at small r, causing perihelion precession, the ISCO, and plunge orbits.
    ///
    /// Since r̂ points outward (from source to body) and both terms are negative,
    /// the resulting acceleration vector points inward (toward the source).
    ///
    /// - Parameters:
    ///   - M: Mass of the gravitating source.
    ///   - r: Separation vector pointing **from the source to the body** (outward).
    ///   - dist: Scalar distance between the bodies (clamped to softening minimum).
    ///   - rHat: Unit vector along r (from source to body).
    ///   - v: Velocity of the body being accelerated.
    /// - Returns: Acceleration vector in Cartesian simulation coordinates.
    private static func schwarzschildAcceleration(
        sourceMass M: Double,
        separation r: Vector2D,
        distance dist: Double,
        rHat: Vector2D,
        velocity v: Vector2D
    ) -> Vector2D {
        let GM = G * M
        let r2 = dist * dist
        let r4 = r2 * r2

        // Specific angular momentum: L = |r × v| (z-component in 2D)
        let L = abs(r.x * v.y - r.y * v.x)
        let L2 = L * L

        // Cartesian radial acceleration:
        //   a = -GM/r² - 3GML²/(c²r⁴)
        // The centrifugal term L²/r³ from the polar geodesic equation is NOT
        // included — it cancels when converting to Cartesian coordinates because
        // the Velocity-Verlet integrator handles it implicitly via tangential velocity.
        let aNewton = -GM / r2                       // Newtonian gravity (inward)
        let aGR = -3.0 * GM * L2 / (cSquared * r4)  // GR correction (inward)

        // Both terms are negative (inward). Multiplying by outward r̂ gives
        // an acceleration vector pointing toward the source.
        return (aNewton + aGR) * rHat
    }

    // MARK: - Simulation Step

    /// Advances the simulation by one time step dt using the Velocity-Verlet
    /// (Störmer-Verlet) symplectic integrator.
    ///
    /// ## Velocity-Verlet Algorithm
    ///
    /// 1. Update positions:     x(t+dt) = x(t) + v(t)·dt + ½·a(t)·dt²
    /// 2. Compute new forces:   a(t+dt) = F(x(t+dt)) / m
    /// 3. Update velocities:    v(t+dt) = v(t) + ½·(a(t) + a(t+dt))·dt
    ///
    /// This is a second-order symplectic integrator, meaning it approximately
    /// conserves the Hamiltonian (total energy) over long timescales. This is
    /// critical for orbital simulations where energy drift would cause orbits
    /// to artificially spiral inward or outward.
    ///
    /// ## Post-Integration Steps
    ///
    /// After integration, the method:
    /// - Checks for event horizon absorption (black hole mode only)
    /// - Accumulates proper time from the Schwarzschild metric
    /// - Records orbital trail positions
    /// - Tracks perihelion passages for precession measurement
    /// - Updates all relativistic metrics
    func step(dt: Double) {
        guard !metrics.isAbsorbed else { return }

        // Velocity-Verlet position update
        body1.position = body1.position + body1.velocity * dt + 0.5 * body1.acceleration * (dt * dt)
        body2.position = body2.position + body2.velocity * dt + 0.5 * body2.acceleration * (dt * dt)

        let oldA1 = body1.acceleration
        let oldA2 = body2.acceleration

        let (newA1, newA2) = Self.computeAccelerations(body1: body1, body2: body2)
        body1.acceleration = newA1
        body2.acceleration = newA2

        // Velocity-Verlet velocity update
        body1.velocity = body1.velocity + 0.5 * (oldA1 + newA1) * dt
        body2.velocity = body2.velocity + 0.5 * (oldA2 + newA2) * dt

        // Check for absorption past the event horizon (only in black hole mode)
        let rs = 2.0 * Self.G * body1.mass / Self.cSquared
        let sep = (body2.position - body1.position).magnitude
        if isBlackHoleMode && rs >= Self.blackHoleThreshold && sep <= rs {
            body2.position = body1.position
            body2.velocity = .zero
            metrics.isAbsorbed = true
            updateMetrics()
            return
        }

        // Accumulate proper time from the Schwarzschild metric:
        // dτ/dt = sqrt((1 - rs/r) - v²/c²)
        let rsOverR = min(rs / max(sep, Self.softening), 0.99)
        let v2OverC2 = min(body2.velocity.magnitudeSquared / Self.cSquared, 0.99)
        let metricFactor = max(1.0 - rsOverR - v2OverC2, 0.001)
        accumulatedProperTime += dt * sqrt(metricFactor)

        // Record trail
        body1.trail.append(body1.position)
        body2.trail.append(body2.position)
        if body1.trail.count > CelestialBody.maxTrailLength {
            body1.trail.removeFirst()
        }
        if body2.trail.count > CelestialBody.maxTrailLength {
            body2.trail.removeFirst()
        }

        trackPrecession()
        updateMetrics()
    }

    // MARK: - Precession Tracking

    /// Detects perihelion passages and measures the accumulated precession angle.
    ///
    /// ## How It Works
    ///
    /// A perihelion (closest approach) occurs when the separation transitions from
    /// decreasing to increasing — i.e., a local minimum in r(t). We detect this
    /// by monitoring the sign change in dr/dt.
    ///
    /// At each perihelion, we record the angular position θ = atan2(y, x). The
    /// angular difference between successive perihelions should be exactly 2π
    /// for a closed Newtonian orbit. Any excess (δθ - 2π) is the perihelion
    /// precession per orbit caused by the GR correction term -3GML²/(c²r⁴).
    ///
    /// For Mercury, this precession is 43 arcseconds per century. In our
    /// scaled simulation with stronger GR effects, precession is much larger
    /// and visually apparent as a rosette-shaped orbit pattern.
    private func trackPrecession() {
        let r = body2.position - body1.position
        let currentSep = r.magnitude
        let isShrinking = currentSep < previousSeparation

        if wasShrinking && !isShrinking {
            let angle = atan2(r.y, r.x)

            if let lastAngle = lastPerihelionAngle {
                var delta = angle - lastAngle
                if delta < 0 { delta += 2.0 * .pi }
                let excess = delta - 2.0 * .pi
                accumulatedPrecession += excess
                orbitsCompleted += 1
            }
            lastPerihelionAngle = angle
        }

        wasShrinking = isShrinking
        previousSeparation = currentSep
    }

    // MARK: - Metrics

    /// Recomputes all observable relativistic metrics from the current state.
    ///
    /// ## Computed Quantities
    ///
    /// - **Schwarzschild radius** rₛ = 2GM/c²: The event horizon radius.
    ///   Objects crossing this boundary cannot escape.
    ///
    /// - **Photon sphere** rₚₕ = 1.5 rₛ = 3GM/c²: The radius where photons
    ///   can orbit in unstable circular paths. Inside this radius, even
    ///   light must spiral inward.
    ///
    /// - **ISCO** rᵢₛ = 3 rₛ = 6GM/c²: The innermost stable circular orbit.
    ///   Below this radius, no stable circular orbit exists and any
    ///   perturbation causes a plunge into the black hole.
    ///
    /// - **Gravitational time dilation** √(1 - rₛ/r): From the g₀₀ component
    ///   of the Schwarzschild metric. A clock at distance r runs slower
    ///   than one at infinity by this factor. Approaches 0 at the event horizon.
    ///
    /// - **Lorentz gamma** γ = 1/√(1 - v²/c²): The special-relativistic
    ///   Lorentz factor for the orbiting body's velocity.
    ///
    /// - **Precession angle**: Total accumulated perihelion advance in degrees.
    ///
    /// - **Proper time**: Total elapsed proper time τ of the orbiting body,
    ///   always less than coordinate time due to combined gravitational
    ///   and velocity time dilation.
    private func updateMetrics() {
        let r = (body2.position - body1.position).magnitude
        let v2Speed = body2.velocity.magnitude

        // Schwarzschild radius: rₛ = 2GM/c²
        let rs = 2.0 * Self.G * body1.mass / Self.cSquared
        metrics.schwarzschildRadius = rs
        metrics.photonSphereRadius = 1.5 * rs   // 3GM/c²
        metrics.iscoRadius = 3.0 * rs           // 6GM/c²
        metrics.isBlackHole = isBlackHoleMode && rs >= Self.blackHoleThreshold

        // Gravitational time dilation from the Schwarzschild metric g₀₀ component:
        // dτ/dt = √(1 - rₛ/r) for a stationary observer at radius r
        let ratio = min(rs / max(r, Self.softening), 0.99)
        metrics.timeDilationFactor = sqrt(1.0 - ratio)

        // Velocity as fraction of c (β = v/c)
        metrics.velocityFractionOfC = v2Speed / Self.c

        // Lorentz factor: γ = 1/√(1 - β²) where β = v/c
        let beta2 = min((v2Speed * v2Speed) / Self.cSquared, 0.99)
        metrics.lorentzGamma = 1.0 / sqrt(1.0 - beta2)

        // Convert accumulated precession from radians to degrees for display
        metrics.precessionAngle = accumulatedPrecession * 180.0 / .pi
        metrics.separation = r
        metrics.properTime = accumulatedProperTime
    }
}
