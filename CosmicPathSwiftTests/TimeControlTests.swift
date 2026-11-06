//
//  TimeControlTests.swift
//  CosmicPathSwiftTests
//
//  Time and integration controls (issue #20, PR 2): the per-frame step planner,
//  the simulated-time trail sampler, the engine's dt-independent trails and
//  bleed emission, and the ViewModel's use of both multipliers.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - FrameStepPlanner

struct FrameStepPlannerTests {

    private func time(accuracy: Double = 1, speed: Double = 1) -> TimeSettings {
        TimeSettings(timeStepMultiplier: accuracy, timeSpeed: speed)
    }

    @Test func defaultSettingsGiveBaseStepsEveryFrame() {
        var planner = FrameStepPlanner()
        for _ in 0..<20 {
            #expect(planner.steps(baseSteps: 4, time: TimeSettings()) == 4)
        }
        #expect(!planner.isSpeedLimited)
    }

    @Test func halfAccuracyDoublesSteps() {
        var planner = FrameStepPlanner()
        #expect(planner.steps(baseSteps: 4, time: time(accuracy: 0.5)) == 8)
    }

    @Test func doubleSpeedDoublesSteps() {
        var planner = FrameStepPlanner()
        #expect(planner.steps(baseSteps: 4, time: time(speed: 2)) == 8)
    }

    /// 4 / 2 × ¼ = 0.5 steps per frame, so one step every other frame.
    @Test func fractionalStepsCarryOver() {
        var planner = FrameStepPlanner()
        let total = (0..<10).reduce(0) { sum, _ in
            sum + planner.steps(baseSteps: 4, time: time(accuracy: 2, speed: 0.25))
        }
        #expect(total == 5)
    }

    @Test func capIsRespectedAndReported() {
        var planner = FrameStepPlanner()
        let steps = planner.steps(baseSteps: 200, time: time(accuracy: 0.25, speed: 8))
        #expect(steps == TimeSettings.maxStepsPerFrame)
        #expect(planner.isSpeedLimited)

        _ = planner.steps(baseSteps: 4, time: TimeSettings())
        #expect(!planner.isSpeedLimited)
    }

    @Test func resetClearsCarry() {
        var planner = FrameStepPlanner()
        #expect(planner.steps(baseSteps: 1, time: time(speed: 0.5)) == 0)
        planner.reset()
        // Without the reset this second call would complete a step.
        #expect(planner.steps(baseSteps: 1, time: time(speed: 0.5)) == 0)
    }
}

// MARK: - TrailSampler

struct TrailSamplerTests {

    @Test func stepEqualToIntervalSamplesAtEndOfEveryStep() {
        var sampler = TrailSampler(interval: 0.02)
        for _ in 0..<50 {
            #expect(sampler.sampleFractions(forStep: 0.02) == [1])
        }
    }

    @Test func quarterStepSamplesEveryFourthStep() {
        var sampler = TrailSampler(interval: 0.02)
        let counts = (0..<40).map { _ in sampler.sampleFractions(forStep: 0.005).count }
        #expect(counts.reduce(0, +) == 10)
        for (index, count) in counts.enumerated() {
            #expect(count == (index % 4 == 3 ? 1 : 0))
        }
    }

    @Test func largeStepGivesSeveralFractionsAndCarriesLeftover() {
        var sampler = TrailSampler(interval: 1)
        let first = sampler.sampleFractions(forStep: 2.5)
        #expect(first.count == 2)
        #expect(abs(first[0] - 0.4) < 1e-12)
        #expect(abs(first[1] - 0.8) < 1e-12)

        // 0.5 left over, so the next samples fall at 0.5, 1.5 and 2.5 into the step.
        let second = sampler.sampleFractions(forStep: 2.5)
        #expect(second.count == 3)
        #expect(abs(second[0] - 0.2) < 1e-12)
        #expect(abs(second[1] - 0.6) < 1e-12)
        #expect(second[2] == 1)
    }

    /// A zero interval means "every step", which the 3-body engine relies on for degenerate systems.
    @Test func zeroIntervalSamplesEveryStep() {
        var sampler = TrailSampler(interval: 0)
        #expect(sampler.sampleFractions(forStep: 0.3) == [1])
    }
}

// MARK: - Engine (real physics)

struct TimeControlEngineTests {

    private func twoBodyEngine() -> GravitySimulationEngine {
        GravitySimulationEngine(bodies: InitialConditions.twoBody(config: SimulationConfig()))
    }

    /// Default settings must reproduce the old behaviour: one trail point per step.
    @Test func defaultStepRecordsOneTrailPointPerStep() {
        let engine = twoBodyEngine()
        let dt = SimulationConfig().timeStep
        for _ in 0..<100 { engine.step(dt: dt) }
        #expect(engine.bodies[1].trail.count == 100)
        #expect(engine.bodies[1].trail.last == engine.bodies[1].position)
    }

