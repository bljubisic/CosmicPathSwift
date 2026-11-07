//
//  ChaosTwin.swift
//  CosmicPathSwift
//
//  The unperturbed copy of a 3-body system for the chaos experiment
//  (issue #20, PR 4). The main run starts with body A nudged by ε; the twin
//  starts from the untouched preset and is stepped in lockstep, so the gap
//  between them shows how fast the system magnifies a tiny difference.
//

import Foundation

/// Steps an unperturbed twin engine alongside the main one and measures how
/// far the two runs have drifted apart.
@MainActor
final class ChaosTwin {
    /// The runs count as diverged once some body is this many length units apart.
    static let divergenceThreshold = 0.1

    /// The preset's length unit L; divergence is reported relative to it.
    let lengthUnit: Double

    /// Largest distance between a body and its twin (same ID), in simulation units.
    private(set) var divergence: Double = 0

    /// Simulated time at which `divergence` first exceeded `divergenceThreshold × L`.
    private(set) var divergenceTime: Double?

    private let engine: SimulationEngineProtocol
    private var elapsedTime: Double = 0

    init(engine: SimulationEngineProtocol, lengthUnit: Double) {
        self.engine = engine
        self.lengthUnit = lengthUnit
    }

    /// The twin's bodies, for rendering.
    var bodies: [CelestialBody] { engine.bodies }

    /// Divergence as a multiple of the length unit.
    var relativeDivergence: Double {
        lengthUnit > 0 ? divergence / lengthUnit : 0
    }

    /// Advances the twin by one step (call once per main-engine step).
    func step(dt: Double) {
        engine.step(dt: dt)
        elapsedTime += dt
    }

    /// Updates the divergence from the main run's bodies. Bodies are matched by
    /// ID; one that has merged away in only one run is skipped.
    func measureDivergence(against mainBodies: [CelestialBody]) {
        let twinByID = Dictionary(engine.bodies.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
        divergence = mainBodies.compactMap { body in
            twinByID[body.id].map { (body.position - $0).magnitude }
        }.max() ?? 0

        if divergenceTime == nil && divergence > Self.divergenceThreshold * lengthUnit {
            divergenceTime = elapsedTime
        }
    }
}
