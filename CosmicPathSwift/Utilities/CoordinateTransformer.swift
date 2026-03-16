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

    init(canvasSize: CGSize) {
        self.canvasCenter = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )
    }

    func simulationToCanvas(_ v: Vector2D) -> CGPoint {
        CGPoint(
            x: canvasCenter.x + v.x,
            y: canvasCenter.y + v.y
        )
    }

    func transformTrail(_ trail: [Vector2D]) -> [CGPoint] {
        trail.map { simulationToCanvas($0) }
    }
}
