//
//  DisplayControlsTests.swift
//  CosmicPathSwiftTests
//
//  Display controls (issue #20, PR 3): trail length, camera presets, lock zoom,
//  and velocity / acceleration vectors.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Settings

struct DisplaySettingsTests {

    /// Defaults must reproduce the app before PR 3: 800-point trails, normal warp,
    /// auto-zoom, no vectors.
    @Test func defaultsMatchPreviousBehaviour() {
        let display = DisplaySettings()
        #expect(display.trailPointLimit == 800)
        #expect(display.gridWarpStrength == 1)
        #expect(!display.lockZoom)
        #expect(!display.showVelocityVectors)
        #expect(!display.showAccelerationVectors)
        #expect(DisplaySettings.trailLengthChoices.contains(display.trailLengthMultiplier))
    }

    /// The engine must keep enough history for the longest trail choice.
    @Test func engineBufferHoldsLongestTrail() {
        let longest = DisplaySettings(trailLengthMultiplier: DisplaySettings.trailLengthChoices.max() ?? 1)
        #expect(CelestialBody.trailBufferLength >= longest.trailPointLimit)
    }

    @Test func trailOffGivesNoPoints() {
        #expect(DisplaySettings(trailLengthMultiplier: 0).trailPointLimit == 0)
    }

    @Test func engineTrailsAreCappedAtBuffer() {
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: SimulationConfig()))
        for _ in 0..<(CelestialBody.trailBufferLength + 50) {
            engine.step(dt: SimulationConfig().timeStep)
        }
        #expect(engine.bodies[1].trail.count == CelestialBody.trailBufferLength)
    }
}

// MARK: - Vector overlay (pure)

struct VectorOverlayTests {

    /// Top-down camera at scale 1 centred on the origin, so canvas = (200 + x, 150 + y).
    private let transformer = CoordinateTransformer(
        canvasSize: CGSize(width: 400, height: 300),
        simulationSeparation: 120,   // 0.4 × 300 / 120 = scale 1
        azimuth: 0,
        elevation: 0
    )

    @Test func dynamicalTime() {
        // √(R³ / GM) with R = 10, G = 500, M = 2 → √(1000 / 1000) = 1.
        #expect(abs(VectorOverlay.dynamicalTime(extent: 10, totalMass: 2) - 1) < 1e-12)
        #expect(VectorOverlay.dynamicalTime(extent: 0, totalMass: 2) == 0)
        #expect(VectorOverlay.dynamicalTime(extent: 10, totalMass: 0) == 0)
    }

    /// For a circular orbit, v·t_dyn = r and a·t_dyn² = r, so both arrows are 0.3 r long.
    @Test func circularOrbitArrowsAreThreeTenthsOfRadius() {
        let radius = 150.0
        let mass = 200.0
        let gm = GravitySimulationEngine.G * mass
        let speed = sqrt(gm / radius)
        let time = VectorOverlay.dynamicalTime(extent: radius, totalMass: mass)

        let velocity = VectorOverlay.displacement(
            Vector3D(x: 0, y: speed, z: 0), kind: .velocity, dynamicalTime: time, maxLength: .infinity
        )
        let acceleration = VectorOverlay.displacement(
            Vector3D(x: -gm / (radius * radius), y: 0, z: 0), kind: .acceleration, dynamicalTime: time, maxLength: .infinity
        )
        #expect(abs(velocity.magnitude - VectorOverlay.lengthFraction * radius) < 1e-9)
        #expect(abs(acceleration.magnitude - VectorOverlay.lengthFraction * radius) < 1e-9)
    }

    @Test func longVectorsAreClampedKeepingDirection() {
        let clamped = VectorOverlay.displacement(
            Vector3D(x: 3, y: 4, z: 0), kind: .velocity, dynamicalTime: 100, maxLength: 10
        )
        #expect(abs(clamped.magnitude - 10) < 1e-9)
        #expect(abs(clamped.x - 6) < 1e-9)
        #expect(abs(clamped.y - 8) < 1e-9)
    }

    @Test func arrowIsProjectedFromBodyPosition() {
        let body = CelestialBody(
            mass: 1, position: Vector3D(x: 10, y: 0, z: 0), velocity: Vector3D(x: 0, y: 5, z: 0)
        )
        // t = 1 → displacement = 0.3 × 5 = 1.5 along y.
        let arrows = VectorOverlay.arrows(
            for: [body], kind: .velocity, dynamicalTime: 1, maxLength: .infinity, transformer: transformer
        )
        #expect(arrows.count == 1)
        #expect(arrows[0].tail == CGPoint(x: 210, y: 150))
        #expect(abs(arrows[0].head.x - 210) < 1e-9)
        #expect(abs(arrows[0].head.y - 151.5) < 1e-9)
    }

