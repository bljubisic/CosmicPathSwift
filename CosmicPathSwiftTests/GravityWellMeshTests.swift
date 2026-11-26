//
//  GravityWellMeshTests.swift
//  CosmicPathSwiftTests
//
//  Projected geometry of the gravity-well sheet (issue #38, PR 3), and the
//  well camera's zoom.
//

import Testing
import CoreGraphics
import Foundation
@testable import CosmicPathSwift

// MARK: - Mesh

struct GravityWellMeshTests {

    private let extent = 150.0

    private func scene(strength: Double = 1, trailPoints: Int = 3) -> GravityWellScene {
        var star = CelestialBody(id: 0, kind: .star, mass: 200, position: .zero, velocity: .zero)
        star.trail = Array(repeating: .zero, count: trailPoints)
        var planet = CelestialBody(id: 1, kind: .planet, mass: 5, position: Vector3D(x: 150, y: 0, z: 0), velocity: .zero)
        planet.trail = (0..<trailPoints).map { Vector3D(x: 150, y: Double($0), z: 0) }
        var config = SimulationConfig()
        config.advanced.display.gridWarpStrength = strength
        return GravityWellScene.make(
            bodies: [star, planet], config: config, metrics: RelativisticMetrics(), centerOfMass: .zero,
            viewExtent: extent, habitableZone: nil, trailLimit: trailPoints
        )
    }

    private func transformer(elevation: Double = WellCamera.defaultElevation) -> CoordinateTransformer {
        CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 600), simulationSeparation: extent,
            azimuth: 0, elevation: elevation
        )
    }

    @Test func gridSpansTheSheetInBothDirections() {
        let mesh = GravityWellMesh.make(scene: scene(), transformer: transformer(), gridLineCount: 10, samplesPerLine: 20)
        #expect(mesh.gridLines.count == 2 * 11)
        #expect(mesh.gridLines.allSatisfy { $0.count == 21 })
    }

    /// At a tilted camera the bottom of a well is drawn lower than the flat sheet there.
    @Test func wellsSinkBelowTheSheet() {
        let t = transformer()
        let mesh = GravityWellMesh.make(scene: scene(), transformer: t)
        let flatStar = t.simulationToCanvas(.zero)
        let flatPlanet = t.simulationToCanvas(Vector3D(x: 150, y: 0, z: 0))
        #expect(mesh.bodyPoints[0].y > flatStar.y + 10)
        #expect(mesh.bodyPoints[1].y > flatPlanet.y)
        // The star's well is deeper than the planet's.
        #expect(mesh.bodyPoints[0].y - flatStar.y > mesh.bodyPoints[1].y - flatPlanet.y)
    }

    @Test func flatSheetLeavesBodiesInPlace() {
        let t = transformer()
        let mesh = GravityWellMesh.make(scene: scene(strength: 0), transformer: t)
        #expect(mesh.bodyPoints[1] == t.simulationToCanvas(Vector3D(x: 150, y: 0, z: 0)))
    }

    @Test func trailsAndContoursFollowTheBodies() {
        let mesh = GravityWellMesh.make(scene: scene(), transformer: transformer())
        #expect(mesh.trails.map(\.count) == [3, 3])
        #expect(Set(mesh.contours.map(\.bodyIndex)) == [0, 1])
        #expect(mesh.contours.allSatisfy { $0.points.count == GravityWellMesh.contourSamples + 1 })
    }

    @Test func renderOrderCoversEveryBody() {
        let mesh = GravityWellMesh.make(scene: scene(), transformer: transformer())
        #expect(mesh.renderOrder.sorted() == [0, 1])
    }

    /// Default grid plus two 800-point trails stays a few thousand points.
    @Test func staysWithinTheVertexBudget() {
        let mesh = GravityWellMesh.make(scene: scene(trailPoints: 800), transformer: transformer())
        #expect(mesh.pointCount < 8000)
    }

    @Test func onlyAFlammFunnelHasAHorizon() {
        #expect(GravityWellMesh.make(scene: scene(), transformer: transformer()).horizon == nil)

        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        let hole = CelestialBody(id: 0, kind: .star, mass: 10, position: .zero, velocity: .zero)
        let probe = CelestialBody(id: 1, kind: .planet, mass: 1e-9, position: Vector3D(x: 160, y: 0, z: 0), velocity: .zero)
        let funnel = GravityWellScene.make(
            bodies: [hole, probe], config: config, metrics: RelativisticMetrics(), centerOfMass: .zero,
            viewExtent: 160, habitableZone: nil, trailLimit: 0
        )
        let mesh = GravityWellMesh.make(scene: funnel, transformer: transformer())
        #expect(mesh.horizon?.count == GravityWellMesh.contourSamples + 1)
        // Only the hole gets contours; the probe is a point mass.
        #expect(Set(mesh.contours.map(\.bodyIndex)) == [0])
    }

    @Test func ringsAreProjectedOntoTheSurface() {
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 5
        let body = CelestialBody(id: 0, kind: .star, mass: 200, position: .zero, velocity: .zero)
        let wells = GravityWellScene.make(
            bodies: [body], config: SimulationConfig(), metrics: metrics, centerOfMass: .zero,
            viewExtent: extent, habitableZone: nil, trailLimit: 0
        )
        let mesh = GravityWellMesh.make(scene: wells, transformer: transformer())
        #expect(mesh.rings.map(\.kind) == [.schwarzschild])
        #expect(mesh.rings[0].points.count == GravityWellMesh.contourSamples + 1)
    }
}

// MARK: - Camera state

@MainActor
struct WellCameraStateTests {

    @Test func pinchZoomsWithinItsRange() {
        let camera = WellCameraState()
        #expect(camera.zoom == 1)
        camera.pinch(scale: 2, from: 1)
        #expect(camera.zoom == 2)
        camera.pinch(scale: 100, from: 2)
        #expect(camera.zoom == WellCamera.zoomRange.upperBound)
        camera.pinch(scale: 0.001, from: 1)
        #expect(camera.zoom == WellCamera.zoomRange.lowerBound)
    }

    @Test func presetsResetTheZoom() {
        let camera = WellCameraState()
        camera.pinch(scale: 2, from: 1)
        camera.elevation = 0.5
        camera.apply(.edgeOn)
        #expect(camera.zoom == 1)
        #expect(camera.elevation == WellCamera.elevation(for: .edgeOn))
    }
}
