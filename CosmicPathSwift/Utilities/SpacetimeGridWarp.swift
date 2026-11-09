//
//  SpacetimeGridWarp.swift
//  CosmicPathSwift
//
//  How the background spacetime grid is bent (purely visual).
//
//  Two rules:
//  - `pull`: every grid vertex moves a fixed number of points toward each
//    source. Visual, planetary Realistic and 3-body use it, as before.
//  - `curvature`: Realistic black holes (the strong-field scenarios). The
//    bending follows the Schwarzschild geometry, so it is set by rₛ on screen
//    instead of a fixed pull: deep near the hole, faint far from it.
//

import CoreGraphics
import Foundation

// MARK: - SpacetimeGridWarp

/// Maps grid vertices (canvas points) to their warped positions.
enum SpacetimeGridWarp {
    /// Fixed pull of `strength` points toward each center.
    case pull([PullSource])
    /// Schwarzschild curvature around one black hole.
    case curvature(SchwarzschildGridWarp)

    /// One point the grid is pulled toward.
    struct PullSource {
        let center: CGPoint
        /// Distance in points every vertex moves toward `center`.
        let strength: CGFloat
    }

    /// Where `point` is drawn.
    func warped(_ point: CGPoint) -> CGPoint {
        switch self {
        case .pull(let sources):
            return Self.pulled(point, toward: sources)
        case .curvature(let warp):
            return warp.warped(point)
        }
    }

    /// How far beyond each canvas edge the grid must be drawn so the warp
    /// doesn't pull its outer edge into view. 0 for `pull` (unchanged look).
    func padding(canvasSize: CGSize) -> CGFloat {
        switch self {
        case .pull:
            return 0
        case .curvature(let warp):
            return warp.padding(canvasSize: canvasSize)
        }
    }

    /// Moves `point` by each source's strength toward its center (the original rule).
    private static func pulled(_ point: CGPoint, toward sources: [PullSource]) -> CGPoint {
        var displaced = point
        for source in sources {
            let dx = source.center.x - point.x
            let dy = source.center.y - point.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let warp = source.strength / dist
            displaced.x += dx * warp
            displaced.y += dy * warp
        }
        return displaced
    }
}

// MARK: - SchwarzschildGridWarp

/// Grid warp from the shape of Schwarzschild space.
///
/// The equatorial plane of a Schwarzschild black hole, embedded in flat
/// space, is Flamm's paraboloid z = 2√(rₛ(r − rₛ)), whose slope is
/// √(rₛ/(r − rₛ)) ≈ √(rₛ/r) far out. Seen from above, the grid is pulled in
/// by that slope: a vertex at distance r is drawn at
///
///     r' = r · (1 − √(rₛ/r))^s,   r > rₛ   (r' = 0 inside the horizon)
///
/// with s the Grid Warp setting. At s = 1 this is r − √(rₛ·r), so the grid's
/// local squeeze is about √(rₛ/r): it collapses at the horizon, is strong
/// within a few rₛ, and fades slowly far away. r' grows with r for every
/// s ≥ 0, so grid lines never fold over.
struct SchwarzschildGridWarp {
    /// The black hole's position on the canvas.
    let center: CGPoint
    /// rₛ in canvas points.
    let schwarzschildRadius: CGFloat
    /// Grid Warp setting: 0 flat, 1 the geometric slope, more exaggerates it.
    let strength: CGFloat

    /// Bisection steps when finding the padding (precision ≈ 2⁻³⁰ of the range).
    private static let paddingSearchSteps = 30
    /// The grid never extends more than this many canvas diagonals past an edge.
    private static let maximumPaddingFactor: CGFloat = 1

    /// Where `point` is drawn: moved toward `center` to distance r'.
    func warped(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0 else { return point }
        let factor = warpedDistance(distance) / distance
        return CGPoint(x: center.x + dx * factor, y: center.y + dy * factor)
    }

    /// r' for a vertex at distance `distance` from the hole.
    func warpedDistance(_ distance: CGFloat) -> CGFloat {
        guard strength > 0, schwarzschildRadius > 0 else { return distance }
        guard distance > schwarzschildRadius else { return 0 }
        return distance * pow(1 - sqrt(schwarzschildRadius / distance), strength)
    }

    /// Extra grid beyond each edge: the smallest margin whose warped edge
    /// still reaches the farthest canvas corner from the hole, capped at one
    /// canvas diagonal.
    func padding(canvasSize: CGSize) -> CGFloat {
        let corners = [
            CGPoint.zero, CGPoint(x: canvasSize.width, y: 0),
            CGPoint(x: 0, y: canvasSize.height), CGPoint(x: canvasSize.width, y: canvasSize.height)
        ]
        let farthest = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
        let maximum = hypot(canvasSize.width, canvasSize.height) * Self.maximumPaddingFactor
        guard farthest > 0, warpedDistance(farthest) < farthest else { return 0 }
        guard warpedDistance(farthest + maximum) >= farthest else { return maximum }

        var low: CGFloat = 0
        var high = maximum
        for _ in 0..<Self.paddingSearchSteps {
            let middle = (low + high) / 2
            if warpedDistance(farthest + middle) >= farthest { high = middle } else { low = middle }
        }
        return high
    }
}
