//
//  InfoContentTests.swift
//  CosmicPathSwiftTests
//
//  Issue #34: the "What am I looking at?" sheet. Each scenario must get only
//  the sections that apply, with numbers that match the metrics panel, and the
//  habitable-zone explanation must follow the Advanced settings.
//

import Testing
import Foundation
@testable import CosmicPathSwift

@MainActor
private enum Info {
    static let canvas = CGSize(width: 400, height: 400)

    /// A view model with the real engine, set up for `configure`'s scene.
    static func viewModel(_ configure: (inout SimulationConfig) -> Void = { _ in }) -> SimulationViewModel {
        let viewModel = SimulationViewModel()
        var config = SimulationConfig()
        configure(&config)
        viewModel.config = config
        viewModel.setup(canvasSize: canvas)
        return viewModel
    }

    static func content(_ configure: (inout SimulationConfig) -> Void = { _ in }) -> (InfoContent, SimulationViewModel) {
        let viewModel = viewModel(configure)
        return (InfoContent.make(from: viewModel.infoSnapshot), viewModel)
    }

    static func strongField(_ scenario: StrongFieldScenario) -> (inout SimulationConfig) -> Void {
        { config in
            config.advanced.scale = .realistic
            config.isBlackHoleMode = true
            config.strongFieldScenario = scenario
        }
    }

    static func ids(_ content: InfoContent) -> [InfoSectionID] {
        content.sections.map(\.id)
    }
}

// MARK: - Sections per Scenario

@MainActor
struct InfoSectionsTests {

    @Test func visualTwoBodyHasAHabitableZoneButNoBlackHole() {
        let (content, _) = Info.content()
        #expect(Info.ids(content) == [.scene, .scale, .bodies, .habitableZone, .display, .metrics])
        #expect(content.section(.scale)?.fact("Relativity magnified") != nil)
        #expect(content.section(.bodies)?.facts == [
            InfoFact(label: "Star", value: "1 M\u{2609}"), InfoFact(label: "Planet", value: "1 M\u{2295}")
        ])
    }

    @Test func visualBlackHoleModeExplainsTheMagnifiedHorizon() throws {
        let (content, _) = Info.content { $0.isBlackHoleMode = true; $0.separationAU = 1.3 }
        #expect(Info.ids(content).contains(.blackHole))
        let blackHole = try #require(content.section(.blackHole))
        #expect(blackHole.fact("Mass") == "1 M\u{2609}")
        #expect(blackHole.fact("Event horizon r\u{209B} (px)") == "125.0")
        // The real horizon of a 1 M☉ black hole, for comparison.
        #expect(blackHole.paragraphs.contains { $0.contains("2.95 km") })
        // The zone comes from the accretion disk, not a star.
        #expect(content.section(.habitableZone)?.fact("Accretion") == "2.5e-4 of Eddington")
    }

    @Test func realisticPlanetaryUsesARealRateAndNoMagnification() {
        let (content, _) = Info.content { $0.advanced.scale = .realistic }
        #expect(content.section(.scene)?.fact("Time") == "1 s = 1 month")
        #expect(content.section(.scale)?.fact("Relativity magnified") == nil)
        #expect(!Info.ids(content).contains(.blackHole))
    }

    @Test func probeIsCloseEnoughToSeeTheHorizon() throws {
        let (content, _) = Info.content(Info.strongField(.stellarBlackHole))
        let blackHole = try #require(content.section(.blackHole))
        #expect(blackHole.fact("Event horizon r\u{209B}") == "29.5 km")
        #expect(blackHole.fact("Distance") == "8.00 r\u{209B}")
        #expect(blackHole.fact("Distance ÷ horizon") == "8.0×")
        #expect(blackHole.fact("Horizon on screen") != "under 1 pt")
        #expect(blackHole.fact("Roche limit") == nil)
        #expect(content.section(.bodies)?.facts.map(\.label) == ["Black hole", "Probe"])
    }

    @Test func planetExplainsTheRocheLimitAndTheInvisibleHorizon() throws {
        let (content, viewModel) = Info.content(Info.strongField(.blackHolePlanet))
        let blackHole = try #require(content.section(.blackHole))
        let expectedRoche = SimulationConfig.groupedInteger(viewModel.config.blackHolePlanetRocheLimitRs) + " r\u{209B}"
        #expect(blackHole.fact("Roche limit") == expectedRoche)
        #expect(blackHole.fact("Roche limit")?.hasPrefix("40,6") == true)
        #expect(blackHole.fact("Distance ÷ horizon") == "60,000×")
        #expect(blackHole.fact("Horizon on screen") == "under 1 pt")
        #expect(blackHole.paragraphs.contains { $0.contains("far smaller than a pixel") })
    }

    @Test func s2HasNoHabitableZone() throws {
        let (content, _) = Info.content(Info.strongField(.sagittariusAStar))
        #expect(!Info.ids(content).contains(.habitableZone))
        #expect(content.section(.bodies)?.facts.first == InfoFact(label: "Black hole", value: "Sgr A* · 4.3 million M\u{2609}"))
        #expect(content.section(.bodies)?.facts.last?.label == "Star")
        let blackHole = try #require(content.section(.blackHole))
        #expect(blackHole.paragraphs.contains { $0.contains("GRAVITY") })
        #expect(content.section(.scene)?.fact("Time") == "1 s = 1 year")
    }

    @Test func threeBodyHasNoBlackHoleOrHabitableZone() {
        let viewModel = Info.viewModel()
        viewModel.selectMode(.threeBody, canvasSize: Info.canvas)
        viewModel.selectPreset(.pythagorean, canvasSize: Info.canvas)
        let content = InfoContent.make(from: viewModel.infoSnapshot)
        #expect(Info.ids(content) == [.scene, .scale, .bodies, .display, .metrics])
        #expect(content.section(.bodies)?.facts == [
            InfoFact(label: "Body A", value: "3"), InfoFact(label: "Body B", value: "4"), InfoFact(label: "Body C", value: "5")
        ])
        #expect(content.section(.metrics)?.terms.map(\.term) == ["Time", "ΔE/E (GR)", "Closest r", "max v/c", "Status"])
    }
}

