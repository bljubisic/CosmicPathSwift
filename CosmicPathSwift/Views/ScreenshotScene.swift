//
//  ScreenshotScene.swift
//  CosmicPathSwift
//
//  Debug-only scenes for App Store screenshots. Launch with
//  `-screenshotScene <name>` (e.g. `xcrun simctl launch <device> <bundle id>
//  -screenshotScene planetDisruption`) and the app sets up that scene and
//  starts running, with no taps needed. `AppStore/capture-screenshots.sh`
//  drives this. Each scene is an `AppScenario` (the deep-link setups) plus
//  screenshot-only tweaks. Not compiled into Release builds.
//

#if DEBUG
import Foundation

enum ScreenshotScene: String, CaseIterable {
    /// Visual Black Hole Mode: accretion disk, horizon, photon sphere, ISCO and habitable zone.
    case blackHoleVisual
    /// Realistic probe on an eccentric orbit a few rₛ out: a precessing rosette at true scale.
    case probeRosette
    /// Realistic probe inside the ISCO, captured as it spirals in towards the horizon.
    case horizonPlunge
    /// Realistic rocky planet inside the Roche limit: tides tear it apart.
    case planetDisruption
    /// S2 on its observed orbit around Sagittarius A*.
    case s2
    /// Pythagorean three-body problem, nudged by 10⁻⁶ next to its unperturbed twin.
    case threeBodyChaos
    /// The figure-8 choreography.
    case figureEight
    /// Pythagorean problem at 8× speed, so the ejection comes within seconds.
    case pythagoreanEjection
    /// Lagrange triangle, captured as it comes apart.
    case lagrangeBreakup

    /// Probe distance for `horizonPlunge`: inside the ISCO (3 rₛ), so no stable orbit.
    static let plungeDistanceRs = 2.5

    /// The scene named by the `-screenshotScene` launch argument, if any.
    static var fromLaunchArguments: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "screenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }

    /// `-screenshotRecording YES` keeps the scene running (for preview videos)
    /// instead of freezing it at `captureMoment`.
    static var isRecordingFromLaunchArguments: Bool {
        UserDefaults.standard.bool(forKey: "screenshotRecording")
    }

    /// When the simulation freezes for the capture. The Debug app takes several
    /// seconds to show its first frame, so timing in the app (not in the capture
    /// script) is what makes the screenshots repeatable.
    enum CaptureMoment: Equatable {
        /// After this many seconds of running.
        case afterRunning(seconds: Double)
        /// Once the simulated time reaches `time` (simulation units). Repeatable
        /// where the moment matters, since frame rates vary but the steps don't.
        case atSimulatedTime(_ time: Double, timeout: Double)
        /// This many seconds after the orbit-ending event (plunge, ejection, merger),
        /// so its banner is up. Gives up waiting after `timeout` seconds.
        case afterEvent(seconds: Double, timeout: Double)
    }

    /// Tuned by eye against the captures (see AppStore/custom-product-pages.md).
    var captureMoment: CaptureMoment {
        switch self {
        case .blackHoleVisual: return .afterRunning(seconds: 4)
        case .probeRosette: return .afterRunning(seconds: 6)
        // The probe crosses the horizon ≈ 5.9 s in; this catches it just outside.
        case .horizonPlunge: return .afterRunning(seconds: 5.5)
        case .planetDisruption: return .afterRunning(seconds: 20)
        case .s2: return .afterRunning(seconds: 2.5)
        // B is flung out at ≈ 30,000 and the twin's dashed trails have split; ejection is ≈ 34,000.
        case .threeBodyChaos: return .atSimulatedTime(30_000, timeout: 90)
        // One full loop of the figure-8.
        case .figureEight: return .atSimulatedTime(130, timeout: 30)
        case .pythagoreanEjection: return .afterEvent(seconds: 0.3, timeout: 90)
        // Intact until ≈ 470; by 510 it has broken into loops; B and C merge by ≈ 630.
        case .lagrangeBreakup: return .atSimulatedTime(510, timeout: 90)
        }
    }

    /// Waits for `captureMoment`, then freezes `viewModel` in its running layout.
    @MainActor
    func freeze(_ viewModel: SimulationViewModel) async {
        let pollInterval = Duration.milliseconds(16)  // about one frame
        switch captureMoment {
        case .afterRunning(let seconds):
            try? await Task.sleep(for: .seconds(seconds))
        case .atSimulatedTime(let time, let timeout):
            await wait(timeout: timeout, pollInterval: pollInterval) { viewModel.simulatedTime >= time }
        case .afterEvent(let seconds, let timeout):
            await wait(timeout: timeout, pollInterval: pollInterval) { viewModel.hasOrbitEndingEvent }
            try? await Task.sleep(for: .seconds(seconds))
        }
        guard !Task.isCancelled else { return }
        viewModel.freezeForScreenshot()
    }

    /// Polls `condition` until it holds or `timeout` seconds pass.
    @MainActor
    private func wait(timeout: Double, pollInterval: Duration, until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while !condition(), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// The deep-link scenario this scene is based on.
    var scenario: AppScenario {
        switch self {
        case .blackHoleVisual: return .blackHoleVisual
        case .probeRosette, .horizonPlunge: return .probe
        case .planetDisruption: return .planet
        case .s2: return .s2
        case .threeBodyChaos: return .chaos
        case .figureEight: return .figureEight
        case .pythagoreanEjection: return .pythagorean
        case .lagrangeBreakup: return .lagrange
        }
    }

    /// The scenario's configuration with this scene's screenshot-only tweaks.
    var config: SimulationConfig {
        var config = scenario.config
        switch self {
        case .s2:
            // A full 16-year orbit in under 2 s, so the trail shows the whole ellipse.
            config.advanced.time.galacticCenterRate = .tenYears
        case .horizonPlunge:
            config.advanced.initial.eccentricity = 0
            config.strongFieldDistanceRs = Self.plungeDistanceRs
            // The plunge takes ≈ 0.7 ms; at 1 s = 100 µs it lasts ≈ 7 s on screen.
            config.advanced.time.strongFieldRate = .hundredMicroseconds
        case .pythagoreanEjection:
            config.advanced.time.timeSpeed = 8
        default:
            break
        }
        return config
    }
}

private extension SimulationViewModel {
    /// Whether the event banner is up: absorbed planet, ejection or merger.
    var hasOrbitEndingEvent: Bool {
        metrics.isAbsorbed || systemMetrics.ejectedBodyID != nil || systemMetrics.collision != nil
    }

    /// Simulated time of the current run (simulation units).
    var simulatedTime: Double {
        isThreeBodyMode ? systemMetrics.elapsedTime : metrics.elapsedTime
    }
}
#endif
