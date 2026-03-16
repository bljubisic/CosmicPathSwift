//
//  SimulationViewModel.swift
//  CosmicPathSwift
//
//  ViewModel that drives the relativistic gravitational simulation.
//  Uses dependency injection via an engine factory for testability.
//

import Foundation
import SwiftUI

@Observable
class SimulationViewModel {
    // MARK: - Observable State

    var body1Position: CGPoint = .zero
    var body2Position: CGPoint = .zero
    var body1Trail: [CGPoint] = []
    var body2Trail: [CGPoint] = []
    var isRunning: Bool = false
    var metrics = RelativisticMetrics()
    var config = SimulationConfig()

    // MARK: - Dependencies

    private let engineFactory: (CelestialBody, CelestialBody) -> SimulationEngineProtocol
    private var engine: SimulationEngineProtocol?
    private var displayLink: Timer?
    private var transformer = CoordinateTransformer(canvasSize: .zero)

    // MARK: - Init

    init(
        engineFactory: @escaping (CelestialBody, CelestialBody) -> SimulationEngineProtocol = { body1, body2 in
            GravitySimulationEngine(body1: body1, body2: body2)
        }
    ) {
        self.engineFactory = engineFactory
    }

    // MARK: - Setup

    /// Initializes the simulation for a given canvas size.
    func setup(canvasSize: CGSize) {
        transformer = CoordinateTransformer(canvasSize: canvasSize)

        let pos1 = Vector2D(x: 0, y: 0)
        let pos2 = Vector2D(x: config.initialSeparation, y: 0)

        // Orbital speed for a roughly circular orbit: v = sqrt(G * M / r)
        let orbitalSpeed = sqrt(
            GravitySimulationEngine.G * config.mass1 / config.initialSeparation
        )

        // Give the heavy body a small opposite velocity to conserve momentum
        let v1y = -(config.mass2 / config.mass1) * orbitalSpeed

        let celestial1 = CelestialBody(
            mass: config.mass1,
            position: pos1,
            velocity: Vector2D(x: 0, y: v1y)
        )
        let celestial2 = CelestialBody(
            mass: config.mass2,
            position: pos2,
            velocity: Vector2D(x: 0, y: orbitalSpeed)
        )

        engine = engineFactory(celestial1, celestial2)
        syncState()
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        isRunning = true
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func pause() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
    }

    func reset(canvasSize: CGSize) {
        pause()
        setup(canvasSize: canvasSize)
    }

    /// Reinitializes the simulation with current config without changing run state.
    func applyConfigChange(canvasSize: CGSize) {
        setup(canvasSize: canvasSize)
    }

    // MARK: - Simulation Loop

    private func tick() {
        guard let engine else { return }
        for _ in 0..<config.stepsPerFrame {
            engine.step(dt: config.timeStep)
        }
        syncState()
    }

    /// Syncs positions, trails, and metrics from the engine to observable state.
    private func syncState() {
        guard let engine else { return }

        body1Position = transformer.simulationToCanvas(engine.body1.position)
        body2Position = transformer.simulationToCanvas(engine.body2.position)

        body1Trail = transformer.transformTrail(engine.body1.trail)
        body2Trail = transformer.transformTrail(engine.body2.trail)

        metrics = engine.metrics
    }
}
