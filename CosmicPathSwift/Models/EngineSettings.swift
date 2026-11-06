//
//  EngineSettings.swift
//  CosmicPathSwift
//
//  Physics-model options from the Advanced sheet (issue #20, PR 5): which
//  integrator runs, the softening length, and what happens when 3-body
//  bodies touch. They are passed to the engine when it is created, so
//  changing any of them restarts the simulation. The defaults reproduce
//  the original engine exactly.
//

import Foundation

/// Numerical integrator used for every step.
enum IntegratorKind: String, CaseIterable, Codable, Sendable {
    /// 2nd-order, symplectic, one force evaluation per step (the original).
    case velocityVerlet
    /// Classic 4th-order Runge–Kutta: accurate but not symplectic.
    case rk4
    /// Yoshida 4th-order symplectic: three Verlet sub-steps.
    case yoshida4

    var displayName: String {
        switch self {
        case .velocityVerlet: return "Verlet"
        case .rk4: return "RK4"
        case .yoshida4: return "Yoshida 4"
        }
    }

    /// Force evaluations (O(N²) pair sums) per step, the integrator's CPU cost.
    var forceEvaluationsPerStep: Int {
        switch self {
        case .velocityVerlet: return 1
        case .yoshida4: return 3
        case .rk4: return 4
        }
    }
}

/// What happens when two bodies come within the merge distance (3-body only).
enum CollisionMode: String, CaseIterable, Codable, Sendable {
    /// Perfectly inelastic merge, conserving mass and momentum (the original).
    case merge
    /// Bodies fly through each other; the softening keeps the force finite.
    case passThrough

    var displayName: String {
        switch self {
        case .merge: return "Merge"
        case .passThrough: return "Pass Through"
        }
    }
}

/// Physics options from the Advanced sheet.
struct EngineSettings: Equatable, Codable, Sendable {
    var integrator: IntegratorKind = .velocityVerlet

    /// Smallest distance used in the force law, in simulation pixels. Also sets
    /// the 3-body merge distance, the star surface, and the closest start.
    var softening: Double = GravitySimulationEngine.softening

    var collisionMode: CollisionMode = .merge

    /// Values offered by the Softening picker; 2 px is the lower limit.
    static let softeningChoices: [Double] = [2, 5, 10, 20]

    /// Safety floor applied by the engine, so the force can never divide by zero.
    static let minimumSoftening: Double = 0.5

    /// Softening actually used: `softening`, never below `minimumSoftening`.
    var effectiveSoftening: Double {
        max(softening, Self.minimumSoftening)
    }
}
