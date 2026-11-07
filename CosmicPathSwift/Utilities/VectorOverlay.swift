//
//  VectorOverlay.swift
//  CosmicPathSwift
//
//  Velocity and acceleration arrows for the Advanced sheet (issue #20).
//
//  ## Scaling
//
//  Velocity and acceleration have different units, so each is converted to a
//  displacement using the system's dynamical time t = √(R³/GM), fixed at setup:
//
//      velocity arrow     = f · v · t
//      acceleration arrow = f · a · t²
//
//  For a circular orbit of radius R, v·t = R and a·t² = R, so both arrows are
//  f·R long (f = `lengthFraction`). The scale stays fixed during a run, so
//  arrow lengths can be compared over time and between bodies. Close encounters
//  can produce huge accelerations, so arrows are clamped to `maxLength`.
//

import Foundation
import CoreGraphics

/// A projected arrow in canvas space, from a body (`tail`) to the vector's tip (`head`).
struct CanvasArrow: Equatable {
    let tail: CGPoint
    let head: CGPoint
}

enum VectorOverlay {

    /// Which per-body vector to draw.
    enum Kind: Sendable {
        case velocity
        case acceleration

        func vector(of body: CelestialBody) -> Vector3D {
            switch self {
            case .velocity: return body.velocity
            case .acceleration: return body.acceleration
            }
        }

        /// Time (or time²) that turns this vector into a displacement.
        func timeFactor(dynamicalTime t: Double) -> Double {
            switch self {
            case .velocity: return t
            case .acceleration: return t * t
            }
        }
    }

    /// Arrow length for a circular orbit, as a fraction of its radius.
    static let lengthFraction: Double = 0.3

    /// Dynamical time √(R³/GM) of a system of total mass M and extent R.
    /// Returns 0 when either is not positive (no arrows are drawn then).
    static func dynamicalTime(extent: Double, totalMass: Double, constants: PhysicalConstants = .visual) -> Double {
        guard extent > 0, totalMass > 0 else { return 0 }
        return sqrt(extent * extent * extent / (constants.G * totalMass))
    }

    /// Simulation-space displacement for `vector`, clamped to `maxLength`.
    static func displacement(
        _ vector: Vector3D,
        kind: Kind,
        dynamicalTime: Double,
        maxLength: Double
    ) -> Vector3D {
        let scaled = vector * (lengthFraction * kind.timeFactor(dynamicalTime: dynamicalTime))
        let length = scaled.magnitude
        guard length > maxLength, length > 0 else { return scaled }
        return scaled * (maxLength / length)
    }

    /// One canvas arrow per body, index-aligned with `bodies`.
    static func arrows(
        for bodies: [CelestialBody],
        kind: Kind,
        dynamicalTime: Double,
        maxLength: Double,
        transformer: CoordinateTransformer
    ) -> [CanvasArrow] {
        bodies.map { body in
            let offset = displacement(
                kind.vector(of: body), kind: kind, dynamicalTime: dynamicalTime, maxLength: maxLength
            )
            return CanvasArrow(
                tail: transformer.simulationToCanvas(body.position),
                head: transformer.simulationToCanvas(body.position + offset)
            )
        }
    }
}