// MARK: - Consistency with the Screen

@MainActor
struct InfoConsistencyTests {

    /// The horizon radius in the sheet is the metrics panel's string, in every black hole scene.
    @Test(arguments: [StrongFieldScenario.stellarBlackHole, .blackHolePlanet, .sagittariusAStar])
    func horizonMatchesTheMetricsPanel(scenario: StrongFieldScenario) throws {
        let (content, viewModel) = Info.content(Info.strongField(scenario))
        let panel = MetricsText(config: viewModel.config).schwarzschildRadius(viewModel.metrics)
        #expect(content.section(.blackHole)?.fact("Event horizon " + panel.label) == panel.value)
    }

    @Test func habitableZoneMatchesTheBadge() throws {
        let (content, viewModel) = Info.content()
        let zone = try #require(content.section(.habitableZone))
        let status = try #require(viewModel.habitableStatus)
        let temperature = try #require(viewModel.planetEquilibriumTemperature)
        #expect(zone.fact("Planet") == "\(status.label) · \(String(format: "%.0f", temperature)) K")
        #expect(zone.fact("Planet") == "Habitable · 255 K")
    }
}

// MARK: - Habitable Zone Settings

@MainActor
struct InfoHabitableZoneTests {

    /// Conservative limits: 1.1× and 0.53× Earth's sunlight, 0.95–1.37 AU for the Sun.
    @Test func conservativeLimitsForTheSun() throws {
        let zone = try #require(Info.content().0.section(.habitableZone))
        #expect(zone.fact("Limits") == "Conservative (Kasting et al. 1993)")
        #expect(zone.fact("Inner edge") == "0.95 AU")
        #expect(zone.fact("Outer edge") == "1.37 AU")
        #expect(zone.fact("Brightness") == "1 L\u{2609}")
        #expect(zone.fact("Albedo") == "0.30")
        #expect(zone.paragraphs.contains { $0.contains("1.1× Earth's sunlight") && $0.contains("0.53×") })
    }

