//
//  CanvasViewMode.swift
//  CosmicPathSwift
//
//  How the simulation is drawn (issue #38). Render-only: switching never
//  restarts or pauses the simulation.
//

import Foundation

/// The canvas's view: today's flat orbit view, the gravity-well sheet, or both.
enum CanvasViewMode: String, CaseIterable, Equatable, Codable, Sendable {
    /// The orbit view (today's canvas).
    case twoD
    /// The orbit view on top and the gravity-well sheet below, from the same frame.
    case split
    /// The gravity-well sheet fills the canvas.
    case threeD

    var displayName: String {
        switch self {
        case .twoD: return "2D"
        case .split: return "Split"
        case .threeD: return "3D"
        }
    }

    /// SF Symbol for the mode's button.
    var systemImage: String {
        switch self {
        case .twoD: return "circle.dashed"
        case .split: return "rectangle.split.1x2"
        case .threeD: return "cone"
        }
    }

    /// True when the gravity-well sheet is on screen.
    var showsWells: Bool { self != .twoD }

    /// The next mode, for the floating button that cycles through them.
    var next: CanvasViewMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
