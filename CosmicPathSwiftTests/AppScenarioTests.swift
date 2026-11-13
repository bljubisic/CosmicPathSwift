//
//  AppScenarioTests.swift
//  CosmicPathSwiftTests
//
//  Issue #33: deep links for the App Store Custom Product Pages
//  (`cosmicpath://scenario/<group>/<name>`), the scenarios they open, and the
//  screenshot scenes built on them.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Parser

struct AppScenarioURLTests {

    /// The links documented in `AppStore/custom-product-pages.md`.
    static let documentedLinks: [(String, AppScenario)] = [
        ("cosmicpath://scenario/black-hole/visual", .blackHoleVisual),
        ("cosmicpath://scenario/black-hole/probe", .probe),
        ("cosmicpath://scenario/black-hole/planet", .planet),
        ("cosmicpath://scenario/black-hole/s2", .s2),
        ("cosmicpath://scenario/three-body/figure-8", .figureEight),
        ("cosmicpath://scenario/three-body/pythagorean", .pythagorean),
        ("cosmicpath://scenario/three-body/lagrange", .lagrange),
        ("cosmicpath://scenario/three-body/sun-earth-moon", .sunEarthMoon),
        ("cosmicpath://scenario/three-body/chaos", .chaos),
    ]

    @Test func documentedLinksOpenTheirScenario() throws {
        for (link, scenario) in Self.documentedLinks {
            let url = try #require(URL(string: link))
            #expect(AppScenario(url: url) == scenario, "\(link)")
        }
    }

    @Test(arguments: AppScenario.allCases)
    func urlRoundTrips(scenario: AppScenario) throws {
        let url = try #require(scenario.url)
        #expect(AppScenario(url: url) == scenario)
    }

    @Test func ignoresCaseAndTrailingSlash() throws {
        let links = [
            "COSMICPATH://Scenario/Black-Hole/Planet",
            "cosmicpath://SCENARIO/BLACK-HOLE/PLANET",
            "cosmicpath://scenario/black-hole/planet/",
        ]
        for link in links {
            let url = try #require(URL(string: link))
            #expect(AppScenario(url: url) == .planet, "\(link)")
        }
    }

    @Test func otherURLsGiveNil() throws {
        let links = [
            "cosmicpath://scenario/black-hole/wormhole",
            "cosmicpath://scenario/black-hole",
            "cosmicpath://scenario",
            "cosmicpath://scenario/black-hole/planet/extra",
            "cosmicpath://settings/black-hole/planet",
            "cosmicpath:///black-hole/planet",
            "https://scenario/black-hole/planet",
            "otherapp://scenario/three-body/figure-8",
        ]
        for link in links {
            let url = try #require(URL(string: link))
            #expect(AppScenario(url: url) == nil, "\(link)")
        }
    }
}

// MARK: - Configurations

struct AppScenarioConfigTests {

    @Test func s2IsGalacticCenter() {
        let config = AppScenario.s2.config
        #expect(config.isGalacticCenter)
        #expect(config.mode == .twoBody)
    }

    @Test func planetIsBlackHolePlanetInsideRocheLimit() {
        let config = AppScenario.planet.config
        #expect(config.isBlackHolePlanet)
        #expect(config.strongFieldPlanetDistanceRs == 25_000)
    }

    @Test func probeIsEccentricStrongField() {
        let config = AppScenario.probe.config
        #expect(config.isStrongField)
        #expect(config.strongFieldScenario == .stellarBlackHole)
        #expect(config.advanced.initial.eccentricity == 0.3)
    }

    @Test func visualBlackHoleKeepsVisualScale() {
        let config = AppScenario.blackHoleVisual.config
        #expect(config.isBlackHoleMode)
        #expect(config.advanced.scale == .visual)
        #expect(!config.isStrongField)
    }

    /// The planet must start outside the ISCO (3 rₛ) so it keeps orbiting.
    @Test func visualBlackHoleStartsOutsideISCO() {
        let config = AppScenario.blackHoleVisual.config
        let scale = config.scale
        let rs = scale.constants.schwarzschildRadius(mass: config.simulationMass1)
        #expect(config.simulationSeparation > 3 * rs)
    }

    @Test func pythagoreanUsesPresetIntegration() {
        let config = AppScenario.pythagorean.config
        #expect(config.mode == .threeBody)
        #expect(config.threeBodyPreset == .pythagorean)
        #expect(config.timeStep == ThreeBodyPreset.pythagorean.timeStep)
        #expect(config.stepsPerFrame == ThreeBodyPreset.pythagorean.stepsPerFrame)
        #expect(!config.isBlackHoleMode)
    }

    @Test func threeBodyPresets() {
        #expect(AppScenario.figureEight.config.threeBodyPreset == .figureEight)
        #expect(AppScenario.lagrange.config.threeBodyPreset == .lagrangeTriangle)
        #expect(AppScenario.sunEarthMoon.config.threeBodyPreset == .sunPlanetMoon)
    }

    @Test func chaosShowsTwin() {
        let config = AppScenario.chaos.config
        #expect(config.threeBodyPreset == .pythagorean)
        #expect(config.advanced.initial.chaosEpsilon == 1e-6)
        #expect(config.advanced.initial.isTwinActive)
    }
}

// MARK: - View model

@MainActor
struct AppScenarioViewModelTests {

    private let canvas = CGSize(width: 400, height: 800)

    private func makeViewModel() -> SimulationViewModel {
        let vm = SimulationViewModel { MockSimulationEngine(bodies: $0.bodies) }
        vm.setup(canvasSize: canvas)
        return vm
    }

