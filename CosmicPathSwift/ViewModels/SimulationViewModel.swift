//
//  SimulationViewModel.swift
//  CosmicPathSwift
//
//  ViewModel that drives the Schwarzschild geodesic gravitational simulation.
//  Bridges the physics engine to the SwiftUI view layer, converting
//  simulation-space coordinates to canvas-space positions.
//
//  ## Physics Responsibilities
//
//  This ViewModel handles two physics-related tasks:
//
//  1. **Initial conditions**: Computes the Schwarzschild circular orbit
//     velocity and clamps the initial separation above the ISCO.
//
//  2. **Coordinate transformation**: Converts simulation-space positions
//     (origin at center, units in simulation pixels) to canvas-space
//     positions (origin at top-left, units in screen points) via
//     `CoordinateTransformer` with an auto-zoom scale factor.
//
//  All physics integration is delegated to `SimulationEngineProtocol`.
//  Uses dependency injection via an engine factory for testability.
//

import Foundation
import SwiftUI

@Observable
@MainActor
class SimulationViewModel {
    // MARK: - Observable State

    var body1Position: CGPoint = .zero
    var body2Position: CGPoint = .zero
    var body1Trail: [CGPoint] = []
    var body2Trail: [CGPoint] = []
    var isRunning: Bool = false
    var metrics = RelativisticMetrics()
    var config = SimulationConfig()
    /// Current coordinate scale factor (simulation units → canvas pixels)
    var coordinateScale: Double = 1.0

    // MARK: - Dependencies

    private let engineFactory: @Sendable (CelestialBody, CelestialBody) -> SimulationEngineProtocol
    private var engine: SimulationEngineProtocol?
    private var simulationTask: Task<Void, Never>?
    private var transformer = CoordinateTransformer(canvasSize: .zero)
    private var currentCanvasSize: CGSize = .zero
    /// Tracks the maximum distance any body reaches from center, used to
    /// dynamically zoom out so the entire orbit always fits on screen.
    private var maxExtent: Double = 0

    // MARK: - Init

    init(
        engineFactory: @escaping @Sendable (CelestialBody, CelestialBody) -> SimulationEngineProtocol = { body1, body2 in
            GravitySimulationEngine(body1: body1, body2: body2)
        }
    ) {
        self.engineFactory = engineFactory
    }

    // MARK: - Setup

