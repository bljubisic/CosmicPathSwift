//
//  SimulationEngineProtocol.swift
//  CosmicPathSwift
//
//  Defines the contract for a simulation engine and provides the
//  GR-based implementation using the Einstein-Infeld-Hoffmann equations.
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

/// Simulation engine using Einstein's General Relativity (1PN approximation).
///
/// The relativistic acceleration on body i due to body j is:
///   a_Newton = -GM/r² * r̂
///   a_GR     = a_Newton + (GM / c²r³) * [ (4GM/r - v²) * r + 4(v·r̂) * v ]
class GravitySimulationEngine: SimulationEngineProtocol {
    // Physics constants (scaled for visual simulation, not SI units)
    static let G: Double = 500.0
    static let c: Double = 200.0
    static let cSquared: Double = c * c
    static let softening: Double = 5.0

    /// Black hole threshold: body1 is a black hole when its Schwarzschild
    /// radius is large enough to be visually meaningful (> 8 pixels).
    static let blackHoleThreshold: Double = 8.0

    private(set) var body1: CelestialBody
    private(set) var body2: CelestialBody
    private(set) var metrics = RelativisticMetrics()
    var isBlackHoleMode: Bool = false

    // Perihelion tracking for precession measurement
    private var previousSeparation: Double = .infinity
    private var wasShrinking: Bool = true
    private var lastPerihelionAngle: Double?
    private var accumulatedPrecession: Double = 0
    private var orbitsCompleted: Int = 0

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

    /// Computes the 1PN (first post-Newtonian) relativistic accelerations
    /// using the Einstein-Infeld-Hoffmann equation at first order.
    static func computeAccelerations(
        body1: CelestialBody,
        body2: CelestialBody
    ) -> (Vector2D, Vector2D) {
        let r12 = body2.position - body1.position
        let dist = max(r12.magnitude, softening)
        let rHat = r12.normalized

        let a1 = relativisticAcceleration(
            sourceMass: body2.mass,
            separation: r12,
            distance: dist,
            rHat: rHat,
            velocity: body1.velocity
        )

        let a2 = relativisticAcceleration(
            sourceMass: body1.mass,
            separation: Vector2D(x: -r12.x, y: -r12.y),
            distance: dist,
            rHat: Vector2D(x: -rHat.x, y: -rHat.y),
            velocity: body2.velocity
        )

        return (a1, a2)
    }

    /// Computes the relativistic acceleration on a test body due to a source mass.
    private static func relativisticAcceleration(
        sourceMass M: Double,
        separation r: Vector2D,
        distance dist: Double,
        rHat: Vector2D,
        velocity v: Vector2D
    ) -> Vector2D {
        let GM = G * M
        let r2 = dist * dist
        let r3 = r2 * dist

        // Newtonian term: a_N = GM/r² * r̂  (toward source)
        let newtonianMag = GM / r2
        let newtonian = newtonianMag * rHat

        // 1PN General Relativity correction:
        // a_GR = GM/(c²r³) * [ (4GM/r - v²)*r + 4*(v·r̂)*v ]
        let vSquared = v.magnitudeSquared
        let vDotRhat = v.dot(rHat)

        let grCoeff = GM / (cSquared * r3)
        let term1Scalar = (4.0 * GM / dist) - vSquared
        let term1 = term1Scalar * r
        let term2 = (4.0 * vDotRhat) * v

        let grCorrection = grCoeff * (term1 + term2)

        return newtonian + grCorrection
    }

    // MARK: - Simulation Step

    /// Advances the simulation by one time step using the Velocity-Verlet integrator.
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
            return
        }

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

    private func updateMetrics() {
        let r = (body2.position - body1.position).magnitude
        let v2Speed = body2.velocity.magnitude

        let rs = 2.0 * Self.G * body1.mass / Self.cSquared
        metrics.schwarzschildRadius = rs
        metrics.photonSphereRadius = 1.5 * rs
        metrics.iscoRadius = 3.0 * rs
        metrics.isBlackHole = isBlackHoleMode && rs >= Self.blackHoleThreshold

        let ratio = min(rs / max(r, Self.softening), 0.99)
        metrics.timeDilationFactor = sqrt(1.0 - ratio)

        metrics.velocityFractionOfC = v2Speed / Self.c

        let beta2 = min((v2Speed * v2Speed) / Self.cSquared, 0.99)
        metrics.lorentzGamma = 1.0 / sqrt(1.0 - beta2)

        metrics.precessionAngle = accumulatedPrecession * 180.0 / .pi
        metrics.separation = r
    }
}