    @Test func openingRestartsWithScenarioAndRuns() {
        let vm = makeViewModel()
        vm.open(.figureEight, canvasSize: canvas)
        #expect(vm.config == AppScenario.figureEight.config)
        #expect(vm.isRunning)
        #expect(vm.bodyPositions.count == 3)
        vm.pause()
    }

    /// A second link replaces the first scenario, whatever mode it was in.
    @Test func openingFromThreeBodyBackToBlackHole() {
        let vm = makeViewModel()
        vm.open(.pythagorean, canvasSize: canvas)
        vm.open(.planet, canvasSize: canvas)
        #expect(vm.config.mode == .twoBody)
        #expect(vm.config.isBlackHolePlanet)
        #expect(vm.bodyPositions.count == 2)
        #expect(vm.isRunning)
        vm.pause()
    }

    @Test func openingResetsCamera() {
        let vm = makeViewModel()
        vm.cameraElevation = 0
        vm.open(.s2, canvasSize: canvas)
        #expect(vm.cameraElevation == CameraPreset.tilted.elevation)
        vm.pause()
    }
}

// MARK: - Screenshot scenes

struct ScreenshotSceneTests {

    /// The configuration each original scene produced before the #33 refactor.
    /// One intentional change: `blackHoleVisual` starts at 3 AU (3.6 rₛ), outside
    /// the ISCO, because at the switch's 1.3 AU (1.6 rₛ) the planet plunges at once.
    private static func legacyConfig(_ scene: ScreenshotScene) -> SimulationConfig? {
        var config = SimulationConfig()
        config.isBlackHoleMode = scene != .threeBodyChaos
        switch scene {
        case .blackHoleVisual:
            config.separationAU = 3.0
        case .probeRosette:
            config.advanced.scale = .realistic
            config.strongFieldScenario = .stellarBlackHole
            config.advanced.initial.eccentricity = 0.3
        case .planetDisruption:
            config.advanced.scale = .realistic
            config.strongFieldScenario = .blackHolePlanet
            config.strongFieldPlanetDistanceRs = 25_000
        case .s2:
            config.advanced.scale = .realistic
            config.strongFieldScenario = .sagittariusAStar
            config.advanced.time.galacticCenterRate = .tenYears
        case .threeBodyChaos:
            config.advanced.initial.chaosEpsilon = 1e-6
            config.advanced.initial.showUnperturbedTwin = true
            // What selectMode(.threeBody) + selectPreset(.pythagorean) applied.
            config.mode = .threeBody
            config.threeBodyPreset = .pythagorean
            config.timeStep = ThreeBodyPreset.pythagorean.timeStep
            config.stepsPerFrame = ThreeBodyPreset.pythagorean.stepsPerFrame
        default:
            return nil
        }
        return config
    }

    @Test(arguments: ScreenshotScene.allCases)
    func originalScenesAreUnchanged(scene: ScreenshotScene) {
        guard let legacy = Self.legacyConfig(scene) else { return }
        #expect(scene.config == legacy)
    }

    @Test func horizonPlungeStartsInsideISCO() {
        let config = ScreenshotScene.horizonPlunge.config
        #expect(config.isStrongField)
        #expect(config.strongFieldDistanceRs < 3)
        #expect(config.advanced.initial.eccentricity == 0)
    }

    @Test func pythagoreanEjectionRunsAtEightTimes() {
        let config = ScreenshotScene.pythagoreanEjection.config
        #expect(config.threeBodyPreset == .pythagorean)
        #expect(config.advanced.time.timeSpeed == 8)
    }

    @Test func newThreeBodyScenes() {
        #expect(ScreenshotScene.figureEight.config == AppScenario.figureEight.config)
        #expect(ScreenshotScene.lagrangeBreakup.config == AppScenario.lagrange.config)
    }
}

// MARK: - Black Hole Mode switch

/// The switch's side effects used to live in an `onChange` on the config, so
/// they also fired when a scenario turned Black Hole Mode on, and reset its
/// strong-field distances to the defaults (found while capturing #33).
@MainActor
struct BlackHoleModeSwitchTests {

    private let canvas = CGSize(width: 400, height: 800)

    private func makeViewModel() -> SimulationViewModel {
        let vm = SimulationViewModel { MockSimulationEngine(bodies: $0.bodies) }
        vm.setup(canvasSize: canvas)
        return vm
    }

    @Test func switchingOnInVisualUsesBlackHoleDefaults() {
        let vm = makeViewModel()
        vm.config.separationAU = 2
        vm.config.inclinationDeg = 30
        vm.setBlackHoleMode(true, canvasSize: canvas)
        #expect(vm.config.isBlackHoleMode)
        #expect(vm.config.separationAU == 1.3)
        #expect(vm.config.inclinationDeg == 0)
    }

    @Test func switchingOnInRealisticRestoresStrongFieldDefaults() {
        let vm = makeViewModel()
        vm.config.advanced.scale = .realistic
        vm.config.strongFieldDistanceRs = 2.5
        vm.setBlackHoleMode(true, canvasSize: canvas)
        #expect(vm.config.isStrongField)
        #expect(vm.config.strongFieldDistanceRs == SimulationConfig().strongFieldDistanceRs)
    }

    @Test func switchingOffRestoresVisualSeparation() {
        let vm = makeViewModel()
        vm.setBlackHoleMode(true, canvasSize: canvas)
        vm.setBlackHoleMode(false, canvasSize: canvas)
        #expect(!vm.config.isBlackHoleMode)
        #expect(vm.config.separationAU == 1.0)
    }

    /// Opening a scenario turns Black Hole Mode on without the switch's resets.
    @Test func scenarioKeepsItsDistances() {
        let vm = makeViewModel()
        vm.open(.planet, canvasSize: canvas)
        #expect(vm.config.strongFieldPlanetDistanceRs == 25_000)
        vm.pause()
    }
}
