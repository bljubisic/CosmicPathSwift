//
//  EngineSettingsTests.swift
//  CosmicPathSwiftTests
//
//  Physics settings from the Advanced sheet (issue #20, PR 5): softening
//  length, collision mode, and how the view model hands them to the engine.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Physics

struct EngineSettingsPhysicsTests {
    private let G = GravitySimulationEngine.G

    @Test func softeningClampsPairDistance() {
        let acceleration = NBodyGravity.pairAcceleration(
            sourceMass: 10, separation: Vector3D(x: 4, y: 0, z: 0), relativeVelocity: .zero, softening: 10
        )
        #expect(abs(acceleration.magnitude - G * 10 / 100) < 1e-12)
        #expect(acceleration.x < 0)
    }

    @Test func mergeDistanceFollowsSoftening() {
        let light = CelestialBody(mass: 1, position: .zero, velocity: .zero)
        #expect(GravitySimulationEngine.collisionDistance(light, light) == 10)
        #expect(GravitySimulationEngine.collisionDistance(light, light, softening: 20) == 40)
    }

    @Test func starSurfaceFollowsSoftening() {
        #expect(GravitySimulationEngine.starSurfaceRadius(schwarzschildRadius: 0.1) == 10)
        #expect(GravitySimulationEngine.starSurfaceRadius(schwarzschildRadius: 0.1, softening: 20) == 40)
    }

    @Test func engineClampsTinySoftening() {
        let settings = EngineSettings(softening: 0)
        #expect(settings.effectiveSoftening == EngineSettings.minimumSoftening)
    }

    /// Two light bodies 30 apart at rest plus a distant third: within 2 × 20 px they merge.
    private func closePair(_ settings: EngineSettings) -> GravitySimulationEngine {
        GravitySimulationEngine(bodies: [
            CelestialBody(id: 0, kind: .star, mass: 1, position: Vector3D(x: 15, y: 0, z: 0), velocity: .zero),
            CelestialBody(id: 1, kind: .star, mass: 1, position: Vector3D(x: -15, y: 0, z: 0), velocity: .zero),
            CelestialBody(id: 2, kind: .star, mass: 1, position: Vector3D(x: 0, y: 500, z: 0), velocity: .zero)
        ], settings: settings)
    }

    @Test func engineMergesWithinItsSoftening() {
        let wide = closePair(EngineSettings(softening: 20))
        wide.step(dt: 0.01)
        #expect(wide.bodies.count == 2)

        let standard = closePair(EngineSettings())
        standard.step(dt: 0.01)
        #expect(standard.bodies.count == 3)
    }

    /// A light star with a planet 30 px away: inside the 40 px surface at softening 20.
    @Test func engineStarSurfaceFollowsSettings() {
        let bodies = [
            CelestialBody(id: 0, kind: .star, mass: 1, position: .zero, velocity: .zero),
            CelestialBody(id: 1, kind: .planet, mass: 1, position: Vector3D(x: 30, y: 0, z: 0), velocity: .zero)
        ]
        let wide = GravitySimulationEngine(bodies: bodies, settings: EngineSettings(softening: 20))
        wide.step(dt: 0.01)
        #expect(wide.metrics.isAbsorbed)

        let standard = GravitySimulationEngine(bodies: bodies)
        standard.step(dt: 0.01)
        #expect(!standard.metrics.isAbsorbed)
    }

    @Test func minimumStartingDistanceFollowsSoftening() {
        var config = SimulationConfig()
        config.separationAU = 0.1
        config.advanced.initial.eccentricity = 0.9
        #expect(InitialConditions.periapsisDistance(config: config) == 10)

        config.advanced.engine.softening = 20
        #expect(InitialConditions.periapsisDistance(config: config) == 40)
    }

    // MARK: - Collision Mode

