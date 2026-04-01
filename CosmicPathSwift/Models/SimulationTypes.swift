//
//  SimulationTypes.swift
//  CosmicPathSwift
//
//  Shared value types used across the simulation: vector math,
//  celestial body data, relativistic metrics, and configuration.
//
//  This file contains no physics logic — only data structures.
//  All physics computations are in SimulationEngineProtocol.swift.
//

import Foundation
import SwiftUI

// MARK: - Vector2D

/// A 2D vector used for positions, velocities, and forces.
struct Vector2D: Equatable {
    var x: Double
    var y: Double

    static let zero = Vector2D(x: 0, y: 0)

    static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (scalar: Double, vec: Vector2D) -> Vector2D {
        Vector2D(x: scalar * vec.x, y: scalar * vec.y)
    }

    static func * (vec: Vector2D, scalar: Double) -> Vector2D {
        Vector2D(x: vec.x * scalar, y: vec.y * scalar)
    }

    /// Dot product of two vectors.
    func dot(_ other: Vector2D) -> Double {
        x * other.x + y * other.y
    }

    var magnitudeSquared: Double {
        x * x + y * y
    }

    var magnitude: Double {
        sqrt(magnitudeSquared)
    }

    var normalized: Vector2D {
        let mag = magnitude
        guard mag > 0 else { return .zero }
        return Vector2D(x: x / mag, y: y / mag)
    }
}

// MARK: - CelestialBody

/// Represents a celestial body with mass, position, velocity, and a trail of past positions.
struct CelestialBody {
    var mass: Double
    var position: Vector2D
    var velocity: Vector2D
    var acceleration: Vector2D = .zero
    var trail: [Vector2D] = []

    static let maxTrailLength = 800
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

    /// Accumulated perihelion precession angle in degrees.
    /// In GR, orbits do not close — the perihelion advances by a small angle
    /// each orbit due to the -3GML²/(c²r⁴) curvature term. For Mercury, this
    /// is 43 arcseconds/century. In our scaled simulation, precession is much
    /// larger and visually apparent as a rosette orbit pattern.
    var precessionAngle: Double = 0

    /// Speed of the orbiting body as a fraction of c (β = v/c).
    /// Ranges from 0 (stationary) to approaching 1 (near light speed).
    var velocityFractionOfC: Double = 0

    /// Current distance between the two bodies in simulation units.
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
/// separationAU) through UI sliders. These are converted to simulation-scale
/// values via the computed properties, which multiply by the base constants
/// in `CelestialConstants`.
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

    /// Formatted display string for separation.
    var separationLabel: String {
        if separationAU < 10 {
            return String(format: "%.1f AU", separationAU)
        } else {
            return String(format: "%.0f AU", separationAU)
        }
    }
}
