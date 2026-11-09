//
//  ScreenshotScene.swift
//  CosmicPathSwift
//
//  Debug-only scenes for App Store screenshots. Launch with
//  `-screenshotScene <name>` (e.g. `xcrun simctl launch <device> <bundle id>
//  -screenshotScene planetDisruption`) and the app sets up that scene and
//  starts running, with no taps needed. Not compiled into Release builds.
//

#if DEBUG
import Foundation

enum ScreenshotScene: String, CaseIterable {
    /// Visual Black Hole Mode: accretion disk, horizon, photon sphere, ISCO and habitable zone.
    case blackHoleVisual
    /// Realistic probe on an eccentric orbit a few rₛ out: a precessing rosette at true scale.
    case probeRosette
    /// Realistic rocky planet inside the Roche limit: tides tear it apart.
    case planetDisruption
    /// S2 on its observed orbit around Sagittarius A*.
    case s2
    /// Pythagorean three-body problem, nudged by 10⁻⁶ next to its unperturbed twin.
    case threeBodyChaos

    /// The scene named by the `-screenshotScene` launch argument, if any.
    static var fromLaunchArguments: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "screenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }

    /// Configures `viewModel` for the scene and starts the simulation.
    @MainActor
    func apply(to viewModel: SimulationViewModel, canvasSize: CGSize) {
        var config = SimulationConfig()
        config.isBlackHoleMode = self != .threeBodyChaos
        switch self {
        case .blackHoleVisual:
            // Black Hole Mode's own defaults (ControlPanelView's toggle sets these).
            config.separationAU = 1.3
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
            // A full 16-year orbit in under 2 s, so the trail shows the whole ellipse.
            config.advanced.time.galacticCenterRate = .tenYears
        case .threeBodyChaos:
            config.advanced.initial.chaosEpsilon = 1e-6
            config.advanced.initial.showUnperturbedTwin = true
        }
        viewModel.pause()
        viewModel.config = config
        if self == .threeBodyChaos {
            // selectMode / selectPreset also apply the preset's own time step.
            viewModel.selectMode(.threeBody, canvasSize: canvasSize)
            viewModel.selectPreset(.pythagorean, canvasSize: canvasSize)
        } else {
            viewModel.applyConfigChange(canvasSize: canvasSize)
        }
        viewModel.start()
    }
}
#endif
