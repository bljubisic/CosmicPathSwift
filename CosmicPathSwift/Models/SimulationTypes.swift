//
//  SimulationTypes.swift
//  CosmicPathSwift
//
//  Shared value types used across the simulation: vector math,
//  celestial body data, relativistic metrics, and configuration.
//
//  This file contains no physics logic — only data structures.
//  Physics lives in NBodyGravity.swift and SimulationEngineProtocol.swift.
//
//  ## 3D Coordinate System
//
//  The simulation operates in a right-handed 3D coordinate system:
//    • x-axis: initial radial direction (body2 starts here)
//    • y-axis: tangential direction (initial orbital velocity)
//    • z-axis: out of the orbital plane (non-zero for inclined orbits)
//
//  At zero inclination the orbit lies entirely in the x-y plane and
//  matches the original 2D behavior. Non-zero inclination rotates the
//  initial velocity out of the x-y plane, creating a tilted orbit.
//

import Foundation
import SwiftUI

// MARK: - Vector3D

/// A 3D vector used for positions, velocities, and forces in the simulation.
///
/// Replaces the former `Vector2D` now that orbits are computed in full
/// 3D space. The cross-product operation is essential for computing the
/// specific angular momentum L = r × v used in the Schwarzschild GR
/// correction term -3GML²/(c²r⁴).
struct Vector3D: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3D(x: 0, y: 0, z: 0)

    static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    /// Negation: returns a vector pointing in the opposite direction.
    static prefix func - (vec: Vector3D) -> Vector3D {
        Vector3D(x: -vec.x, y: -vec.y, z: -vec.z)
    }

    /// Scalar multiplication (scalar on the left).
    static func * (scalar: Double, vec: Vector3D) -> Vector3D {
        Vector3D(x: scalar * vec.x, y: scalar * vec.y, z: scalar * vec.z)
    }

    /// Scalar multiplication (scalar on the right).
    static func * (vec: Vector3D, scalar: Double) -> Vector3D {
        Vector3D(x: vec.x * scalar, y: vec.y * scalar, z: vec.z * scalar)
    }

    /// Dot product: returns the scalar projection of one vector onto another.
    func dot(_ other: Vector3D) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    /// Cross product: returns a vector perpendicular to both `self` and `other`.
    ///
    /// The magnitude |self × other| equals the specific angular momentum L
    /// for an orbiting body (|r × v|), which is conserved in central-force
    /// motion and enters the Schwarzschild GR correction term L².
    func cross(_ other: Vector3D) -> Vector3D {
        Vector3D(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    var magnitudeSquared: Double {
        x * x + y * y + z * z
    }

    var magnitude: Double {
        sqrt(magnitudeSquared)
    }

    /// Returns a unit vector in the same direction, or `.zero` if the magnitude is zero.
    var normalized: Vector3D {
        let mag = magnitude
        guard mag > 0 else { return .zero }
        return Vector3D(x: x / mag, y: y / mag, z: z / mag)
    }
}

// MARK: - BodyKind

/// Rendering category of a celestial body. Physics treats all kinds identically.
enum BodyKind: Equatable, Sendable {
    case star
    case planet
    case moon
}

// MARK: - CelestialBody

/// Represents a celestial body with mass, position, velocity, and a trail of past positions.
///
/// All kinematic quantities are 3D vectors, enabling fully inclined orbits.
/// The trail stores the body's recent history in simulation space; it is
/// projected to canvas space by `CoordinateTransformer` before rendering.
struct CelestialBody {
    /// Stable identifier that survives merges (the surviving body keeps its ID).
    /// Used to pick per-body colours in 3-body mode and in status overlays.
    var id: Int = 0
    /// What the body represents; drives rendered size and gradient style.
    var kind: BodyKind = .planet
    var mass: Double
    var position: Vector3D
    var velocity: Vector3D
    var acceleration: Vector3D = .zero

    /// Simulation-space positions from recent frames, newest at the end.
    /// Capped at `maxTrailLength` to bound memory usage.
    var trail: [Vector3D] = []

    /// Maximum number of trail positions to retain.
    static let maxTrailLength = 800
}

// MARK: - BleedParticle

/// A fragment of material stripped from the planet by tidal forces near the Roche limit.
///
/// Each particle is emitted at the planet's position when it enters the Roche limit,
/// inherits a fraction of the planet's velocity, and then falls freely under the
/// central body's Newtonian gravity. It fades out over `maxLife` simulation time units.
struct BleedParticle {
    var position: Vector3D
    var velocity: Vector3D
    /// Normalised remaining lifetime: 1.0 = just emitted, 0.0 = fully faded.
    var life: Double

    /// Simulation time units a particle lives before fully fading.
    static let maxLife: Double = 15.0
    /// Life decrease per simulation time unit (= 1 / maxLife).
    static let decayRate: Double = 1.0 / maxLife
}

// MARK: - RelativisticMetrics

/// Observable metrics derived from the Schwarzschild geodesic simulation.
///
/// These values are computed each frame by `GravitySimulationEngine.updateMetrics()`
/// and exposed to the UI through `SimulationViewModel.metrics`. All quantities
/// are derived from the Schwarzschild metric and the current orbital state.
struct RelativisticMetrics {

    // MARK: - Schwarzschild Radii
    //
    // The Schwarzschild solution defines three physically significant radii
    // for a non-rotating black hole of mass M:

    /// Event horizon radius: rₛ = 2GM/c².
    /// The boundary beyond which nothing (including light) can escape.
    /// In the Schwarzschild metric, the g₀₀ component vanishes here.
    var schwarzschildRadius: Double = 0

    /// Photon sphere radius: rₚₕ = 1.5 rₛ = 3GM/c².
    /// Photons can orbit here in unstable circular paths. Any perturbation
    /// causes them to either escape to infinity or spiral into the horizon.
    var photonSphereRadius: Double = 0

    /// Innermost stable circular orbit: rᵢₛ = 3 rₛ = 6GM/c².
    /// The smallest radius at which a massive particle can maintain a stable
    /// circular orbit. Below this, the GR correction term -3GML²/(c²r⁴)
    /// overwhelms the centrifugal barrier and no stable orbit exists.
    var iscoRadius: Double = 0

    // MARK: - Time Dilation

    /// Gravitational time dilation factor: √(1 - rₛ/r).
    /// Derived from the g₀₀ component of the Schwarzschild metric for a
    /// stationary observer at distance r. Ranges from 1.0 (flat spacetime,
    /// no dilation) to 0.0 (at the event horizon, time stops for a distant observer).
    /// Note: This is the purely gravitational component; the full proper time
    /// rate also includes velocity-based dilation (see `properTime`).
    var timeDilationFactor: Double = 1.0

    // MARK: - Orbital Dynamics

    /// Number of complete orbits body2 has completed, incremented each time
    /// the engine detects a perihelion passage (local minimum in separation).
    /// A Newtonian orbit increments this once per revolution; GR precession
    /// shifts the perihelion each orbit, but the count is still exact.
    var orbitsCompleted: Int = 0

    /// Accumulated perihelion precession angle in degrees.
    /// In GR, orbits do not close — the perihelion advances by a small angle
    /// each orbit due to the -3GML²/(c²r⁴) curvature term. For Mercury, this
    /// is 43 arcseconds/century. In our scaled simulation, precession is much
    /// larger and visually apparent as a rosette orbit pattern.
    ///
    /// For inclined orbits, this is measured as the angle in the x-y projection;
    /// it approximates the true in-plane precession for small inclinations.
    var precessionAngle: Double = 0

    /// Speed of the orbiting body as a fraction of c (β = v/c).
    /// Ranges from 0 (stationary) to approaching 1 (near light speed).
    var velocityFractionOfC: Double = 0

    /// Current 3D distance between the two bodies in simulation units.
    var separation: Double = 0

    /// Lorentz factor: γ = 1/√(1 - v²/c²).
    /// From special relativity, this factor governs relativistic mass increase,
    /// length contraction, and time dilation due to velocity. Approaches ∞
    /// as v → c. Combined with gravitational time dilation in the proper time
    /// calculation via the full Schwarzschild metric.
    var lorentzGamma: Double = 1.0

    // MARK: - Black Hole State

    /// Whether body1 is classified as a black hole for rendering purposes.
    /// Requires both `isBlackHoleMode` to be enabled AND the Schwarzschild
    /// radius to exceed the visual threshold (8 simulation pixels).
    var isBlackHole: Bool = false

    /// Whether body2 has crossed the event horizon and been absorbed.
    /// Once true, the simulation freezes body2 at body1's position and
    /// stops further integration steps.
    var isAbsorbed: Bool = false

    /// Accumulated proper time τ of the orbiting body (body2).
    /// Proper time is the physical time measured by a clock traveling with
    /// the body. It is always less than coordinate time t due to the combined
    /// effect of gravitational and velocity time dilation, both unified in
    /// the Schwarzschild metric: dτ/dt = √((1 - rₛ/r) - v²/c²).
    var properTime: Double = 0

    /// Color representing the current gravitational time dilation severity.
    /// Transitions from cyan (weak field) through blue and purple to
    /// red (extreme dilation near the event horizon).
    var timeDilationColor: Color {
        if timeDilationFactor > 0.9 {
            return .cyan
        } else if timeDilationFactor > 0.7 {
            return .blue
        } else if timeDilationFactor > 0.5 {
            return .purple
        } else {
            return .red
        }
    }
}

// MARK: - SystemMetrics

/// System-wide metrics for 3-body mode, updated by the engine every step.
///
/// Unlike `RelativisticMetrics` (which describes body2's orbit around body1),
/// these describe the whole N-body system and make no assumption about which
/// body is "central".
struct SystemMetrics {
    /// Coordinate time elapsed since the simulation started (simulation units).
    var elapsedTime: Double = 0

    /// Relative Newtonian energy drift ΔE/E₀.
    ///
    /// Energy lost in inelastic merges is excluded, so this tracks only integrator
    /// error plus the non-conservative part of the GR correction term — it is
    /// nonzero partly because GR is switched on.
    var energyDrift: Double = 0

    /// Smallest pairwise separation reached so far (simulation pixels).
    var closestApproach: Double = .infinity

    /// Largest speed any body has reached so far, as a fraction of c.
    var maxVelocityFractionOfC: Double = 0

    /// ID of the first body that escaped the system, if any.
    var ejectedBodyID: Int?

    /// IDs of the most recent merge as (survivor, absorbed), if any.
    var collision: (Int, Int)?

    /// Short human-readable status for the metrics panel.
    var statusLabel: String {
        if collision != nil { return "Merged" }
        if ejectedBodyID != nil { return "Ejected" }
        return "Bound"
    }

    /// Letter label ("A", "B", "C", …) for a body ID, used in overlays and legends.
    static func letter(for id: Int) -> String {
        guard let scalar = UnicodeScalar(65 + max(0, id)) else { return "?" }
        return String(Character(scalar))
    }
}

// MARK: - Simulation Mode

/// Top-level scenario: the original star–planet pair or a general 3-body system.
enum SimulationMode: String, CaseIterable, Equatable, Sendable {
    case twoBody
    case threeBody

    var displayName: String {
        switch self {
        case .twoBody: return "2-Body"
        case .threeBody: return "3-Body"
        }
    }
}

/// Initial-condition presets for 3-body mode.
///
/// Each preset also carries its own integration settings because close encounters
/// need finer steps; `stepsPerFrame` compensates so the on-screen pace stays comfortable.
enum ThreeBodyPreset: String, CaseIterable, Equatable, Sendable {
    case figureEight
    case lagrangeTriangle
    case sunPlanetMoon
    case pythagorean
    case custom

    var displayName: String {
        switch self {
        case .figureEight: return "Figure-8"
        case .lagrangeTriangle: return "Lagrange Triangle"
        case .sunPlanetMoon: return "Sun–Planet–Moon"
        case .pythagorean: return "Pythagorean (chaotic)"
        case .custom: return "Custom"
        }
    }

    /// Integration sub-step for this preset (simulation time units).
    var timeStep: Double {
        switch self {
        case .figureEight, .lagrangeTriangle, .custom: return 0.03
        case .sunPlanetMoon: return 0.04
        // 1e-4 in the preset's dimensionless time (time unit = 1200).
        case .pythagorean: return 0.12
        }
    }

    /// Integration sub-steps per rendered frame for this preset.
    var stepsPerFrame: Int {
        switch self {
        case .figureEight, .lagrangeTriangle, .custom: return 8
        case .sunPlanetMoon: return 6
        case .pythagorean: return 200
        }
    }
}

// MARK: - Celestial Constants

/// Astronomical constants and simulation-scale mappings.
///
/// ## Why Not SI Units?
///
/// The simulation uses scaled constants (G=500, c=200) rather than SI values
/// because SI-scale physics would be invisible at screen resolution. The real
/// Schwarzschild radius of the Sun is ~3 km — utterly invisible at any
/// reasonable zoom level. By compressing the scales, GR effects (precession,
/// time dilation, ISCO) become visually meaningful.
///
/// ## Mass Ratio Compression
///
/// The real Sun-to-Earth mass ratio is ~333,000:1. At this ratio, Earth's
/// gravitational influence would be negligible and its rendered size
/// subpixel. We use a compressed ratio of 200:5 (40:1) so both bodies
/// are visible and the orbiting body has enough mass to demonstrate
/// two-body effects.
///
/// ## Schwarzschild Radius at Simulation Scale
///
/// With G=500, c=200 (c²=40,000): rₛ = 2GM/c² = M/40.
/// - For 1 M☉ (mass=200):     rₛ = 5 pixels (below visual threshold)
/// - For BH mode (mass=5000):  rₛ = 125 pixels (clearly visible)
enum CelestialConstants {
    /// Solar mass in kg: 1.989 × 10³⁰ kg (reference only, not used in physics)
    static let solarMassKg: Double = 1.989e30
    /// Earth mass in kg: 5.972 × 10²⁴ kg (reference only, not used in physics)
    static let earthMassKg: Double = 5.972e24
    /// Real mass ratio: M☉ / M⊕ ≈ 333,000 (reference only)
    static let realMassRatio: Double = solarMassKg / earthMassKg

    /// Base simulation mass for 1 M☉.
    /// With G=500, c²=40000: this gives rₛ = 2×500×200/40000 = 5 pixels.
    static let baseSolarMass: Double = 200.0

    /// Base simulation mass for 1 M⊕.
    /// Compressed ratio (200:5 = 40:1 vs. real 333,000:1) so that Earth
    /// is visible and its gravitational back-reaction on the star is noticeable.
    static let baseEarthMass: Double = 5.0

    /// 1 AU in simulation pixels.
    /// This is the reference orbital separation for a 1 M☉ + 1 M⊕ system.
    /// At this distance with mass=200, rₛ/r = 5/150 ≈ 0.033, giving
    /// measurable but not extreme relativistic effects.
    static let baseAU: Double = 150.0

    /// Extra margin factor applied to the initial orbital separation when setting
    /// up the coordinate transformer. Ensures the full orbit (which may be eccentric)
    /// fits on screen without waiting for dynamic zoom to kick in.
    static let orbitMarginFactor: Double = 1.3

    /// Black hole mode base mass.
    /// With G=500, c²=40000: rₛ = 2×500×5000/40000 = 125 pixels,
    /// well above the visual threshold of 8 pixels. This makes the
    /// event horizon, photon sphere (188 px), and ISCO (375 px)
    /// clearly visible on screen.
    static let blackHoleSolarMass: Double = 5000.0
}

// MARK: - SimulationConfig

/// Configuration for the initial simulation parameters.
///
/// Users adjust dimensionless multipliers (mass1Multiplier, mass2Multiplier,
/// separationAU, inclinationDeg) through UI sliders. These are converted to
/// simulation-scale values via the computed properties.
struct SimulationConfig: Equatable {
    /// Multiplier for the central body mass in units of M☉ (solar masses).
    /// The simulation mass is `baseSolarMass × mass1Multiplier` (or
    /// `blackHoleSolarMass × mass1Multiplier` in black hole mode).
    var mass1Multiplier: Double = 1.0

    /// Multiplier for the orbiting body mass in units of M⊕ (Earth masses).
    /// The simulation mass is `baseEarthMass × mass2Multiplier`.
    var mass2Multiplier: Double = 1.0

    /// Orbital separation in astronomical units (AU).
    /// The simulation separation in pixels is `baseAU × separationAU`.
    var separationAU: Double = 1.0

    /// Orbital inclination in degrees relative to the x-y plane.
    ///
    /// At 0° the orbit lies flat in the x-y plane (matching the original 2D
    /// behavior). At 90° the orbit is polar — perpendicular to the default
    /// viewing plane. The inclination rotates the initial tangential velocity
    /// out of the x-y plane, producing a tilted Schwarzschild geodesic.
    ///
    /// Range: 0° to 90°. Use the camera drag gesture to appreciate the 3D
    /// structure of inclined orbits.
    var inclinationDeg: Double = 0.0

    /// Whether to use the black hole mass range for body1.
    /// When true, body1's base mass switches from `baseSolarMass` (200) to
    /// `blackHoleSolarMass` (5000), making the Schwarzschild radius large
    /// enough to be visually rendered (rₛ = 125 px at 1× multiplier).
    var isBlackHoleMode: Bool = false

    /// Integration time step per sub-step in simulation time units.
    /// Smaller values improve accuracy but slow the simulation.
    var timeStep: Double = 0.02

    /// Number of integration sub-steps per display frame.
    /// At 60 fps with 4 steps/frame, the simulation advances 4×0.02 = 0.08
    /// time units per rendered frame.
    var stepsPerFrame: Int = 4

    // MARK: - Mode Selection

    /// Which scenario to simulate. Switching modes re-runs setup.
    var mode: SimulationMode = .twoBody

    /// Active preset when `mode == .threeBody`.
    var threeBodyPreset: ThreeBodyPreset = .figureEight

    // MARK: - Custom 3-Body Parameters

    /// Mass multipliers for the three bodies of the Custom preset (one entry per body).
    var customMassMultipliers: [Double] = [1.0, 1.0, 1.0]

    /// Side-length multiplier of the Custom preset's starting triangle.
    var customSpreadAU: Double = 1.0

    /// Scales the Lagrange rigid-rotation velocities of the Custom preset.
    /// 1.0 = rigid rotation; other values give eccentric or chaotic motion.
    var customVelocityFactor: Double = 1.0

    // MARK: - Derived Simulation Values

    /// The simulation mass for body 1 (central body).
    var simulationMass1: Double {
        if isBlackHoleMode {
            return CelestialConstants.blackHoleSolarMass * mass1Multiplier
        }
        return CelestialConstants.baseSolarMass * mass1Multiplier
    }

    /// The simulation mass for body 2 (orbiting body).
    var simulationMass2: Double {
        return CelestialConstants.baseEarthMass * mass2Multiplier
    }

    /// The simulation separation in pixels.
    var simulationSeparation: Double {
        return CelestialConstants.baseAU * separationAU
    }

    /// Orbital inclination converted to radians for physics calculations.
    var inclinationRad: Double {
        inclinationDeg * .pi / 180.0
    }

    // MARK: - Display Labels

    /// Formatted display string for body 1 mass.
    var mass1Label: String {
        if mass1Multiplier == 1.0 {
            return "1 M\u{2609}"
        } else if mass1Multiplier < 10 {
            return String(format: "%.1f M\u{2609}", mass1Multiplier)
        } else {
            return String(format: "%.0f M\u{2609}", mass1Multiplier)
        }
    }

    /// Formatted display string for body 2 mass.
    var mass2Label: String {
        if mass2Multiplier == 1.0 {
            return "1 M\u{2295}"
        } else if mass2Multiplier < 10 {
            return String(format: "%.1f M\u{2295}", mass2Multiplier)
        } else {
            return String(format: "%.0f M\u{2295}", mass2Multiplier)
        }
    }

    /// Formatted display string for orbital separation.
    var separationLabel: String {
        if separationAU < 10 {
            return String(format: "%.1f AU", separationAU)
        } else {
            return String(format: "%.0f AU", separationAU)
        }
    }

    /// Formatted display string for orbital inclination.
    var inclinationLabel: String {
        String(format: "%.0f°", inclinationDeg)
    }
}
