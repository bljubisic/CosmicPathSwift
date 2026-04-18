//
//  CoordinateTransformer.swift
//  CosmicPathSwift
//
//  Converts simulation-space coordinates (origin at center)
//  to canvas-space coordinates (origin at top-left).
//

import Foundation

struct CoordinateTransformer {
    let canvasCenter: CGPoint
    let scale: Double

    /// Creates a transformer that maps simulation coordinates to canvas coordinates.
    /// The scale ensures the initial separation fits within the canvas. Since the star
    /// sits at center and the planet extends to one side, we fit the separation into
    /// 40% of the canvas width (leaving margin from center to edge).
    init(canvasSize: CGSize, simulationSeparation: Double = CelestialConstants.baseAU) {
        self.canvasCenter = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )
        // The planet starts at (separation, 0) from center.
        // It must fit within ~40% of width from center (leaving 10% padding to edge).
        // Also consider height for when orbit goes above/below.
        let availableHalfWidth = canvasSize.width * 0.40
        let availableHalfHeight = canvasSize.height * 0.40
        let available = min(availableHalfWidth, availableHalfHeight)
        if simulationSeparation > 0 {
            self.scale = available / simulationSeparation
        } else {
            self.scale = 1.0
        }
    }

    /// Converts a simulation-space position (origin at center) to a canvas-space point
    /// (origin at top-left). The simulation origin maps to the canvas center, and
    /// positions are scaled by the auto-zoom factor.
    func simulationToCanvas(_ v: Vector2D) -> CGPoint {
        CGPoint(
            x: canvasCenter.x + v.x * scale,
            y: canvasCenter.y + v.y * scale
        )
    }

    /// Batch-converts an array of simulation-space trail positions to canvas-space points.
    func transformTrail(_ trail: [Vector2D]) -> [CGPoint] {
        trail.map { simulationToCanvas($0) }
    }
}
