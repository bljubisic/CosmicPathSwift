//
//  AdvancedSettingsTests.swift
//  CosmicPathSwiftTests
//
//  Advanced sheet settings (issue #20): defaults, survival across Reset,
//  and Restore defaults.
//

import Testing
import Foundation
@testable import CosmicPathSwift

@MainActor
struct AdvancedSettingsTests {
    private let canvas = CGSize(width: 400, height: 300)

    private func makeViewModel() -> SimulationViewModel {
        SimulationViewModel { bodies, _ in MockSimulationEngine(bodies: bodies) }
    }

    /// A value with every display option changed from its default.
    private var nonDefaultDisplay: DisplaySettings {
        DisplaySettings(showSpacetimeGrid: false, showCenterOfMass: false, showRelativisticRadii: false)
    }

    /// A value with both time multipliers changed from their defaults.
    private var nonDefaultTime: TimeSettings {
        TimeSettings(timeStepMultiplier: 0.25, timeSpeed: 4)
    }

    /// A value with every starting condition changed from its default.
    private var nonDefaultInitial: InitialConditionSettings {
        InitialConditionSettings(eccentricity: 0.4, periapsisAngleDeg: 90, chaosEpsilon: 1e-6,
                                 showUnperturbedTwin: true, customLayout: .random, customSeed: 4242)
    }

    /// A value with every physics setting changed from its default.
    private var nonDefaultEngine: EngineSettings {
        EngineSettings(integrator: .yoshida4, softening: 2, collisionMode: .passThrough)
    }

    /// Defaults must reproduce the original physics: Verlet, 5 px softening, merges.
    @Test func engineDefaultsAreNeutral() {
        let engine = SimulationConfig().advanced.engine
        #expect(engine.integrator == .velocityVerlet)
        #expect(engine.softening == GravitySimulationEngine.softening)
        #expect(engine.collisionMode == .merge)
        #expect(EngineSettings.softeningChoices.contains(engine.softening))
    }

    /// Defaults must reproduce the original start: circular orbit, no nudge, triangle.
    @Test func initialDefaultsAreNeutral() {
        let initial = SimulationConfig().advanced.initial
        #expect(initial.eccentricity == 0)
        #expect(initial.periapsisAngleDeg == 0)
        #expect(initial.chaosEpsilon == 0)
        #expect(!initial.isTwinActive)
        #expect(initial.customLayout == .triangle)
    }

    /// Defaults must reproduce the original pacing: base time step at normal speed.
    @Test func timeDefaultsAreNeutral() {
        let time = SimulationConfig().advanced.time
        #expect(time.timeStepMultiplier == 1)
        #expect(time.timeSpeed == 1)
        #expect(TimeSettings.timeStepChoices.contains(time.timeStepMultiplier))
        #expect(TimeSettings.timeSpeedChoices.contains(time.timeSpeed))
    }

    /// Defaults must draw everything, matching the app before the Advanced sheet existed.
    @Test func defaultsShowEverything() {
        let display = SimulationConfig().advanced.display
        #expect(display.showSpacetimeGrid)
        #expect(display.showCenterOfMass)
        #expect(display.showRelativisticRadii)
    }

    @Test func resetKeepsAdvancedSettings() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        vm.config.advanced.display = nonDefaultDisplay
        vm.config.advanced.time = nonDefaultTime
        vm.config.advanced.initial = nonDefaultInitial
        vm.config.advanced.engine = nonDefaultEngine
        vm.config.mass1Multiplier = 5

        vm.reset(canvasSize: canvas)

        #expect(vm.config.advanced.display == nonDefaultDisplay)
        #expect(vm.config.advanced.time == nonDefaultTime)
        #expect(vm.config.advanced.initial == nonDefaultInitial)
        #expect(vm.config.advanced.engine == nonDefaultEngine)
        // Basic sliders are still reset as before.
        #expect(vm.config.mass1Multiplier == SimulationConfig().mass1Multiplier)
    }

    @Test func restoreDefaultsClearsAdvancedSettings() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        vm.config.advanced.display = nonDefaultDisplay
        vm.config.advanced.time = nonDefaultTime
        vm.config.advanced.initial = nonDefaultInitial
        vm.config.advanced.engine = nonDefaultEngine

        vm.restoreAdvancedDefaults()

        #expect(vm.config.advanced == AdvancedSettings())
    }

    /// Restore defaults only touches advanced settings, not the scenario or run state.
    @Test func restoreDefaultsLeavesSimulationAlone() {
        let vm = makeViewModel()
        vm.config.mode = .threeBody
        vm.config.mass2Multiplier = 3
        vm.setup(canvasSize: canvas)
        vm.start()
        vm.config.advanced.display.showSpacetimeGrid = false

        vm.restoreAdvancedDefaults()

        #expect(vm.isRunning)
        #expect(vm.config.mode == .threeBody)
        #expect(vm.config.mass2Multiplier == 3)
        vm.pause()
    }

    /// The settings are Codable so they can be persisted later; the round trip must be lossless.
    @Test func codableRoundTrip() throws {
        let settings = AdvancedSettings(
            display: nonDefaultDisplay, time: nonDefaultTime, initial: nonDefaultInitial, engine: nonDefaultEngine
        )
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AdvancedSettings.self, from: data) == settings)
    }
}
