//
//  InitialConditionSettings.swift
//  CosmicPathSwift
//
//  Starting-condition options from the Advanced sheet (issue #20, PR 4):
//  orbit shape for the 2-body planet, the 3-body chaos experiment, and the
//  Custom preset's random layout.
//
//  These change how a run starts, so editing them restarts the setup while
//  paused (like the basic parameter sliders). The defaults reproduce the
//  standard starting conditions exactly.
//

import Foundation

/// Layout of the 3-body Custom preset.
enum CustomLayout: String, CaseIterable, Equatable, Codable, Sendable {
    /// Lagrange equilateral triangle (the original Custom preset).
    case triangle
    /// Seeded random positions and velocities, always bound.
    case random

    var displayName: String {
        switch self {
        case .triangle: return "Triangle"
        case .random: return "Random"
        }
    }
}

/// Starting-condition options from the Advanced sheet.
struct InitialConditionSettings: Equatable, Codable, Sendable {
    /// 2-body orbit eccentricity. The Distance slider is the semi-major axis a,
    /// and the planet starts at periapsis a(1 − e). 0 is today's circular orbit.
    var eccentricity: Double = 0

    /// Direction of periapsis within the orbital plane, in degrees from the x-axis.
    var periapsisAngleDeg: Double = 0

    /// 3-body chaos nudge: body A moves by ε × the preset's length unit. 0 = off.
    var chaosEpsilon: Double = 0

    /// Run an unperturbed copy of the 3-body system alongside, drawn as a ghost.
    /// Only has an effect when `chaosEpsilon > 0`.
    var showUnperturbedTwin: Bool = false

    /// Layout of the Custom preset.
    var customLayout: CustomLayout = .triangle

    /// Seed of the Custom preset's random layout.
    var customSeed: UInt64 = 1

    // MARK: - Ranges & Choices

    /// Eccentricity slider range. Above 0.9 the planet starts almost on the star.
    static let eccentricityRange: ClosedRange<Double> = 0...0.9

    /// Periapsis angle slider range, in degrees.
    static let periapsisAngleRange: ClosedRange<Double> = 0...360

    /// Values offered by the chaos ε picker (0 = off).
    static let chaosEpsilonChoices: [Double] = [0, 1e-8, 1e-6, 1e-4, 1e-2]

    /// Largest seed the seed field accepts, so it stays a readable number.
    static let maxSeed: UInt64 = 999_999

    /// Periapsis angle in radians.
    var periapsisAngleRad: Double { periapsisAngleDeg * .pi / 180 }

    /// True when the chaos twin should run.
    var isTwinActive: Bool { showUnperturbedTwin && chaosEpsilon > 0 }
}
