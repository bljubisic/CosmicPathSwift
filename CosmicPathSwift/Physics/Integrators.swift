//
//  Integrators.swift
//  CosmicPathSwift
//
//  The selectable integrators (issue #20, PR 5). Each advances every body by
//  one step `dt` under the pairwise force of `NBodyGravity`.
//
//  ## Velocity-Verlet (default)
//
//  The original `NBodyGravity.verletStep`: 2nd-order and symplectic, so the
//  energy error oscillates but stays bounded. One force evaluation per step.
//
//  ## RK4
//
//  Classic 4-stage Runge–Kutta on the state (x, v) with derivative (v, a(x, v)).
//  4th-order, and it evaluates the velocity-dependent GR term at every stage,
//  so it stays 4th-order with GR on. It is not symplectic: the energy error
//  slowly drifts. Stage 1 reuses the stored a(t), and the step ends by storing
//  a(t+dt) for the next step and the acceleration arrows, so it costs 4 force
//  evaluations.
//
//  ## Yoshida 4
//
//  Three Verlet sub-steps of dt·w₁, dt·w₀, dt·w₁ with
//      w₁ = 1 / (2 − 2^⅓),   w₀ = −2^⅓ / (2 − 2^⅓).
//  The middle sub-step goes backwards in time; that is expected. 4th-order
//  and symplectic for Newtonian forces, at 3 force evaluations per step.
//
//  ## GR caveat
//
//  Verlet evaluates a(t+dt) with the old velocity v(t), so with GR on Verlet
//  and Yoshida are only 1st-order in the (small) GR term; their textbook
//  orders hold for the Newtonian part. RK4 has no such limitation.
//

import Foundation

extension IntegratorKind {

    /// Yoshida 4th-order sub-step weights: outer w₁ (first and last) and middle w₀.
    static let yoshidaWeights: (outer: Double, middle: Double) = {
        let cubeRootOfTwo = pow(2.0, 1.0 / 3.0)
        let outer = 1 / (2 - cubeRootOfTwo)
        return (outer, -cubeRootOfTwo * outer)
    }()

    /// Advances all bodies by one step and returns the new state.
    ///
    /// Each body's stored `acceleration` must hold a(t) on entry; on return it
    /// holds a(t+dt). Trails, masses and IDs are carried over unchanged.
    func step(
        _ bodies: [CelestialBody],
        dt: Double,
        softening: Double,
        grEnabled: Bool = true
    ) -> [CelestialBody] {
        switch self {
        case .velocityVerlet:
            return NBodyGravity.verletStep(bodies, dt: dt, softening: softening, grEnabled: grEnabled)
        case .rk4:
            return Self.rk4Step(bodies, dt: dt, softening: softening, grEnabled: grEnabled)
        case .yoshida4:
            return Self.yoshidaStep(bodies, dt: dt, softening: softening, grEnabled: grEnabled)
        }
    }

    // MARK: - Yoshida

    private static func yoshidaStep(
        _ bodies: [CelestialBody], dt: Double, softening: Double, grEnabled: Bool
    ) -> [CelestialBody] {
        let weights = yoshidaWeights
        return [weights.outer, weights.middle, weights.outer].reduce(bodies) { state, weight in
            NBodyGravity.verletStep(state, dt: dt * weight, softening: softening, grEnabled: grEnabled)
        }
    }

    // MARK: - RK4

    /// Time derivative of the state at one RK4 stage: (dx/dt, dv/dt) per body.
    private struct Derivative {
        let velocities: [Vector3D]
        let accelerations: [Vector3D]
    }

    private static func rk4Step(
        _ bodies: [CelestialBody], dt: Double, softening: Double, grEnabled: Bool
    ) -> [CelestialBody] {
        let evaluate = { (stage: [CelestialBody]) in
            Derivative(
                velocities: stage.map(\.velocity),
                accelerations: NBodyGravity.accelerations(of: stage, softening: softening, grEnabled: grEnabled)
            )
        }
        let k1 = Derivative(velocities: bodies.map(\.velocity), accelerations: bodies.map(\.acceleration))
        let k2 = evaluate(advanced(bodies, by: k1, dt: dt / 2))
        let k3 = evaluate(advanced(bodies, by: k2, dt: dt / 2))
        let k4 = evaluate(advanced(bodies, by: k3, dt: dt))

        let combined = Derivative(
            velocities: weightedSum(k1.velocities, k2.velocities, k3.velocities, k4.velocities),
            accelerations: weightedSum(k1.accelerations, k2.accelerations, k3.accelerations, k4.accelerations)
        )
        let final = advanced(bodies, by: combined, dt: dt)
        return NBodyGravity.withAccelerations(final, softening: softening, grEnabled: grEnabled)
    }

    /// Copies of `bodies` moved along `derivative` for time `dt` (x + dt·ẋ, v + dt·v̇).
    private static func advanced(_ bodies: [CelestialBody], by derivative: Derivative, dt: Double) -> [CelestialBody] {
        bodies.indices.map { i in
            var moved = bodies[i]
            moved.position = bodies[i].position + derivative.velocities[i] * dt
            moved.velocity = bodies[i].velocity + derivative.accelerations[i] * dt
            return moved
        }
    }

    /// RK4 weighting (k1 + 2k2 + 2k3 + k4) / 6, per body.
    private static func weightedSum(
        _ k1: [Vector3D], _ k2: [Vector3D], _ k3: [Vector3D], _ k4: [Vector3D]
    ) -> [Vector3D] {
        k1.indices.map { i in
            (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]) * (1.0 / 6.0)
        }
    }
}
