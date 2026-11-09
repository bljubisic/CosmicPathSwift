//
//  StrongFieldScenario.swift
//  CosmicPathSwift
//
//  What orbits the black hole in the Realistic strong-field setup
//  (Realistic + 2-body + Black Hole Mode; issue #21, PRs 3–5).
//

import Foundation

/// Which system the Realistic strong-field setup (Realistic + 2-body + Black Hole Mode) shows.
enum StrongFieldScenario: String, CaseIterable, Codable, Sendable {
    /// A point-mass probe a few rₛ from a stellar black hole: strong-field GR.
    case stellarBlackHole
    /// A rocky planet around a stellar black hole, thousands of rₛ out: tides.
    case blackHolePlanet
    /// The star S2 on its observed orbit around Sagittarius A*.
    case sagittariusAStar

    var displayName: String {
        switch self {
        case .stellarBlackHole: return "Probe"
        case .blackHolePlanet: return "Planet"
        case .sagittariusAStar: return "S2 · Sgr A*"
        }
    }
}