    /// Two bodies flying head-on at each other, plus a distant third.
    private func headOn(_ mode: CollisionMode) -> GravitySimulationEngine {
        GravitySimulationEngine(bodies: [
            CelestialBody(id: 0, kind: .star, mass: 10, position: Vector3D(x: 50, y: 0, z: 0),
                          velocity: Vector3D(x: -100, y: 0, z: 0)),
            CelestialBody(id: 1, kind: .star, mass: 10, position: Vector3D(x: -50, y: 0, z: 0),
                          velocity: Vector3D(x: 100, y: 0, z: 0)),
            CelestialBody(id: 2, kind: .star, mass: 10, position: Vector3D(x: 0, y: 2000, z: 0), velocity: .zero)
        ], settings: EngineSettings(collisionMode: mode))
    }

    @Test func mergeModeMergesOnContact() {
        let engine = headOn(.merge)
        for _ in 0..<100 { engine.step(dt: 0.01) }
        #expect(engine.bodies.count == 2)
        #expect(engine.systemMetrics.collision != nil)
    }

    @Test func passThroughModeKeepsAllBodies() {
        let engine = headOn(.passThrough)
        for _ in 0..<100 { engine.step(dt: 0.01) }
        #expect(engine.bodies.count == 3)
        #expect(engine.systemMetrics.collision == nil)
        // They crossed: body 0 started on the right and is now on the left.
        #expect(engine.bodies[0].position.x < 0)
        #expect(engine.bodies.allSatisfy { $0.position.magnitude.isFinite })
    }

    // MARK: - Frame Budget

    @Test func stepCapScalesWithForceEvaluations() {
        let cap = TimeSettings.maxStepsPerFrame
        #expect(FrameStepPlanner.stepCap(integrator: .velocityVerlet, engineCount: 1) == cap)
        #expect(FrameStepPlanner.stepCap(integrator: .rk4, engineCount: 1) == cap / 4)
        #expect(FrameStepPlanner.stepCap(integrator: .yoshida4, engineCount: 2) == cap / 3 / 2)
    }
}

// MARK: - ViewModel Wiring

@MainActor
struct EngineSettingsViewModelTests {
    private let canvas = CGSize(width: 400, height: 300)
    private let rk4Settings = EngineSettings(integrator: .rk4, softening: 10, collisionMode: .passThrough)

    private final class EngineRecorder: @unchecked Sendable {
        var engines: [MockSimulationEngine] = []
    }

    private func makeViewModel(_ recorder: EngineRecorder) -> SimulationViewModel {
        SimulationViewModel { bodies, settings in
            let engine = MockSimulationEngine(bodies: bodies, settings: settings)
            recorder.engines.append(engine)
            return engine
        }
    }

    @Test func factoryReceivesConfiguredSettings() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config.advanced.engine = rk4Settings
        vm.setup(canvasSize: canvas)
        #expect(recorder.engines.last?.settings == rk4Settings)
    }

    @Test func changingSettingsRestartsSetup() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.setup(canvasSize: canvas)
        #expect(recorder.engines.count == 1)

        vm.config.advanced.engine.integrator = .yoshida4
        #expect(recorder.engines.count == 2)
        #expect(recorder.engines.last?.settings?.integrator == .yoshida4)
    }

    @Test func chaosTwinUsesSameSettings() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config.mode = .threeBody
        vm.config.advanced.initial.chaosEpsilon = 1e-6
        vm.config.advanced.initial.showUnperturbedTwin = true
        vm.config.advanced.engine = rk4Settings
        vm.setup(canvasSize: canvas)

        let created = recorder.engines.suffix(2)
        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.settings == rk4Settings })
    }

    @Test func rk4LowersStepCap() throws {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config.advanced.engine.integrator = .rk4
        vm.setup(canvasSize: canvas)
        vm.config.stepsPerFrame = TimeSettings.maxStepsPerFrame

        vm.tick()

        let engine = try #require(recorder.engines.last)
        #expect(engine.stepCount == TimeSettings.maxStepsPerFrame / 4)
        #expect(vm.isSpeedLimited)
    }
}