    /// Initializes the simulation with physically correct initial conditions
    /// for a given canvas size.
    ///
    /// ## Initial Orbital Velocity (Schwarzschild Circular Orbit)
    ///
    /// For a circular orbit in the Schwarzschild metric, the orbital velocity
    /// is derived from setting d²r/dt² = 0 and dr/dt = 0 in the geodesic
    /// equation. This gives:
    ///
    ///     v_circular = √(GM / (r - 1.5 rₛ))
    ///
    /// where rₛ = 2GM/c² is the Schwarzschild radius and 1.5 rₛ is the
    /// photon sphere radius. Key properties:
    ///
    /// - At r >> rₛ: reduces to Newtonian v = √(GM/r)
    /// - At r → 1.5 rₛ: v → ∞ (photon sphere, no massive particle circular orbit)
    /// - At r = 3 rₛ (ISCO): gives the maximum stable orbital velocity
    /// - At r < 3 rₛ: circular orbits exist but are unstable (any perturbation
    ///   causes a plunge or escape)
    ///
    /// ## ISCO Clamping
    ///
    /// The initial separation is clamped to at least 3.5 rₛ (slightly above
    /// the ISCO at 3 rₛ) to ensure the orbit starts in a stable regime.
    /// Without this, configurations with very high mass and small separation
    /// would start below the ISCO and immediately plunge.
    ///
    /// ## Momentum Conservation
    ///
    /// Body1 is given a small opposite velocity v₁ = -(m₂/m₁)·v₂ so that
    /// the total momentum of the system is zero. This keeps the center of
    /// mass stationary and prevents the system from drifting across the screen.
    func setup(canvasSize: CGSize) {
        currentCanvasSize = canvasSize
        // Reserve extra room beyond the initial separation so the full orbit
        // (which can be eccentric) fits on screen without waiting for dynamic zoom.
        maxExtent = config.simulationSeparation * CelestialConstants.orbitMarginFactor
        transformer = CoordinateTransformer(canvasSize: canvasSize, simulationSeparation: maxExtent)

        let mass1 = config.simulationMass1
        let mass2 = config.simulationMass2
        let separation = config.simulationSeparation

        // Clamp initial separation to above ISCO (3 rₛ) for orbital stability.
        // We use 3.5 rₛ to provide a small margin above the marginally stable orbit.
        let rs = 2.0 * GravitySimulationEngine.G * mass1 / GravitySimulationEngine.cSquared
        let minSeparation = max(3.5 * rs, GravitySimulationEngine.softening * 2)
        let safeSeparation = max(separation, minSeparation)

        let pos1 = Vector2D(x: 0, y: 0)
        let pos2 = Vector2D(x: safeSeparation, y: 0)

        // Schwarzschild circular orbit speed: v = √(GM / (r - 1.5 rₛ))
        // The denominator (r - 1.5 rₛ) diverges at the photon sphere,
        // reflecting the impossibility of massive-particle circular orbits there.
        let denominator = max(safeSeparation - 1.5 * rs, 0.1)
        let orbitalSpeed = sqrt(
            GravitySimulationEngine.G * mass1 / denominator
        )

        // Opposite velocity on body1 to conserve total momentum: p₁ + p₂ = 0
        let v1y = -(mass2 / mass1) * orbitalSpeed

        let celestial1 = CelestialBody(
            mass: mass1,
            position: pos1,
            velocity: Vector2D(x: 0, y: v1y)
        )
        let celestial2 = CelestialBody(
            mass: mass2,
            position: pos2,
            velocity: Vector2D(x: 0, y: orbitalSpeed)
        )

        engine = engineFactory(celestial1, celestial2)
        engine?.isBlackHoleMode = config.isBlackHoleMode
        syncState()
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        isRunning = true
        simulationTask = Task { [weak self] in
            let clock = ContinuousClock()
            let frameDuration = Duration.milliseconds(1000 / 60)
            while !Task.isCancelled {
                self?.tick()
                try? await clock.sleep(for: frameDuration)
            }
        }
    }

    func pause() {
        isRunning = false
        simulationTask?.cancel()
        simulationTask = nil
    }

    func reset(canvasSize: CGSize) {
        pause()
        setup(canvasSize: canvasSize)
    }

    /// Updates the coordinate transformer when the canvas is resized without disturbing the simulation.
    func resizeCanvas(_ size: CGSize) {
        currentCanvasSize = size
        transformer = CoordinateTransformer(canvasSize: size, simulationSeparation: maxExtent)
        syncState()
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
    /// Dynamically zooms out if any body moves beyond the current view extent.
    private func syncState() {
        guard let engine else { return }

        // Track the farthest any body reaches from center.
        // Zoom out instantly if a body exceeds the current extent; zoom back in
        // gradually via exponential decay so the view recovers after brief excursions.
        let extent1 = engine.body1.position.magnitude
        let extent2 = engine.body2.position.magnitude
        let currentMax = max(extent1, extent2)

        let minExtent = config.simulationSeparation * CelestialConstants.orbitMarginFactor
        let targetExtent = max(currentMax * 1.1, minExtent)
        let previousExtent = maxExtent

        if targetExtent > maxExtent {
            // Zoom out immediately to keep bodies on screen
            maxExtent = targetExtent
        } else {
            // Slowly decay toward the target so zoom recovers over ~3 seconds at 60fps
            let decayRate = 0.995
            maxExtent = max(targetExtent, maxExtent * decayRate)
        }

        if maxExtent != previousExtent {
            transformer = CoordinateTransformer(
                canvasSize: currentCanvasSize,
                simulationSeparation: maxExtent
            )
        }

        body1Position = transformer.simulationToCanvas(engine.body1.position)
        body2Position = transformer.simulationToCanvas(engine.body2.position)

        body1Trail = transformer.transformTrail(engine.body1.trail)
        body2Trail = transformer.transformTrail(engine.body2.trail)

        metrics = engine.metrics
        coordinateScale = transformer.scale
    }
}