    @Test func zeroVectorGivesDegenerateArrow() {
        let body = CelestialBody(mass: 1, position: .zero, velocity: .zero)
        let arrows = VectorOverlay.arrows(
            for: [body], kind: .acceleration, dynamicalTime: 1, maxLength: .infinity, transformer: transformer
        )
        #expect(arrows[0].tail == arrows[0].head)
    }
}

// MARK: - ViewModel (mock engine)

@MainActor
struct DisplayControlsViewModelTests {

    private let canvas = CGSize(width: 400, height: 300)
    private static let prefilledTrailLength = 3000

    /// Holds the mock the factory created so the test can inspect and move it.
    private final class EngineBox: @unchecked Sendable {
        var engine: MockSimulationEngine?
    }

    /// A paused 2-body view model whose mock bodies already have long trails.
    private func makeViewModel() -> (SimulationViewModel, EngineBox) {
        let box = EngineBox()
        let vm = SimulationViewModel { bodies in
            let withTrails = bodies.map { body in
                var copy = body
                copy.trail = Array(repeating: body.position, count: Self.prefilledTrailLength)
                return copy
            }
            let engine = MockSimulationEngine(bodies: withTrails)
            box.engine = engine
            return engine
        }
        vm.setup(canvasSize: canvas)
        return (vm, box)
    }

    // MARK: Trail length

    @Test func defaultTrailLengthShowsEightHundredPoints() {
        let (vm, _) = makeViewModel()
        #expect(vm.bodyTrails.allSatisfy { $0.count == 800 })
    }

    /// Changing the setting re-projects at once, so it works while paused.
    @Test func trailLengthAppliesImmediately() {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.trailLengthMultiplier = 0.25
        #expect(vm.bodyTrails.allSatisfy { $0.count == 200 })

        vm.config.advanced.display.trailLengthMultiplier = 0
        #expect(vm.bodyTrails.allSatisfy { $0.isEmpty })
    }

    @Test func trailLengthIsLimitedByRecordedHistory() {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.trailLengthMultiplier = 4   // 3200 > 3000 recorded
        #expect(vm.bodyTrails.allSatisfy { $0.count == Self.prefilledTrailLength })
    }

    // MARK: Lock zoom

    @Test func lockedZoomKeepsScaleFixed() throws {
        let (vm, box) = makeViewModel()
        vm.config.advanced.display.lockZoom = true
        let scale = vm.coordinateScale

        let engine = try #require(box.engine)
        engine.bodies[1].position = engine.bodies[1].position * 10
        vm.tick()

        #expect(vm.coordinateScale == scale)
    }

    @Test func unlockedZoomFollowsBodies() throws {
        let (vm, box) = makeViewModel()
        let scale = vm.coordinateScale

        let engine = try #require(box.engine)
        engine.bodies[1].position = engine.bodies[1].position * 10
        vm.tick()

        #expect(vm.coordinateScale < scale)
    }

    // MARK: Camera presets

    @Test(arguments: CameraPreset.allCases)
    func cameraPresetSetsAngles(preset: CameraPreset) {
        let (vm, _) = makeViewModel()
        vm.rotateCamera(deltaAzimuth: 1, deltaElevation: 0.3)
        vm.applyCameraPreset(preset)
        #expect(vm.cameraAzimuth == preset.azimuth)
        #expect(vm.cameraElevation == preset.elevation)
    }

    @Test func presetAnglesAreAsLabelled() {
        #expect(CameraPreset.topDown.elevation == 0)
        #expect(CameraPreset.tilted.elevation == .pi / 6)
        #expect(CameraPreset.edgeOn.elevation == .pi / 2)
    }

    // MARK: Vectors

    @Test func vectorsAreEmptyWhenOff() {
        let (vm, _) = makeViewModel()
        #expect(vm.velocityArrows.isEmpty)
        #expect(vm.accelerationArrows.isEmpty)
    }

    @Test func enablingVelocityVectorsShowsOneArrowPerBody() {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.showVelocityVectors = true

        #expect(vm.velocityArrows.count == vm.bodyPositions.count)
        #expect(vm.accelerationArrows.isEmpty)
        // Arrows start at the bodies, and the planet's points along its motion.
        #expect(vm.velocityArrows.map(\.tail) == vm.bodyPositions)
        #expect(vm.velocityArrows[1].tail != vm.velocityArrows[1].head)
    }

    @Test func enablingAccelerationVectorsShowsOneArrowPerBody() {
        let (vm, _) = makeViewModel()
        vm.config.advanced.display.showAccelerationVectors = true
        #expect(vm.accelerationArrows.count == vm.bodyPositions.count)
    }
}
