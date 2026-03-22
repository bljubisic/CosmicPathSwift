//
//  SimulationTypes.swift
//  CosmicPathSwift
//
//  Shared value types used across the simulation: vector math,
//  celestial body data, relativistic metrics, and configuration.
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

/// Observable metrics derived from the relativistic simulation.
struct RelativisticMetrics {
    /// Schwarzschild radius of the heavy body: r_s = 2GM/c²
    var schwarzschildRadius: Double = 0
    /// Photon sphere radius: r_ph = 1.5 * r_s
    var photonSphereRadius: Double = 0
    /// Innermost stable circular orbit: r_isco = 3 * r_s
    var iscoRadius: Double = 0
    /// Current proper time dilation factor for the lighter body: sqrt(1 - r_s/r)
    var timeDilationFactor: Double = 1.0
    /// Accumulated perihelion precession angle in degrees
    var precessionAngle: Double = 0
    /// Current speed of lighter body as fraction of c
    var velocityFractionOfC: Double = 0
    /// Current separation between bodies
    var separation: Double = 0
    /// The Lorentz factor gamma for the lighter body
    var lorentzGamma: Double = 1.0
    /// Whether the central body qualifies as a black hole
    var isBlackHole: Bool = false
    /// Whether the orbiting body has been absorbed past the event horizon
    var isAbsorbed: Bool = false

    /// Color representing the current time dilation severity.
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

/// Real-world astronomical constants used for display and scaling.
enum CelestialConstants {
    /// Solar mass in kg: 1.989 × 10³⁰ kg
    static let solarMassKg: Double = 1.989e30
    /// Earth mass in kg: 5.972 × 10²⁴ kg
    static let earthMassKg: Double = 5.972e24
    /// Real mass ratio: M☉ / M⊕ ≈ 333,000
    static let realMassRatio: Double = solarMassKg / earthMassKg

    /// Base simulation mass for 1 M☉ (tuned for visual dynamics)
    static let baseSolarMass: Double = 200.0
    /// Base simulation mass for 1 M⊕ (compressed ratio for visual dynamics)
    /// Using compressed ratio so Earth is not invisibly small in the simulation.
    static let baseEarthMass: Double = 5.0

    /// 1 AU in simulation pixels (reference separation for 1 M☉ + 1 M⊕)
    static let baseAU: Double = 150.0

    /// Black hole mode base mass (tuned for visible Schwarzschild radius)
    static let blackHoleSolarMass: Double = 5000.0
}

// MARK: - SimulationConfig

/// Configuration for the initial simulation parameters.
/// Mass sliders are multipliers of solar/earth mass.
struct SimulationConfig: Equatable {
    /// Multiplier for M☉ (central body mass)
    var mass1Multiplier: Double = 1.0
    /// Multiplier for M⊕ (orbiting body mass)
    var mass2Multiplier: Double = 1.0
    /// Separation multiplier in AU
    var separationAU: Double = 1.0
    /// Whether to use black hole mass range
    var isBlackHoleMode: Bool = false
    var timeStep: Double = 0.02
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
