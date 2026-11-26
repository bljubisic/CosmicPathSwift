//
//  GravityWellMesh.swift
//  CosmicPathSwift
//
//  Projects a `GravityWellScene` to canvas polylines (issue #38). Every point
//  of the orbital plane is lifted to (x, y, depth) and sent through the same
//  orthographic `CoordinateTransformer` as the orbit view, with the depth on
//  the out-of-plane axis, so the wells sink below the sheet on screen.
//  Pure, so the geometry is tested without a renderer.
//

import CoreGraphics
import Foundation

struct GravityWellMesh {

    /// A ring of constant radius around one body's throat, in its colour.
    struct Contour {
        /// Index into `scene.bodies`.
        let bodyIndex: Int
        let points: [CGPoint]
    }

    /// A `WellRing` drawn on the surface.
    struct Ring {
        let kind: WellRing.Kind
        let points: [CGPoint]
    }

    /// Lines of the sheet in both directions.
    let gridLines: [[CGPoint]]
    let contours: [Contour]
    let rings: [Ring]
    /// Trail of every body, index-aligned with `scene.bodies`.
    let trails: [[CGPoint]]
    /// Each body at the bottom of its well, index-aligned with `scene.bodies`.
    let bodyPoints: [CGPoint]
    /// Indices into `scene.bodies`, far to near, so nearer bodies are drawn on top.
    let renderOrder: [Int]
    /// Outline of the event horizon at the bottom of a Flamm throat; nil otherwise.
    let horizon: [CGPoint]?

    /// Segments of every contour, ring and horizon circle.
    static let contourSamples = 48
    /// Contour radii, in well widths (Newtonian wells).
    static let newtonianContourRadii = [0.5, 1, 2]
    /// Contour radii, in rₛ (Flamm funnel).
    static let flammContourRadii = [2.0, 4, 8]

    /// Total projected points, for the frame budget.
    var pointCount: Int {
        let lines = gridLines + contours.map(\.points) + rings.map(\.points) + trails
        return lines.reduce(0) { $0 + $1.count } + bodyPoints.count + (horizon?.count ?? 0)
    }

    // MARK: Building

    static func make(
        scene: GravityWellScene, transformer: CoordinateTransformer,
        gridLineCount: Int = 30, samplesPerLine: Int = 60
    ) -> GravityWellMesh {
        let surface = scene.surface
        let project = { (point: PlanePoint) -> CGPoint in
            transformer.simulationToCanvas(lift(point, on: surface))
        }
        let bodies = scene.bodies.map { lift($0.position, on: surface) }
        let depths = bodies.map { transformer.depthOf($0) }
        return GravityWellMesh(
            gridLines: grid(halfSize: sheetHalfSize(scene), lines: gridLineCount, samples: samplesPerLine).map { $0.map(project) },
            contours: contours(scene).map { Contour(bodyIndex: $0.index, points: $0.circle.map(project)) },
            rings: scene.rings.map { Ring(kind: $0.kind, points: circle(center: $0.center, radius: $0.radius).map(project)) },
            trails: scene.trails.map { $0.map(project) },
            bodyPoints: bodies.map { transformer.simulationToCanvas($0) },
            renderOrder: scene.bodies.indices.sorted { depths[$0] > depths[$1] },
            horizon: horizon(scene).map { $0.map(project) }
        )
    }

    /// `point` on the sheet: depth on the out-of-plane axis, positive downward on screen.
    static func lift(_ point: PlanePoint, on surface: GravityWellSurface) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: surface.depth(x: point.x, y: point.y))
    }

    // MARK: Pieces

    /// Half the sheet's side: out to the Flamm rim, or `rimFraction` of the view.
    private static func sheetHalfSize(_ scene: GravityWellScene) -> Double {
        if case let .flamm(_, rim) = scene.surface.profile { return rim }
        return GravityWellSurface.rimFraction * scene.viewExtent
    }

    /// `lines + 1` lines across x and as many across y, each with `samples + 1` points.
    private static func grid(halfSize: Double, lines: Int, samples: Int) -> [[PlanePoint]] {
        let count = max(lines, 1)
        let steps = max(samples, 1)
        let offsets = (0...count).map { -halfSize + 2 * halfSize * Double($0) / Double(count) }
        let along = (0...steps).map { -halfSize + 2 * halfSize * Double($0) / Double(steps) }
        let vertical = offsets.map { x in along.map { PlanePoint(x: x, y: $0) } }
        let horizontal = offsets.map { y in along.map { PlanePoint(x: $0, y: y) } }
        return vertical + horizontal
    }

    /// Contours around each body with a well: every weighted body for
    /// Newtonian wells, only the hole for a Flamm funnel.
    private static func contours(_ scene: GravityWellScene) -> [(index: Int, circle: [PlanePoint])] {
        let surface = scene.surface
        switch surface.profile {
        case .newtonian:
            return scene.bodies.indices.filter { surface.weight(of: $0) > 0 }.flatMap { index in
                let width = surface.wellWidth(of: index)
                return newtonianContourRadii.map { (index, circle(center: scene.bodies[index].position, radius: $0 * width)) }
            }
        case let .flamm(rs, rim):
            guard let hole = scene.bodies.first else { return [] }
            return flammContourRadii.map { $0 * rs }.filter { $0 < rim }.map { (0, circle(center: hole.position, radius: $0)) }
        }
    }

    /// The horizon circle at the bottom of the throat (r = rₛ, so at full depth).
    private static func horizon(_ scene: GravityWellScene) -> [PlanePoint]? {
        guard case let .flamm(rs, _) = scene.surface.profile, let hole = scene.bodies.first else { return nil }
        return circle(center: hole.position, radius: rs)
    }

    /// A closed circle of `contourSamples` segments.
    private static func circle(center: PlanePoint, radius: Double) -> [PlanePoint] {
        (0...contourSamples).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(contourSamples)
            return PlanePoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }
}
