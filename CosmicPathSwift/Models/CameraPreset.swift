//
//  CameraPreset.swift
//  CosmicPathSwift
//
//  Fixed camera orientations offered in the Advanced sheet (issue #20).
//  Angles follow `CoordinateTransformer`: elevation 0 looks straight down on
//  the x-y plane, π/2 looks along it (edge-on).
//

import Foundation

/// A named camera orientation. Applying one replaces the current drag rotation.
enum CameraPreset: String, CaseIterable, Equatable, Sendable {
    case topDown
    case tilted
    case edgeOn

    var displayName: String {
        switch self {
        case .topDown: return "Top"
        case .tilted: return "Tilted"
        case .edgeOn: return "Edge-on"
        }
    }

    /// Rotation around the z-axis, in radians.
    var azimuth: Double { 0 }

    /// Tilt above the orbital plane, in radians.
    var elevation: Double {
        switch self {
        case .topDown: return 0
        case .tilted: return .pi / 6   // the app's default view
        case .edgeOn: return .pi / 2
        }
    }
}
