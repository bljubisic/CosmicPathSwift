//
//  PhysicsScale.swift
//  CosmicPathSwift
//
//  The user's choice of physics scale (issue #21, PR 2), picked in the
//  Advanced sheet. Visual is the original app; Realistic uses real constants.
//

import Foundation

/// Which `ScaleProfile` the simulation runs in.
enum PhysicsScale: String, CaseIterable, Codable, Sendable {
    /// G = 500, c = 200: GR magnified so it shows at screen size.
    case visual
    /// Real G and c in AU, M☉ and days.
    case realistic

    var displayName: String {
        switch self {
        case .visual: return "Visual"
        case .realistic: return "Realistic"
        }
    }

    /// Constants, units and size rules of this scale.
    var profile: ScaleProfile {
        switch self {
        case .visual: return .visual
        case .realistic: return .realisticPlanetary
        }
    }
}
