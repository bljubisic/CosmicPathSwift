//
//  ChaosTwinTests.swift
//  CosmicPathSwiftTests
//
//  The 3-body chaos experiment (issue #20, PR 4): the unperturbed twin's
//  physics, its wiring in the ViewModel, and restarting on setting changes.
//

import Testing
import Foundation
@testable import CosmicPathSwift

/// Records every engine the ViewModel creates, in order (main first, then twin).
private final class EngineRecorder: @unchecked Sendable {
    var engines: [MockSimulationEngine] = []
}

private func chaosConfig(
    preset: ThreeBodyPreset = .figureEight,
    epsilon: Double = 1e-6,
    twin: Bool = true
) -> SimulationConfig {
    var config = SimulationConfig()
    config.mode = .threeBody
    config.threeBodyPreset = preset
    config.timeStep = preset.timeStep
    config.stepsPerFrame = preset.stepsPerFrame
    config.advanced.initial.chaosEpsilon = epsilon
    config.advanced.initial.showUnperturbedTwin = twin
    return config
}

// MARK: - Physics

@MainActor
struct ChaosTwinPhysicsTests {

    /// With no nudge, the twin is the same deterministic calculation and must
    /// match the main run exactly.
    @Test func unnudgedTwinStaysIdentical() {
        let bodies = InitialConditions.threeBody(preset: .figureEight, config: chaosConfig(epsilon: 0))
        let main = GravitySimulationEngine(bodies: bodies)
        let twin = ChaosTwin(engine: GravitySimulationEngine(bodies: bodies), lengthUnit: 150)

        for _ in 0..<500 {
            main.step(dt: 0.03)
            twin.step(dt: 0.03)
        }
        twin.measureDivergence(against: main.bodies)
        #expect(twin.divergence == 0)
        #expect(twin.divergenceTime == nil)
    }

    /// The Pythagorean problem magnifies a 10⁻⁶ nudge by orders of magnitude.
    /// Measured: ~13× after 60k steps, ~220× after 200k, ~3800× by the ejection
    /// near 300k; the test asserts two orders of magnitude at 200k.
    @Test func pythagoreanMagnifiesATinyNudge() {
        let config = chaosConfig(preset: .pythagorean, epsilon: 1e-6)
        let lengthUnit = InitialConditions.units(for: .pythagorean, config: config).length
        let main = GravitySimulationEngine(bodies: InitialConditions.threeBody(preset: .pythagorean, config: config))
        let twin = ChaosTwin(
            engine: GravitySimulationEngine(bodies: InitialConditions.threeBody(
                preset: .pythagorean, config: config, applyingNudge: false
            )),
            lengthUnit: lengthUnit
        )

        twin.measureDivergence(against: main.bodies)
        let initial = twin.divergence
        #expect(initial > 0)

        let dt = ThreeBodyPreset.pythagorean.timeStep
        for _ in 0..<200_000 {
            main.step(dt: dt)
            twin.step(dt: dt)
        }
        twin.measureDivergence(against: main.bodies)
        #expect(twin.divergence / initial > 100, "grew only \(twin.divergence / initial)×")
    }

    @Test func divergenceTimeIsRecordedOnceAboveTheThreshold() {
        let bodies = InitialConditions.threeBody(preset: .figureEight, config: chaosConfig(epsilon: 0))
        let twin = ChaosTwin(engine: MockSimulationEngine(bodies: bodies), lengthUnit: 100)
        twin.step(dt: 2)

        var far = bodies
        far[0].position = far[0].position + Vector3D(x: 50, y: 0, z: 0)   // 0.5 L apart
        twin.measureDivergence(against: far)
        #expect(abs(twin.relativeDivergence - 0.5) < 1e-6)
        #expect(twin.divergenceTime == 2)

        twin.step(dt: 2)
        twin.measureDivergence(against: far)
        #expect(twin.divergenceTime == 2, "the first crossing time is kept")
    }

    @Test func badgeFormatsSmallValuesInScientificNotation() {
        #expect(ChaosTwinBadge.scientific(3.2e-5) == "3.2×10⁻⁵")
        #expect(ChaosTwinBadge.scientific(0.25) == "0.25")
        #expect(ChaosTwinBadge.scientific(0) == "0")
    }
}

// MARK: - ViewModel Wiring

@MainActor
struct ChaosTwinViewModelTests {
    private let canvas = CGSize(width: 400, height: 300)

    private func makeViewModel(_ recorder: EngineRecorder) -> SimulationViewModel {
        SimulationViewModel { bodies, _ in
            let engine = MockSimulationEngine(bodies: bodies)
            recorder.engines.append(engine)
            return engine
        }
    }

    @Test(arguments: [(1e-6, true, 2), (1e-6, false, 1), (0.0, true, 1)])
    func twinIsBuiltOnlyWhenEnabledWithANudge(epsilon: Double, twin: Bool, expectedEngines: Int) {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config = chaosConfig(epsilon: epsilon, twin: twin)
        vm.setup(canvasSize: canvas)
        #expect(recorder.engines.count == expectedEngines)
    }

    @Test func noTwinInTwoBodyMode() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        var config = chaosConfig()
        config.mode = .twoBody
        vm.config = config
        vm.setup(canvasSize: canvas)
        #expect(recorder.engines.count == 1)
        #expect(vm.twinDivergence == nil)
    }

    @Test func twinStepsInLockstepAndIsDrawn() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config = chaosConfig()
        vm.setup(canvasSize: canvas)

        vm.tick()

        let main = recorder.engines[0]
        let twin = recorder.engines[1]
        #expect(main.stepCount == ThreeBodyPreset.figureEight.stepsPerFrame)
        #expect(twin.stepCount == main.stepCount)
        #expect(twin.lastDt == main.lastDt)
        #expect(vm.ghostPositions.count == 3)
        #expect(vm.ghostIDs == [0, 1, 2])
        #expect(vm.twinDivergence != nil)
    }

    @Test func twinHalvesTheStepCap() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        var config = chaosConfig(preset: .pythagorean)
        config.advanced.time = TimeSettings(timeStepMultiplier: 0.25, timeSpeed: 8)
        vm.config = config
        vm.setup(canvasSize: canvas)

        vm.tick()

        #expect(recorder.engines[0].stepCount == TimeSettings.maxStepsPerFrame / 2)
        #expect(vm.isSpeedLimited)
    }

    @Test func turningTheTwinOffClearsTheGhost() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.config = chaosConfig()
        vm.setup(canvasSize: canvas)
        #expect(!vm.ghostPositions.isEmpty)

        vm.config.advanced.initial.showUnperturbedTwin = false

        #expect(vm.ghostPositions.isEmpty)
        #expect(vm.twinDivergence == nil)
    }

    /// Editing a starting condition restarts the setup with it.
    @Test func changingStartingConditionsRestartsTheSetup() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.setup(canvasSize: canvas)
        let enginesBefore = recorder.engines.count

        vm.config.advanced.initial.eccentricity = 0.5

        #expect(recorder.engines.count == enginesBefore + 1)
        let planet = recorder.engines.last!.bodies[1]
        #expect(abs(planet.position.magnitude - CelestialConstants.baseAU * 0.5) < 1e-9)
    }

    /// Display changes must not restart the run.
    @Test func displayChangesDoNotRestart() {
        let recorder = EngineRecorder()
        let vm = makeViewModel(recorder)
        vm.setup(canvasSize: canvas)
        let enginesBefore = recorder.engines.count

        vm.config.advanced.display.showSpacetimeGrid = false

        #expect(recorder.engines.count == enginesBefore)
    }
}
