//
//  SimulationViewModel+Scenario.swift
//  CosmicPathSwift
//
//  Opens a ready-made scenario (deep link or screenshot scene, issue #33).
//

import Foundation

extension SimulationViewModel {
    /// Restarts with `scenario` and starts it running.
    func open(_ scenario: AppScenario, canvasSize: CGSize) {
        run(scenario.config, canvasSize: canvasSize)
    }

    /// Restarts with `config`, from the default camera, and starts running.
    /// Any recording in progress is discarded, as on Reset.
    func run(_ config: SimulationConfig, canvasSize: CGSize) {
        recorder.discard()
        pause()
        cameraAzimuth = CameraPreset.tilted.azimuth
        cameraElevation = CameraPreset.tilted.elevation
        self.config = config
        applyConfigChange(canvasSize: canvasSize)
        start()
    }
}
