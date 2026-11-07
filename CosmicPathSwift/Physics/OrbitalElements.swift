//
//  OrbitalElements.swift
//  CosmicPathSwift
//
//  Stateless 2-body diagnostics (issue #20, PR 6): osculating orbital
//  elements, the conserved quantities of the relative orbit, and the
//  measured-vs-predicted perihelion precession.
//
//  ## Relative orbit
//
//  With r = r₂ − r₁ and v = v₂ − v₁, the pair force gives
//
//      r̈ = (−GM/r² − 3GML²/(c²r⁴)) r̂,   M = m₁ + m₂,  L = |r × v|
//
//  The force is central, so L is conserved. With L constant,
//
//      E = ½v² − GM/r − GML²/(c²r³)
//
//  is conserved too: its time derivative cancels term by term. Any change in
//  E or L during a run is therefore integrator error, not physics.
//

import Foundation

// MARK: - OrbitalElements

/// Newtonian osculating elements of the relative orbit at one instant.
///
/// The GR term makes the true orbit differ slightly from the ellipse these
/// describe, so they wobble a little around each orbit.
struct OrbitalElements: Equatable, Sendable {
    /// Semi-major axis a = −GM/(2ε) in simulation pixels. Negative for a
    /// hyperbola, infinite for a parabola.
    let semiMajorAxis: Double
    /// Eccentricity |e|: 0 circular, < 1 bound, ≥ 1 unbound.
    let eccentricity: Double
    /// Orbital period 2π√(a³/GM); nil when the orbit is unbound.
    let period: Double?

    /// True for a closed (elliptical) orbit.
    var isBound: Bool { period != nil }

    /// Elements from the relative state.
    ///
    /// ε = v²/2 − μ/r,  a = −μ/(2ε),
    /// e = ((v² − μ/r) r − (r·v) v) / μ,  T = 2π√(a³/μ),  with μ = GM.
    static func osculating(
        relativePosition r: Vector3D,
        relativeVelocity v: Vector3D,
        totalMass: Double,
        constants: PhysicalConstants = .visual
    ) -> OrbitalElements {
        let mu = constants.G * totalMass
        let distance = r.magnitude
        guard mu > 0, distance > 0 else {
            return OrbitalElements(semiMajorAxis: .infinity, eccentricity: .infinity, period: nil)
        }
        let speedSquared = v.magnitudeSquared
        let specificEnergy = 0.5 * speedSquared - mu / distance
        let semiMajorAxis = -mu / (2 * specificEnergy)
        let eVector = (r * (speedSquared - mu / distance) - v * r.dot(v)) * (1 / mu)
        let period = specificEnergy < 0 ? 2 * .pi * sqrt(pow(semiMajorAxis, 3) / mu) : nil
        return OrbitalElements(semiMajorAxis: semiMajorAxis, eccentricity: eVector.magnitude, period: period)
    }
}

// MARK: - RelativeOrbit

/// Conserved quantities of the GR-corrected relative orbit.
enum RelativeOrbit {
    /// E = ½v² − GM/r − GML²/(c²r³), with r clamped at the softening length
    /// like the force law.
    static func energy(
        r: Vector3D, v: Vector3D, totalMass: Double, softening: Double, constants: PhysicalConstants = .visual
    ) -> Double {
        let gm = constants.G * totalMass
        let distance = max(r.magnitude, softening)
        let l = angularMomentum(r: r, v: v)
        return 0.5 * v.magnitudeSquared - gm / distance
            - gm * l * l / (constants.cSquared * distance * distance * distance)
    }

    /// Specific angular momentum L = |r × v|.
    static func angularMomentum(r: Vector3D, v: Vector3D) -> Double {
        r.cross(v).magnitude
    }
}

// MARK: - PrecessionComparison

/// Measured perihelion advance per orbit next to the weak-field prediction.
struct PrecessionComparison: Equatable, Sendable {
    /// Average measured advance per orbit, in degrees.
    let measuredPerOrbit: Double
    /// 6πGM/(c²p) in degrees.
    let predictedPerOrbit: Double

    /// measured / predicted. The weak-field formula is first-order; with the
    /// app's strong GR the next term adds about (18 + e²)/4 · GM/(c²p).
    var ratio: Double {
        predictedPerOrbit > 0 ? measuredPerOrbit / predictedPerOrbit : .nan
    }

    init(
        measuredPerOrbit: Double, totalMass: Double, periapsis: Double, apoapsis: Double,
        constants: PhysicalConstants = .visual
    ) {
        self.measuredPerOrbit = measuredPerOrbit
        self.predictedPerOrbit = Self.predicted(
            totalMass: totalMass, periapsis: periapsis, apoapsis: apoapsis, constants: constants
        )
    }

    /// Weak-field advance per orbit in degrees: Δφ = 6πGM/(c²p), with the
    /// semi-latus rectum p = a(1 − e²) = 2 rₚ rₐ / (rₚ + rₐ) taken from the
    /// measured turning points.
    static func predicted(
        totalMass: Double, periapsis: Double, apoapsis: Double, constants: PhysicalConstants = .visual
    ) -> Double {
        let sum = periapsis + apoapsis
        guard sum > 0 else { return 0 }
        let semiLatusRectum = 2 * periapsis * apoapsis / sum
        guard semiLatusRectum > 0 else { return 0 }
        let gm = constants.G * totalMass
        let radians = 6 * .pi * gm / (constants.cSquared * semiLatusRectum)
        return radians * 180 / .pi
    }
}