    @Test(arguments: [0.005, 0.02, 0.04])
    func trailLengthDependsOnSimulatedTimeOnly(dt: Double) {
        let engine = twoBodyEngine()
        let steps = Int((4.0 / dt).rounded())
        for _ in 0..<steps { engine.step(dt: dt) }
        #expect(abs(engine.bodies[1].trail.count - 200) <= 1)
    }

    /// A planet on a circular orbit inside the Roche limit (≈ 43 px for these masses),
    /// but well outside the star's surface (10 px).
    ///
    /// At this radius the GR term adds ~25 % to the pull (3v²/c²), so the speed is the
    /// circular speed of the corrected force, v² = (GM/r) / (1 − 3GM/(c²r)); the
    /// Newtonian speed would plunge into the star.
    private func rocheEngine() -> GravitySimulationEngine {
        let starMass = CelestialConstants.baseSolarMass
        let radius = 30.0
        let gm = GravitySimulationEngine.G * starMass
        let speed = sqrt(gm / radius / (1 - 3 * gm / (GravitySimulationEngine.cSquared * radius)))
        let star = CelestialBody(id: 0, kind: .star, mass: starMass, position: .zero, velocity: .zero)
        let planet = CelestialBody(
            id: 1, kind: .planet, mass: CelestialConstants.baseEarthMass,
            position: Vector3D(x: radius, y: 0, z: 0), velocity: Vector3D(x: 0, y: speed, z: 0)
        )
        return GravitySimulationEngine(bodies: [star, planet])
    }

    @Test(arguments: [0.005, 0.02, 0.04])
    func bleedEmissionRateDependsOnSimulatedTimeOnly(dt: Double) {
        let engine = rocheEngine()
        let steps = Int((4.0 / dt).rounded())
        for _ in 0..<steps { engine.step(dt: dt) }
        #expect(!engine.metrics.isAbsorbed)
        // One particle per 0.08 time units: 4 / 0.08 = 50.
        #expect(abs(engine.bleedParticles.count - 50) <= 1)
    }
}

// MARK: - ViewModel (mock engine)

@MainActor
struct TimeControlViewModelTests {

    private let canvas = CGSize(width: 400, height: 300)

    /// Holds the mock the factory created so the test can inspect it.
    private final class EngineBox: @unchecked Sendable {
        var engine: MockSimulationEngine?
    }

    private func makeViewModel() -> (SimulationViewModel, EngineBox) {
        let box = EngineBox()
        let vm = SimulationViewModel { bodies, _ in
            let engine = MockSimulationEngine(bodies: bodies)
            box.engine = engine
            return engine
        }
        vm.setup(canvasSize: canvas)
        return (vm, box)
    }

    @Test func defaultTickRunsBaseStepsAtBaseTimeStep() throws {
        let (vm, box) = makeViewModel()
        vm.tick()
        let engine = try #require(box.engine)
        #expect(engine.stepCount == 4)
        #expect(engine.lastDt == 0.02)
    }

    @Test func halfAccuracyHalvesTimeStepAndDoublesSteps() throws {
        let (vm, box) = makeViewModel()
        vm.config.advanced.time.timeStepMultiplier = 0.5
        vm.tick()
        let engine = try #require(box.engine)
        #expect(engine.stepCount == 8)
        #expect(engine.lastDt == 0.01)
        #expect(vm.effectiveTimeStep == 0.01)
    }

    @Test func speedLimitIsExposed() {
        let (vm, _) = makeViewModel()
        vm.config.stepsPerFrame = TimeSettings.maxStepsPerFrame
        vm.config.advanced.time.timeSpeed = 2
        vm.tick()
        #expect(vm.isSpeedLimited)
    }

    @Test func stepFrameAdvancesWhilePaused() throws {
        let (vm, box) = makeViewModel()
        vm.stepFrame()
        #expect(try #require(box.engine).stepCount == 4)
    }

    /// Even when the speed is so low that a frame would contain no step, a manual step moves.
    @Test func stepFrameAlwaysRunsAtLeastOneStep() throws {
        let (vm, box) = makeViewModel()
        vm.config.advanced.time = TimeSettings(timeStepMultiplier: 2, timeSpeed: 0.25)
        vm.stepFrame()
        #expect(try #require(box.engine).stepCount == 1)
    }

    @Test func stepFrameDoesNothingWhileRunning() throws {
        let (vm, box) = makeViewModel()
        vm.start()
        let before = try #require(box.engine).stepCount
        vm.stepFrame()
        #expect(try #require(box.engine).stepCount == before)
        vm.pause()
    }
}
