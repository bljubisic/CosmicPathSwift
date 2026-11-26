//
//  GravityWellSceneTests.swift
//  CosmicPathSwiftTests
//
//  Gravity-well view plumbing (issue #38, PR 2): the scene the sheet is drawn
//  from, the view-mode setting and the well camera.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Scene (pure)

struct GravityWellSceneBuilderTests {

    private func bodies() -> [CelestialBody] {
        var star = CelestialBody(id: 0, kind: .star, mass: 200, position: Vector3D(x: 10, y: 0, z: 0), velocity: .zero)
        star.trail = [Vector3D(x: 10, y: 0, z: 0)]
        var planet = CelestialBody(id: 1, kind: .planet, mass: 5, position: Vector3D(x: 160, y: 20, z: 40), velocity: .zero)
        planet.trail = [Vector3D(x: 150, y: 0, z: 30), Vector3D(x: 155, y: 10, z: 35), Vector3D(x: 160, y: 20, z: 40)]
        return [star, planet]
    }

    private func scene(
        config: SimulationConfig = SimulationConfig(), metrics: RelativisticMetrics = RelativisticMetrics(),
        habitableZone: HabitableZone? = nil, trailLimit: Int = 800
    ) -> GravityWellScene {
        GravityWellScene.make(
            bodies: bodies(), config: config, metrics: metrics, centerOfMass: Vector3D(x: 10, y: 0, z: 5),
            viewExtent: 150, habitableZone: habitableZone, trailLimit: trailLimit
        )
    }

    /// Positions are CoM-relative and flattened onto the orbital plane.
    @Test func bodiesAreCentredAndFlattened() {
        let wells = scene()
        #expect(wells.bodies.map(\.position) == [PlanePoint(x: 0, y: 0), PlanePoint(x: 150, y: 20)])
        #expect(wells.bodies.map(\.id) == [0, 1])
        #expect(wells.bodies.map(\.kind) == [.star, .planet])
        #expect(wells.surface.sources == [WellSource(x: 0, y: 0, mass: 200), WellSource(x: 150, y: 20, mass: 5)])
        #expect(wells.viewExtent == 150)
    }

    @Test func trailsAreFlattenedAndLimited() {
        let wells = scene(trailLimit: 2)
        #expect(wells.trails[1] == [PlanePoint(x: 145, y: 10), PlanePoint(x: 150, y: 20)])
        #expect(scene(trailLimit: 0).trails.allSatisfy { $0.isEmpty })
    }

    @Test func gridWarpStrengthSetsTheDepth() {
        var config = SimulationConfig()
        config.advanced.display.gridWarpStrength = 2.5
        #expect(scene(config: config).surface.strength == 2.5)
    }

    /// The absorbed planet leaves the sheet: no body, no well.
    @Test func absorbedPlanetHasNoWell() {
        var metrics = RelativisticMetrics()
        metrics.isAbsorbed = true
        let wells = scene(metrics: metrics)
        #expect(wells.bodies.map(\.id) == [0])
        #expect(wells.surface.sources.count == 1)
    }

    @Test func blackHoleRingsSurroundTheCentralBody() {
        var metrics = RelativisticMetrics()
        metrics.isBlackHole = true
        metrics.schwarzschildRadius = 5
        metrics.photonSphereRadius = 7.5
        metrics.iscoRadius = 15
        let rings = scene(metrics: metrics).rings
        #expect(rings.map(\.kind) == [.schwarzschild, .photonSphere, .isco])
        #expect(rings.map(\.radius) == [5, 7.5, 15])
        #expect(rings.allSatisfy { $0.center == PlanePoint(x: 0, y: 0) })
    }

    @Test func starsShowOnlyTheirSchwarzschildRing() {
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 5
        #expect(scene(metrics: metrics).rings.map(\.kind) == [.schwarzschild])
    }

    @Test func hidingRelativisticRadiiHidesTheirRings() {
        var config = SimulationConfig()
        config.advanced.display.showRelativisticRadii = false
        var metrics = RelativisticMetrics()
        metrics.isBlackHole = true
        metrics.schwarzschildRadius = 5
        #expect(scene(config: config, metrics: metrics).rings.isEmpty)
    }

    @Test func habitableZoneAddsItsEdges() {
        let config = SimulationConfig()
        let zone = HabitableZone.forCentralBody(of: config)
        let rings = scene(habitableZone: zone).rings
        #expect(rings.map(\.kind) == [.habitableInner, .habitableOuter])
        #expect(rings.map(\.radius) == [zone.innerPx, zone.outerPx])
    }

    @Test func threeBodyHasNoRings() {
        var config = SimulationConfig()
        config.mode = .threeBody
        var metrics = RelativisticMetrics()
        metrics.schwarzschildRadius = 5
        #expect(scene(config: config, metrics: metrics).rings.isEmpty)
    }
}

// MARK: - Well camera (pure)

struct WellCameraTests {

    @Test func defaultIsSixtyDegrees() {
        #expect(abs(WellCamera.defaultElevation - 60 * .pi / 180) < 1e-12)
    }

