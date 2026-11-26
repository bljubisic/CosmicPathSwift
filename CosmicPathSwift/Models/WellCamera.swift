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
import Observation

enum WellCamera {
    /// A low camera, like the reel the view is modelled on, but high enough that
    /// the sheet doesn't flatten into a band.
    static let defaultElevation = 60 * Double.pi / 180

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

extension WellCamera {
    /// Pinch zoom of the sheet: > 1 zooms in, < 1 shows more of it.
    static let zoomRange: ClosedRange<Double> = 0.5...3
}

// MARK: - WellCameraState

/// The sheet's own camera: its elevation and pinch zoom. Owned by the view
/// model so it survives the layout switches between running and paused.
@Observable
@MainActor
final class WellCameraState {
    var elevation = WellCamera.defaultElevation
    private(set) var zoom: Double = 1

    /// Sets the zoom to `base × scale` (a pinch that started at `base`), within `zoomRange`.
    func pinch(scale: Double, from base: Double) {
        let range = WellCamera.zoomRange
        zoom = min(max(base * scale, range.lowerBound), range.upperBound)
    }

    /// The elevation for `preset`, at zoom 1.
    func apply(_ preset: CameraPreset) {
        elevation = WellCamera.elevation(for: preset)
        zoom = 1
    }
}
