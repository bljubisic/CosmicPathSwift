//
//  ZoomController.swift
//  CosmicPathSwift
//
//  Dynamic zoom for `SimulationViewModel`: tracks the farthest body from the
//  centre of mass each frame and grows or shrinks the viewed extent so the
//  whole system always fits on screen.
//
//  Zooms out instantly when a body passes the current extent and zooms back in
//  gradually by exponential decay after brief excursions. An ejected body is
//  not tracked (neither for the CoM nor the extent), so the camera stays on the
//  remaining bound system instead of zooming out forever.
//

import Foundation

struct ZoomController: Equatable {

    /// Headroom around the farthest body, so none sits at the canvas edge.
    static let headroom: Double = 1.15

    /// Per-frame zoom-in factor while the orbit is active. 0.999/frame ≈ 6%
    /// oscillation for a 2-second eccentric orbit; the slow recovery (~13 s to
    /// halve) keeps the view stable rather than "bouncing" between perihelion
    /// and aphelion.
    static let activeDecayRate: Double = 0.999

    /// Per-frame zoom-in factor after absorption or ejection: recovers in
    /// < 0.5 s once the body is gone, so the canvas snaps back.
    static let bodyLeftDecayRate: Double = 0.96

    /// Viewed extent: the largest distance from the CoM that fits on screen.
    private(set) var maxExtent: Double = 0

    /// Smallest extent the zoom may shrink to: the initial extent × orbit margin.
    private(set) var minimumExtent: Double = 0

    /// Instantaneous centre of mass of the tracked bodies, in simulation space.
    /// Used as the transformer's `centerOffset`, so the view stays centred even
    /// when the CoM slowly drifts from the origin over many orbits.
    private(set) var centerOfMass: Vector3D = .zero

    /// Starts a new run: centres on the bodies' CoM and sets the extent to the
    /// farthest body × `CelestialConstants.orbitMarginFactor`.
    ///
    /// - Parameter fallbackExtent: Extent used if there are no bodies.
    /// - Returns: The initial extent (farthest body from the CoM).
    mutating func reset(for bodies: [CelestialBody], fallbackExtent: Double) -> Double {
        centerOfMass = NBodyGravity.centerOfMass(bodies)
        let initialExtent = bodies.map { ($0.position - centerOfMass).magnitude }.max() ?? fallbackExtent
        minimumExtent = initialExtent * CelestialConstants.orbitMarginFactor
        maxExtent = minimumExtent
        return initialExtent
    }

    /// Re-centres on the CoM and adjusts the extent so every tracked body fits.
    ///
    /// - Parameters:
    ///   - ejectedID: ID of an ejected body to ignore (unless it's the only one).
    ///   - bodyLeft: True after absorption or ejection; zooms back in faster.
    ///   - lockZoom: Keeps the current extent (the view still follows the CoM).
    /// - Returns: True if the extent or the CoM changed, so the transformer must be rebuilt.
    mutating func update(bodies: [CelestialBody], ejectedID: Int?, bodyLeft: Bool, lockZoom: Bool) -> Bool {
        let tracked = bodies.filter { $0.id != ejectedID || bodies.count == 1 }

        // Measuring extents from the instantaneous CoM rather than the fixed origin
        // prevents the zoom from ratcheting outward as the CoM slowly drifts.
        let previousCOM = centerOfMass
        centerOfMass = NBodyGravity.centerOfMass(tracked)
        let currentMax = tracked.map { ($0.position - centerOfMass).magnitude }.max() ?? 0

        let targetExtent = max(currentMax * Self.headroom, minimumExtent)
        let previousExtent = maxExtent

        if lockZoom {
            // Keep the current extent.
        } else if targetExtent > maxExtent {
            // Zoom out immediately so bodies are never clipped off-screen.
            maxExtent = targetExtent
        } else {
            let decayRate = bodyLeft ? Self.bodyLeftDecayRate : Self.activeDecayRate
            maxExtent = max(targetExtent, maxExtent * decayRate)
        }

        return maxExtent != previousExtent || centerOfMass != previousCOM
    }
}
