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
//  ## 3D Extension
//
//  The physics generalises directly from 2D to 3D:
//    • All position/velocity/acceleration quantities are now `Vector3D`.
//    • The specific angular momentum L = |r × v| uses the full 3D cross
//      product. In 2D only the z-component was needed; in 3D inclined
//      orbits all three components contribute.
//    • The radial acceleration formula a = (-GM/r² - 3GML²/(c²r⁴)) × r̂
//      is unchanged — it is purely radial in any dimension.
//    • The Velocity-Verlet integrator is unchanged; it applies the 3D
//      vectors without modification.
//
//  ## N-Body Generalisation
//
//  The engine now integrates any number of bodies. The pairwise acceleration
//  and the integrator live in `NBodyGravity`; the GR term uses the *relative*
//  velocity of each pair so it does not depend on the reference frame.
//
//  Scenario-specific behaviour is split into extension files:
//    • GravitySimulationEngine+TwoBody.swift   — absorption, tidal stripping,
//      precession tracking, proper time (only when created with 2 bodies)
//    • GravitySimulationEngine+ThreeBody.swift — merges, ejection detection,
//      system metrics (created with any other body count)
//

import Foundation

// MARK: - Protocol

/// Contract for an N-body gravitational simulation engine.
/// Enables dependency injection and testability in the ViewModel.
protocol SimulationEngineProtocol: AnyObject {
    /// All simulated bodies in a stable order. In 2-body mode index 0 is the
    /// central body (star / black hole) and index 1 is the orbiting planet.
    var bodies: [CelestialBody] { get }
    /// Orbit metrics of body2 around body1 (meaningful in 2-body mode only).
    var metrics: RelativisticMetrics { get }
    /// System-wide metrics (meaningful in 3-body mode).
    var systemMetrics: SystemMetrics { get }
    var isBlackHoleMode: Bool { get set }
    /// Particles of material stripped from the planet by tidal forces.
    /// Projected to canvas space by the ViewModel each frame for rendering.
    var bleedParticles: [BleedParticle] { get }

    func step(dt: Double)
}

extension SimulationEngineProtocol {
    /// The central body in 2-body mode. Kept for code written before N-body support.
    var body1: CelestialBody { bodies[0] }

    /// The orbiting body in 2-body mode. Falls back to the only remaining body
    /// if merges have reduced the system to one.
    var body2: CelestialBody { bodies[min(1, bodies.count - 1)] }
}

// MARK: - GravitySimulationEngine

/// Production simulation engine using Schwarzschild-corrected gravity for every pair.
///
/// The Cartesian acceleration on body i from body j:
///
///     aᵢ = (−Gmⱼ/r² − 3GmⱼL²/(c²r⁴)) × r̂
///
/// where L = |rᵢⱼ × (vᵢ − vⱼ)| is the pair's specific angular momentum and r̂
/// points outward from the source. See `NBodyGravity` for the implementation.
///
/// Whether the 2-body or the N-body feature set runs is decided once at init
/// from the body count (`isTwoBodyScenario`), so a 3-body system that merges
/// down to two bodies keeps its 3-body behaviour.
final class GravitySimulationEngine: SimulationEngineProtocol {

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

    // MARK: - State
    //
    // Setters are internal (not private) so the scenario extensions in the
    // +TwoBody and +ThreeBody files can update them; the protocol exposes
    // them read-only to the ViewModel.

    var bodies: [CelestialBody]
    var metrics = RelativisticMetrics()
    var systemMetrics = SystemMetrics()
    var bleedParticles: [BleedParticle] = []

    /// When true, enables black hole rendering and event horizon absorption.
    /// When false, body1 is never classified as a black hole regardless of mass.
    /// Only affects the 2-body scenario.
    var isBlackHoleMode: Bool = false

    /// True when the engine was created with exactly two bodies. Enables the
    /// star–planet features: absorption, tidal stripping, precession, proper time.
    let isTwoBodyScenario: Bool

    /// Bookkeeping for the 2-body feature set.
    var twoBodyState = TwoBodyState()

    /// Bookkeeping for the N-body feature set.
    var nBodyState: NBodyState

    /// - Precondition: `bodies` must not be empty.
    init(bodies: [CelestialBody]) {
        precondition(!bodies.isEmpty, "GravitySimulationEngine needs at least one body")
        let initial = NBodyGravity.withAccelerations(bodies)
        self.bodies = initial
        self.isTwoBodyScenario = initial.count == 2
        self.nBodyState = NBodyState(bodies: initial)

        if isTwoBodyScenario {
            twoBodyState.body2InitialMass = initial[1].mass
            twoBodyState.previousSeparation = (initial[1].position - initial[0].position).magnitude
            updateMetrics()
        } else {
            updateSystemMetrics()
        }
    }

    // MARK: - Acceleration Computation

    /// Accelerations on a star–planet pair, as (a1, a2).
    ///
    /// Thin wrapper over `NBodyGravity.accelerations(of:)`, kept for callers
    /// that work with an explicit pair.
    static func computeAccelerations(
        body1: CelestialBody,
        body2: CelestialBody
    ) -> (Vector3D, Vector3D) {
        let accelerations = NBodyGravity.accelerations(of: [body1, body2])
        return (accelerations[0], accelerations[1])
    }

    // MARK: - Simulation Step

    /// Advances the simulation by one time step `dt`.
    ///
    /// Integration is Velocity-Verlet (Störmer-Verlet), a second-order
    /// symplectic integrator that keeps energy error bounded over long runs —
    /// essential for orbital simulations. The scenario-specific step wraps the
    /// shared `integrate(dt:)` with its own collision and bookkeeping logic.
    func step(dt: Double) {
        if isTwoBodyScenario {
            stepTwoBody(dt: dt)
        } else {
            stepNBody(dt: dt)
        }
    }

    /// Velocity-Verlet update of every body (shared by both scenarios).
    func integrate(dt: Double) {
        bodies = NBodyGravity.verletStep(bodies, dt: dt)
    }
}
