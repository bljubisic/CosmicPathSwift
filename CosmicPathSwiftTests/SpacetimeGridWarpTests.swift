//
//  SpacetimeGridWarpTests.swift
//  CosmicPathSwiftTests
//
//  The background grid's warp: the original fixed pull, and the
//  Schwarzschild curvature warp used around Realistic black holes.
//

import Testing
import CoreGraphics
import Foundation
@testable import CosmicPathSwift

// MARK: - Pull (original rule)

struct GridPullWarpTests {

    /// Every vertex farther than 1 pt moves exactly `strength` toward the source.
    @Test func movesEveryVertexByTheStrength() {
        let warp = SpacetimeGridWarp.pull([.init(center: .zero, strength: 8)])
        let moved = warp.warped(CGPoint(x: 100, y: 0))
        #expect(abs(moved.x - 92) < 1e-9)
        #expect(moved.y == 0)
        #expect(warp.padding(canvasSize: CGSize(width: 400, height: 800)) == 0)
    }
}

// MARK: - Schwarzschild curvature

struct SchwarzschildGridWarpTests {

    private func warp(rs: CGFloat, strength: CGFloat = 1, center: CGPoint = .zero) -> SchwarzschildGridWarp {
        SchwarzschildGridWarp(center: center, schwarzschildRadius: rs, strength: strength)
    }

    /// At ×1, r' = r − √(rₛ r).
    @Test func followsTheFlammSlope() {
        let w = warp(rs: 10)
        #expect(abs(w.warpedDistance(40) - 20) < 1e-9)
        #expect(abs(w.warpedDistance(1000) - 900) < 1e-9)
    }

    @Test func collapsesInsideTheHorizon() {
        let w = warp(rs: 10)
        #expect(w.warpedDistance(10) == 0)
        #expect(w.warpedDistance(5) == 0)
        #expect(w.warped(CGPoint(x: 3, y: 4)) == .zero)
    }

    @Test func zeroStrengthIsFlat() {
        let w = warp(rs: 10, strength: 0)
        #expect(w.warpedDistance(15) == 15)
        #expect(w.padding(canvasSize: CGSize(width: 400, height: 800)) == 0)
    }

    /// The squeeze is strong near the hole and fades far away.
    @Test func squeezeFadesWithDistance() {
        let w = warp(rs: 10)
        let near = w.warpedDistance(30) / 30
        let far = w.warpedDistance(3000) / 3000
        #expect(near < 0.5)
        #expect(far > 0.9)
    }

    /// r' grows with r at every strength, so grid lines never fold over.
    @Test(arguments: [0.25, 1.0, 3.0])
    func neverFolds(strength: Double) {
        let w = warp(rs: 10, strength: CGFloat(strength))
        let radii = stride(from: 10.0, through: 2000, by: 0.5).map { CGFloat($0) }
        let warped = radii.map(w.warpedDistance)
        #expect(zip(warped, warped.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func movesVerticesTowardTheHole() {
        let w = warp(rs: 10, center: CGPoint(x: 100, y: 100))
        let moved = w.warped(CGPoint(x: 140, y: 100))
        #expect(abs(moved.x - 120) < 1e-9)
        #expect(abs(moved.y - 100) < 1e-9)
    }

    /// With the padding, the warped grid edge still reaches every canvas corner.
    @Test(arguments: [1.0, 3.0])
    func paddingKeepsTheCanvasCovered(strength: Double) {
        let size = CGSize(width: 400, height: 800)
        let w = warp(rs: 15, strength: CGFloat(strength), center: CGPoint(x: 200, y: 300))
        let padding = w.padding(canvasSize: size)
        #expect(padding > 0)
        let farthest = hypot(CGFloat(200), CGFloat(500))
        #expect(w.warpedDistance(farthest + padding) >= farthest - 1e-6)
        #expect(padding <= hypot(size.width, size.height))
    }

    /// S2 scale (rₛ ≈ 0.01 pt): the grid barely moves, as in reality.
    @Test func s2ScaleIsNearlyFlat() {
        let w = warp(rs: 0.01)
        #expect(200 - w.warpedDistance(200) < 2)
    }
}
