//
//  NBodyGravity.swift
//  CosmicPathSwift
//
//  Stateless N-body gravity: pairwise GR-corrected accelerations, the
//  Velocity-Verlet step, and conservation-law helpers (CoM, momentum,
//  energy, angular momentum).
//
//  ## Pairwise Acceleration
//
//  Every body i feels, from every other body j, the same radial acceleration
//  the 2-body engine has always used:
//
//      aᵢ = Σⱼ (−Gmⱼ/rᵢⱼ² − 3GmⱼLᵢⱼ²/(c²rᵢⱼ⁴)) r̂ᵢⱼ
//
//  where rᵢⱼ = rᵢ − rⱼ points from source j to body i and
//  Lᵢⱼ = |rᵢⱼ × (vᵢ − vⱼ)| uses the *relative* velocity.
//
//  Using the relative velocity keeps the GR term independent of the reference
//  frame. With absolute velocities, two equal-mass stars would feel a different
//  GR pull depending on how fast the camera frame drifts, which is unphysical.
//
//  The GR term is an approximation, not the full 1PN Einstein-Infeld-Hoffmann
//  equations, so it is not exactly conservative: Newtonian energy slowly drifts
//  while it is on. `grEnabled: false` exists so tests can verify the integrator
//  against known Newtonian solutions; the app always passes `true`.
//

import Foundation

enum NBodyGravity {

    private static var G: Double { GravitySimulationEngine.G }
    private static var cSquared: Double { GravitySimulationEngine.cSquared }
    private static var softening: Double { GravitySimulationEngine.softening }

    // MARK: - Accelerations

    /// GR-corrected acceleration on one body caused by a single source.
    ///
    /// The centrifugal term L²/r³ of the polar geodesic equation is omitted: it
    /// cancels when converting to Cartesian coordinates, where the integrator
    /// handles it implicitly through the tangential velocity.
    ///
    /// - Parameters:
    ///   - sourceMass: Mass of the gravitating source.
    ///   - separation: Vector pointing **from the source to the body** (outward).
    ///   - relativeVelocity: Body velocity minus source velocity.
    ///   - grEnabled: When false, returns pure Newtonian gravity (tests only).
    /// - Returns: Acceleration vector pointing toward the source.
    static func pairAcceleration(
        sourceMass: Double,
        separation: Vector3D,
        relativeVelocity: Vector3D,
        grEnabled: Bool = true
    ) -> Vector3D {
        // Clamp to the softening length to prevent divergence as r → 0.
        let dist = max(separation.magnitude, softening)
        let r2 = dist * dist
        let gm = G * sourceMass

        let aNewton = -gm / r2
        var aGR = 0.0
        if grEnabled {
            // Specific angular momentum of the pair: L = |r × v_rel|.
            let angularMomentum = separation.cross(relativeVelocity).magnitude
            aGR = -3.0 * gm * angularMomentum * angularMomentum / (cSquared * r2 * r2)
        }
        // Both terms are negative (inward); multiplying by outward r̂ points to the source.
        return (aNewton + aGR) * separation.normalized
    }

    /// Accelerations on every body from all other bodies (O(N²) pair sum).
    static func accelerations(of bodies: [CelestialBody], grEnabled: Bool = true) -> [Vector3D] {
        bodies.indices.map { i in
            bodies.indices.reduce(Vector3D.zero) { total, j in
                guard j != i else { return total }
                return total + pairAcceleration(
                    sourceMass: bodies[j].mass,
                    separation: bodies[i].position - bodies[j].position,
                    relativeVelocity: bodies[i].velocity - bodies[j].velocity,
                    grEnabled: grEnabled
                )
            }
        }
    }

    /// Returns copies of `bodies` with `acceleration` set from the current state.
    static func withAccelerations(_ bodies: [CelestialBody], grEnabled: Bool = true) -> [CelestialBody] {
        zip(bodies, accelerations(of: bodies, grEnabled: grEnabled)).map { body, acc in
            var updated = body
            updated.acceleration = acc
            return updated
        }
    }

    // MARK: - Integrator

    /// Advances all bodies by one Velocity-Verlet step and returns the new state.
    ///
    /// 1. x(t+dt) = x(t) + v(t)·dt + ½·a(t)·dt²
    /// 2. a(t+dt) = F(x(t+dt), v(t)) / m
    /// 3. v(t+dt) = v(t) + ½·(a(t) + a(t+dt))·dt
    ///
    /// Each body's stored `acceleration` must hold a(t) on entry; on return it
    /// holds a(t+dt). Trails are carried over unchanged.
    static func verletStep(_ bodies: [CelestialBody], dt: Double, grEnabled: Bool = true) -> [CelestialBody] {
        let drifted = bodies.map { body -> CelestialBody in
            var moved = body
            moved.position = body.position + body.velocity * dt + 0.5 * body.acceleration * (dt * dt)
            return moved
        }
        let newAccelerations = accelerations(of: drifted, grEnabled: grEnabled)
        return zip(drifted, newAccelerations).map { body, newAcc in
            var kicked = body
            kicked.velocity = body.velocity + 0.5 * (body.acceleration + newAcc) * dt
            kicked.acceleration = newAcc
            return kicked
        }
    }

    // MARK: - Conservation Helpers

    static func totalMass(_ bodies: [CelestialBody]) -> Double {
        bodies.reduce(0) { $0 + $1.mass }
    }

    /// Mass-weighted mean position. Returns `.zero` for an empty or massless set.
    static func centerOfMass(_ bodies: [CelestialBody]) -> Vector3D {
        let mass = totalMass(bodies)
        guard mass > 0 else { return .zero }
        let weighted = bodies.reduce(Vector3D.zero) { $0 + $1.position * $1.mass }
        return weighted * (1.0 / mass)
    }

    /// Total linear momentum Σ mᵢvᵢ.
    static func totalMomentum(_ bodies: [CelestialBody]) -> Vector3D {
        bodies.reduce(Vector3D.zero) { $0 + $1.velocity * $1.mass }
    }

    /// Newtonian total energy: Σ ½mᵢvᵢ² − Σᵢ<ⱼ Gmᵢmⱼ / max(rᵢⱼ, softening).
    static func newtonianEnergy(_ bodies: [CelestialBody]) -> Double {
        let kinetic = bodies.reduce(0.0) { $0 + 0.5 * $1.mass * $1.velocity.magnitudeSquared }
        var potential = 0.0
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let dist = max((bodies[i].position - bodies[j].position).magnitude, softening)
                potential -= G * bodies[i].mass * bodies[j].mass / dist
            }
        }
        return kinetic + potential
    }

    /// Total angular momentum about the origin: Σ mᵢ (rᵢ × vᵢ).
    static func angularMomentum(_ bodies: [CelestialBody]) -> Vector3D {
        bodies.reduce(Vector3D.zero) { $0 + $1.position.cross($1.velocity) * $1.mass }
    }

    /// Returns copies shifted so the CoM sits at the origin with zero net momentum.
    static func centerOfMassFrame(_ bodies: [CelestialBody]) -> [CelestialBody] {
        let mass = totalMass(bodies)
        guard mass > 0 else { return bodies }
        let com = centerOfMass(bodies)
        let comVelocity = totalMomentum(bodies) * (1.0 / mass)
        return bodies.map { body in
            var shifted = body
            shifted.position = body.position - com
            shifted.velocity = body.velocity - comVelocity
            return shifted
        }
    }
}
