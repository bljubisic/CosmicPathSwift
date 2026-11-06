//
//  HabitableZoneSettings.swift
//  CosmicPathSwift
//
//  Habitable-zone options from the Advanced sheet (issue #20, PR 6): which
//  flux limits define the zone's edges, and the planet's Bond albedo. They
//  only change what is drawn, so they apply immediately, even while running.
//  The defaults reproduce the original zone exactly.
//

import Foundation

/// Stellar-flux limits (in units of Earth's insolation) for the zone's edges.
enum HabitableZoneLimits: String, CaseIterable, Codable, Sendable {
    /// Runaway greenhouse (inner) and maximum greenhouse (outer): Kasting 1993 /
    /// Kopparapu 2013, the original zone.
    case conservative
    /// Recent Venus (inner) and early Mars (outer), Kopparapu 2013: planets
    /// that may once have had liquid water.
    case optimistic

    /// Flux at the inner (hot) edge.
    var innerFlux: Double {
        switch self {
        case .conservative: return HabitableZonePhysics.innerFlux
        case .optimistic: return 1.78
        }
    }

    /// Flux at the outer (cold) edge.
    var outerFlux: Double {
        switch self {
        case .conservative: return HabitableZonePhysics.outerFlux
        case .optimistic: return 0.32
        }
    }

    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .optimistic: return "Optimistic"
        }
    }

    /// Physical meaning of the two edges, for the Advanced sheet caption.
    var edgeDescription: String {
        switch self {
        case .conservative: return "Runaway greenhouse to maximum greenhouse"
        case .optimistic: return "Recent Venus to early Mars"
        }
    }
}

/// Habitable-zone options from the Advanced sheet.
struct HabitableZoneSettings: Equatable, Codable, Sendable {
    var limits: HabitableZoneLimits = .conservative

    /// Fraction of starlight the planet reflects (Earth ≈ 0.3).
    var bondAlbedo: Double = HabitableZonePhysics.bondAlbedo

    /// Range offered by the albedo slider.
    static let albedoRange: ClosedRange<Double> = 0...0.9

    /// Step of the albedo slider.
    static let albedoStep: Double = 0.05
}
