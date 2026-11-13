//
//  AppScenario.swift
//  CosmicPathSwift
//
//  Scenarios that a deep link can open (issue #33): each App Store Custom
//  Product Page links to one, e.g. `cosmicpath://scenario/black-hole/planet`.
//  The Debug-only `ScreenshotScene` builds on the same configurations, so the
//  screenshots and the links show the same setups.
//

import Foundation

/// A ready-made setup the app can open directly, from a deep link or a screenshot scene.
enum AppScenario: String, CaseIterable, Sendable {
    /// Visual Black Hole Mode: accretion disk, horizon, photon sphere, ISCO and habitable zone.
    case blackHoleVisual
    /// Realistic probe on an eccentric orbit a few rₛ out: a precessing rosette at true scale.
    case probe
    /// Realistic rocky planet inside the Roche limit: tides tear it apart.
    case planet
    /// S2 on its observed orbit around Sagittarius A*.
    case s2
    /// The figure-8 three-body choreography.
    case figureEight
    /// The Pythagorean three-body problem, which ends by ejecting a star.
    case pythagorean
    /// Three equal masses at the corners of a rotating equilateral triangle.
    case lagrange
    /// Sun, planet and moon.
    case sunEarthMoon
    /// Pythagorean problem nudged by 10⁻⁶, next to its unperturbed twin.
    case chaos

    // MARK: - Deep links

    /// URL scheme registered in Info.plist (`CFBundleURLTypes`).
    static let urlScheme = "cosmicpath"
    /// First URL component after the scheme: `cosmicpath://scenario/…`.
    static let urlHost = "scenario"

    /// Path components after the host, e.g. `["three-body", "figure-8"]`.
    var pathComponents: [String] {
        switch self {
        case .blackHoleVisual: return ["black-hole", "visual"]
        case .probe: return ["black-hole", "probe"]
        case .planet: return ["black-hole", "planet"]
        case .s2: return ["black-hole", "s2"]
        case .figureEight: return ["three-body", "figure-8"]
        case .pythagorean: return ["three-body", "pythagorean"]
        case .lagrange: return ["three-body", "lagrange"]
        case .sunEarthMoon: return ["three-body", "sun-earth-moon"]
        case .chaos: return ["three-body", "chaos"]
        }
    }

    /// The deep link that opens this scenario.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }

    /// Parses `cosmicpath://scenario/<group>/<name>`, ignoring case and a trailing slash.
    /// Returns nil for any other URL, so unknown links just open the app as usual.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              url.host()?.lowercased() == Self.urlHost else { return nil }
        let components = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }
        guard let match = Self.allCases.first(where: { $0.pathComponents == components }) else { return nil }
        self = match
    }

    // MARK: - Configuration

    /// Visual Black Hole Mode distance: 3.6 rₛ, a stable orbit just outside the ISCO.
    static let visualBlackHoleSeparationAU = 3.0

    /// The configuration the simulation restarts with.
    var config: SimulationConfig {
        var config = SimulationConfig()
        switch self {
        case .blackHoleVisual:
            config.isBlackHoleMode = true
            // Outside the ISCO (3 rₛ = 375 px = 2.5 AU here), so the planet keeps
            // orbiting. The switch's own default, 1.3 AU (1.6 rₛ), plunges at once.
            config.separationAU = Self.visualBlackHoleSeparationAU
        case .probe:
            config.applyStrongField(.stellarBlackHole)
            config.advanced.initial.eccentricity = 0.3
        case .planet:
            config.applyStrongField(.blackHolePlanet)
            config.strongFieldPlanetDistanceRs = 25_000
        case .s2:
            config.applyStrongField(.sagittariusAStar)
        case .figureEight:
            config.applyThreeBody(.figureEight)
        case .pythagorean:
            config.applyThreeBody(.pythagorean)
        case .lagrange:
            config.applyThreeBody(.lagrangeTriangle)
        case .sunEarthMoon:
            config.applyThreeBody(.sunPlanetMoon)
        case .chaos:
            config.applyThreeBody(.pythagorean)
            config.advanced.initial.chaosEpsilon = 1e-6
            config.advanced.initial.showUnperturbedTwin = true
        }
        return config
    }
}

private extension SimulationConfig {
    /// Realistic scale, 2-body, Black Hole Mode: the strong-field setup with `scenario`.
    mutating func applyStrongField(_ scenario: StrongFieldScenario) {
        isBlackHoleMode = true
        advanced.scale = .realistic
        strongFieldScenario = scenario
    }

    /// 3-body mode with `preset` and the preset's own integration settings
    /// (what `SimulationViewModel.selectMode` / `selectPreset` apply).
    mutating func applyThreeBody(_ preset: ThreeBodyPreset) {
        mode = .threeBody
        threeBodyPreset = preset
        timeStep = preset.timeStep
        stepsPerFrame = preset.stepsPerFrame
    }
}
