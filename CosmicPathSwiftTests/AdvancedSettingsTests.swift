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
        SimulationViewModel { bodies in MockSimulationEngine(bodies: bodies) }
    }

    /// A value with every display option changed from its default.
    private var nonDefaultDisplay: DisplaySettings {
        DisplaySettings(showSpacetimeGrid: false, showCenterOfMass: false, showRelativisticRadii: false)
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
        vm.config.mass1Multiplier = 5

        vm.reset(canvasSize: canvas)

        #expect(vm.config.advanced.display == nonDefaultDisplay)
        // Basic sliders are still reset as before.
        #expect(vm.config.mass1Multiplier == SimulationConfig().mass1Multiplier)
    }

    @Test func restoreDefaultsClearsAdvancedSettings() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        vm.config.advanced.display = nonDefaultDisplay

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
        let settings = AdvancedSettings(display: nonDefaultDisplay)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AdvancedSettings.self, from: data) == settings)
    }
}
