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
    /// Cyan = negligible dilation, red = extreme dilation.
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

// MARK: - SimulationConfig

/// Configuration for the initial simulation parameters.
struct SimulationConfig: Equatable {
    var mass1: Double = 200.0
    var mass2: Double = 5.0
    var initialSeparation: Double = 150.0
    var isBlackHoleMode: Bool = false
    var timeStep: Double = 0.02
    var stepsPerFrame: Int = 4
}
