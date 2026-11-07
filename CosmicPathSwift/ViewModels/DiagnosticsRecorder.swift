//
//  DiagnosticsRecorder.swift
//  CosmicPathSwift
//
//  Time series of the current run for the Diagnostics section of the
//  Advanced sheet (issue #20, PR 6): drift charts and the CSV export. Split
//  out of `SimulationViewModel`, like `ScreenRecorder`.
//
//  ## Bounded memory
//
//  One sample is kept every `stride` frames. When the buffer reaches
//  `capacity`, every other sample is dropped and the stride doubles, so the
//  whole run stays visible, evenly spaced, in at most `capacity` samples.
//

import Foundation

/// State of one body at the time of a sample, in simulation space.
struct BodySnapshot: Equatable, Sendable {
    let id: Int
    let mass: Double
    let position: Vector3D
    let velocity: Vector3D
}

/// One recorded frame of the run.
struct DiagnosticsSample: Equatable, Sendable {
    /// Coordinate time (simulation units).
    let time: Double
    /// Relative energy drift ΔE/E at this time.
    let energyDrift: Double
    /// Relative angular-momentum drift ΔL/L at this time.
    let angularMomentumDrift: Double
    /// Every body, in engine order.
    let bodies: [BodySnapshot]
}

@Observable
@MainActor
final class DiagnosticsRecorder {

    /// Most samples kept before the buffer is thinned out.
    static let capacity = 1000

    /// Recorded samples, oldest first.
    private(set) var samples: [DiagnosticsSample] = []

    /// A sample is kept every `stride` frames; doubles each time the buffer fills.
    private(set) var stride: Int = 1

    /// Frames offered since the last reset (those whose time advanced).
    private var frameIndex: Int = 0

    /// Time of the last offered frame, used to ignore re-syncs without a step.
    private var lastTime: Double?

    /// Offers the state of one frame. Ignored unless time has advanced, because
    /// the view model also syncs on camera, resize and display changes.
    func record(time: Double, energyDrift: Double, angularMomentumDrift: Double, bodies: [CelestialBody]) {
        if let lastTime, time <= lastTime { return }
        lastTime = time
        defer { frameIndex += 1 }
        guard frameIndex % stride == 0 else { return }

        samples.append(DiagnosticsSample(
            time: time,
            energyDrift: energyDrift,
            angularMomentumDrift: angularMomentumDrift,
            bodies: bodies.map { BodySnapshot(id: $0.id, mass: $0.mass, position: $0.position, velocity: $0.velocity) }
        ))
        if samples.count >= Self.capacity {
            thinOut()
        }
    }

    /// Clears the run (called whenever the simulation is set up again).
    func reset() {
        samples = []
        stride = 1
        frameIndex = 0
        lastTime = nil
    }

    /// Keeps every other sample (starting with the first) and doubles the stride.
    private func thinOut() {
        samples = samples.enumerated().compactMap { index, sample in index.isMultiple(of: 2) ? sample : nil }
        stride *= 2
    }
}