    @Test func followsTheAdvancedSettings() throws {
        let (content, _) = Info.content {
            $0.advanced.habitableZone.limits = .optimistic
            $0.advanced.habitableZone.bondAlbedo = 0.6
        }
        let zone = try #require(content.section(.habitableZone))
        #expect(zone.fact("Limits") == "Optimistic (Kopparapu et al. 2013)")
        #expect(zone.fact("Albedo") == "0.60")
        #expect(zone.paragraphs.contains { $0.contains("1.78×") && $0.contains("0.32×") })
    }

    @Test func offScreenNoteOnlyWhenOffScreen() throws {
        var snapshot = Info.viewModel().infoSnapshot
        snapshot.isHabitableZoneOffScreen = false
        let onScreen = try #require(InfoContent.make(from: snapshot).section(.habitableZone))
        #expect(!onScreen.paragraphs.contains { $0.contains("beyond the edge") })

        snapshot.isHabitableZoneOffScreen = true
        let offScreen = try #require(InfoContent.make(from: snapshot).section(.habitableZone))
        #expect(offScreen.paragraphs.contains { $0.contains("beyond the edge") })
    }

    @Test func noHabitableZoneSectionWhenHidden() {
        let (content, _) = Info.content { $0.showHabitableZone = false }
        #expect(!Info.ids(content).contains(.habitableZone))
    }
}

// MARK: - On the Screen

@MainActor
struct InfoDisplayTests {

    @Test func termsFollowTheDisplaySettings() throws {
        let (defaults, _) = Info.content()
        let terms = try #require(defaults.section(.display)).terms.map(\.term)
        #expect(terms.contains("Grid") && terms.contains("CoM") && terms.contains("Red rings"))

        let (hidden, _) = Info.content {
            $0.advanced.display.showSpacetimeGrid = false
            $0.advanced.display.showCenterOfMass = false
            $0.advanced.display.showRelativisticRadii = false
        }
        let hiddenTerms = try #require(hidden.section(.display)).terms.map(\.term)
        #expect(!hiddenTerms.contains("Grid") && !hiddenTerms.contains("CoM") && !hiddenTerms.contains("Red rings"))
    }

    @Test func strongFieldGridIsFlammsParaboloid() throws {
        let (content, _) = Info.content(Info.strongField(.stellarBlackHole))
        let grid = try #require(content.section(.display)?.terms.first { $0.term == "Grid" })
        #expect(grid.definition.contains("Flamm"))
    }

    @Test func snapshotFollowsTheViewModel() {
        let viewModel = Info.viewModel()
        #expect(viewModel.infoSnapshot.config.strongFieldScenario == .stellarBlackHole)
        viewModel.config.advanced.scale = .realistic
        viewModel.config.isBlackHoleMode = true
        viewModel.config.strongFieldScenario = .sagittariusAStar
        viewModel.applyConfigChange(canvasSize: Info.canvas)
        #expect(viewModel.infoSnapshot.bodyLabels.first == "Sgr A* · 4.3 million M\u{2609}")
        #expect(viewModel.infoSnapshot.activeRealTimeRate == .oneYear)
    }
}

// MARK: - Black Hole Metrics Before the First Step

/// Found while building the info sheet: Black Hole Mode is set on the engine
/// after it is created, and the metrics used to stay "not a black hole" until
/// the first step, so a paused scene showed no horizon rings or rₛ.
@MainActor
struct BlackHoleMetricsBeforeFirstStepTests {

    @Test func engineRefreshesMetricsWhenBlackHoleModeChanges() {
        let config = SimulationConfig()
        var blackHoleConfig = config
        blackHoleConfig.isBlackHoleMode = true
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: blackHoleConfig))
        #expect(!engine.metrics.isBlackHole)
        engine.isBlackHoleMode = true
        #expect(engine.metrics.isBlackHole)
        engine.isBlackHoleMode = false
        #expect(!engine.metrics.isBlackHole)
    }

    @Test(arguments: [false, true])
    func pausedBlackHoleSceneIsABlackHoleBeforeStart(realistic: Bool) {
        let viewModel = Info.viewModel {
            $0.isBlackHoleMode = true
            if realistic { $0.advanced.scale = .realistic }
        }
        #expect(!viewModel.isRunning)
        #expect(viewModel.metrics.isBlackHole)
    }
}
