//
//  WellCamera.swift
//  CosmicPathSwift
//
//  Elevation rules for the gravity-well sheet's camera (issue #38). The sheet
//  shares the orbit view's azimuth but has its own elevation, since Split
//  shows both at once. Angles follow `CoordinateTransformer`: 0 looks straight
//  down, π/2 is edge-on.
//

import Foundation

enum WellCamera {
    /// A low camera, like the reel the view is modelled on.
    static let defaultElevation = 65 * Double.pi / 180

    /// Never top-down (the wells would vanish) and never level with or under the sheet.
    static let elevationRange: ClosedRange<Double> = (20 * Double.pi / 180)...(80 * Double.pi / 180)

    /// `elevation` kept inside `elevationRange`.
    static func clamped(_ elevation: Double) -> Double {
        min(max(elevation, elevationRange.lowerBound), elevationRange.upperBound)
    }

    /// The sheet's elevation for an Advanced-sheet camera preset.
    static func elevation(for preset: CameraPreset) -> Double {
        switch preset {
        case .topDown: return elevationRange.lowerBound
        case .tilted: return defaultElevation
        case .edgeOn: return elevationRange.upperBound
        }
    }
}