    @Test func elevationIsClampedAboveTheSheet() {
        #expect(WellCamera.clamped(0) == WellCamera.elevationRange.lowerBound)
        #expect(WellCamera.clamped(-1) == WellCamera.elevationRange.lowerBound)
        #expect(WellCamera.clamped(.pi / 2) == WellCamera.elevationRange.upperBound)
        #expect(WellCamera.clamped(1) == 1)
        #expect(abs(WellCamera.elevationRange.lowerBound - 20 * .pi / 180) < 1e-12)
        #expect(abs(WellCamera.elevationRange.upperBound - 80 * .pi / 180) < 1e-12)
    }

    @Test func presetsMapIntoTheRange() {
        #expect(WellCamera.elevation(for: .topDown) == WellCamera.elevationRange.lowerBound)
        #expect(WellCamera.elevation(for: .tilted) == WellCamera.defaultElevation)
        #expect(WellCamera.elevation(for: .edgeOn) == WellCamera.elevationRange.upperBound)
    }
}

// MARK: - View model

@MainActor
struct GravityWellViewModelTests {

    private let canvas = CGSize(width: 400, height: 800)

    /// Holds the engine the factory built, so tests can reach it.
    private final class EngineBox: @unchecked Sendable {
        var engine: MockSimulationEngine?
    }

    private func makeViewModel() -> (SimulationViewModel, EngineBox) {
        let box = EngineBox()
        let vm = SimulationViewModel { setup in
            let engine = MockSimulationEngine(bodies: setup.bodies)
            box.engine = engine
            return engine
        }
        vm.setup(canvasSize: canvas)
        return (vm, box)
    }

    @Test func defaultsToTwoDWithoutAScene() {
        let (vm, _) = makeViewModel()
        #expect(vm.config.advanced.display.viewMode == .twoD)
        #expect(vm.gravityWellScene == nil)
    }

    @Test(arguments: [CanvasViewMode.split, .threeD])
    func wellModesBuildTheSceneAtOnce(mode: CanvasViewMode) {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.viewMode = mode
        #expect(vm.gravityWellScene?.bodies.count == 2)

        vm.config.advanced.display.viewMode = .twoD
        #expect(vm.gravityWellScene == nil)
    }

    /// Switching is render-only: the same engine keeps running from where it was.
    @Test func switchingDoesNotRestartOrPause() throws {
        let (vm, box) = makeViewModel()
        let engine = try #require(box.engine)
        vm.tick()
        vm.start()
        let elapsed = vm.metrics.elapsedTime

        vm.config.advanced.display.viewMode = .threeD

        #expect(box.engine === engine)
        #expect(vm.isRunning)
        #expect(vm.metrics.elapsedTime == elapsed)
        vm.pause()
    }

    @Test func sceneFollowsTheBodies() throws {
        let (vm, box) = makeViewModel()
        vm.config.advanced.display.viewMode = .split
        let before = try #require(vm.gravityWellScene?.bodies.last?.position)
        let engine = try #require(box.engine)
        for _ in 0..<5 { engine.step(dt: 1) }
        vm.tick()
        #expect(vm.gravityWellScene?.bodies.last?.position != before)
    }

    @Test func wellCameraStartsAtItsDefault() {
        let (vm, _) = makeViewModel()
        #expect(vm.wellCameraElevation == WellCamera.defaultElevation)
    }

    /// Azimuth is shared with the orbit view; elevation is the sheet's own, clamped.
    @Test func rotatingTheWellCameraSharesOnlyTheAzimuth() {
        let (vm, _) = makeViewModel()
        let orbitElevation = vm.cameraElevation
        vm.rotateWellCamera(deltaAzimuth: 0.4, deltaElevation: 5)
        #expect(vm.cameraAzimuth == 0.4)
        #expect(vm.cameraElevation == orbitElevation)
        #expect(vm.wellCameraElevation == WellCamera.elevationRange.upperBound)
    }

    @Test(arguments: CameraPreset.allCases)
    func presetsAlsoTurnTheWellCamera(preset: CameraPreset) {
        let (vm, _) = makeViewModel()
        vm.rotateWellCamera(deltaAzimuth: 1, deltaElevation: -0.3)
        vm.applyCameraPreset(preset)
        #expect(vm.wellCameraElevation == WellCamera.elevation(for: preset))
    }

    /// Opening a scenario (deep link) keeps the view the user chose.
    @Test func openingAScenarioKeepsTheViewMode() {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.viewMode = .threeD
        vm.run(SimulationConfig(), canvasSize: canvas)
        #expect(vm.config.advanced.display.viewMode == .threeD)
        #expect(vm.gravityWellScene != nil)
        vm.pause()
    }

    @Test func resetRestoresTheWellCamera() {
        let (vm, _) = makeViewModel()
        vm.rotateWellCamera(deltaAzimuth: 0, deltaElevation: -0.5)
        vm.reset(canvasSize: canvas)
        #expect(vm.wellCameraElevation == WellCamera.defaultElevation)
    }
}
