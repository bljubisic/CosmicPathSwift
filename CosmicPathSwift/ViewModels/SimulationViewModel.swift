//
//  SimulationViewModel.swift
//  CosmicPathSwift
//
//  ViewModel that drives the Schwarzschild geodesic gravitational simulation.
//  Bridges the physics engine to the SwiftUI view layer, converting 3D
//  simulation-space coordinates to 2D canvas-space positions via an
//  orthographic camera with adjustable azimuth and elevation.
//
//  ## Physics Responsibilities
//
//  1. **Initial conditions**: Computes the Schwarzschild circular orbit velocity,
//     clamps the initial separation above the ISCO, and applies the orbital
//     inclination by rotating the initial velocity out of the x-y plane.
//
//  2. **Coordinate transformation**: Projects 3D simulation-space positions
//     to 2D canvas-space positions via `CoordinateTransformer`, which applies
//     an azimuth rotation and elevation tilt before scaling to canvas coordinates.
//
//  3. **Dynamic zoom**: Tracks the farthest body extent each frame and
//     adjusts the transformer scale so the full orbit always fits on screen,
//     with gradual zoom-back-in recovery via exponential decay.
//
//  4. **Camera control**: Exposes `cameraAzimuth` and `cameraElevation` for
//     the view to modify via drag gestures, calling `rotateCamera(_:_:)` to
//     re-project all state with the new camera orientation.
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

    /// Canvas-space position of body 1 (star / black hole), projected from 3D.
    var body1Position: CGPoint = .zero
    /// Canvas-space position of body 2 (planet), projected from 3D.
    var body2Position: CGPoint = .zero

    /// Canvas-space trail of body 1 positions, projected from 3D.
    var body1Trail: [CGPoint] = []
    /// Canvas-space trail of body 2 positions, projected from 3D.
    var body2Trail: [CGPoint] = []

    var isRunning: Bool = false
    var metrics = RelativisticMetrics()
    var config = SimulationConfig()

    /// Current coordinate scale factor (simulation units → canvas pixels).
    /// Used by the view to scale body radii proportionally with zoom.
    var coordinateScale: Double = 1.0

    /// True when body2 (planet) is farther from the camera than body1 (star/BH).
    ///
    /// The canvas uses this to swap the ZStack render order so the closer body
    /// always draws on top of the farther one, giving correct occlusion. Without
    /// this, the planet would appear in front of the black hole even when orbiting
    /// behind it. Updated every frame in `syncState()`.
    var planetIsBehindStar: Bool = false

    // MARK: - Camera State

    /// Camera azimuth in radians — rotation of the scene around the z-axis.
    ///
    /// At 0 the camera looks along the negative x-axis (body2 starts to the right).
    /// Increasing this angle rotates the scene counter-clockwise when viewed from above.
    /// Modified by horizontal drag gestures in `SimulationCanvasView`.
    var cameraAzimuth: Double = 0.0

    /// Camera elevation in radians — tilt of the camera above the orbital plane.
    ///
    /// At 0° the full orbit is visible (top-down view). At 90° it is edge-on.
    /// Default is π/6 (30°), giving a natural 3D perspective on the flat default orbit.
    /// Clamped to [-π/2, π/2] to prevent the view from flipping upside-down.
    /// Modified by vertical drag gestures in `SimulationCanvasView`.
    var cameraElevation: Double = .pi / 6

    // MARK: - Dependencies

    private let engineFactory: @Sendable (CelestialBody, CelestialBody) -> SimulationEngineProtocol
    private var engine: SimulationEngineProtocol?
    private var simulationTask: Task<Void, Never>?
    private var transformer = CoordinateTransformer(canvasSize: .zero)
    private var currentCanvasSize: CGSize = .zero

    /// Tracks the maximum 3D distance any body reaches from the origin, used to
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

    /// Initialises the simulation with physically correct 3D initial conditions.
    ///
    /// ## Orbital Inclination
    ///
    /// At zero inclination the orbit lies in the x-y plane, matching the
    /// former 2D behaviour. The user-specified `config.inclinationRad` tilts
    /// the initial tangential velocity out of the x-y plane around the x-axis:
    ///
    ///     v₂ = (0,  orbitalSpeed·cos(i),  orbitalSpeed·sin(i))
    ///
    /// This places the initial velocity vector in the x-z plane, making the
    /// orbit precess in a plane that is inclined by angle i to the x-y plane.
    /// The angular momentum vector L = r × v then has components along both
    /// y and z, as expected for a tilted orbit.
    ///
    /// ## Schwarzschild Circular Orbit Velocity
    ///
    ///     v_circular = √(GM / (r - 1.5 rₛ))
    ///
    /// - At r >> rₛ: reduces to Newtonian v = √(GM/r).
    /// - At r → 1.5 rₛ: diverges (photon sphere, no massive-particle orbit).
    /// - At r = 3 rₛ (ISCO): maximum stable circular speed.
    ///
    /// ## ISCO Clamping
    ///
    /// The initial separation is clamped to at least 3.5 rₛ (slightly above
    /// the ISCO at 3 rₛ) to ensure the orbit starts in a stable regime.
    ///
    /// ## Momentum Conservation
    ///
    /// Body1 receives an equal and opposite velocity (scaled by mass ratio) so
    /// the total system momentum is zero. This keeps the centre of mass fixed.
    func setup(canvasSize: CGSize) {
        currentCanvasSize = canvasSize

        // Reserve extra room beyond the initial separation so the full orbit
        // (which may be eccentric) fits on screen without waiting for dynamic zoom.
        maxExtent = config.simulationSeparation * CelestialConstants.orbitMarginFactor

        // Note: the default camera elevation (π/6 = 30°) compresses the orbit
        // vertically by cos(30°) ≈ 0.87, making a perfectly circular orbit
        // appear as a slight ellipse. This is intentional — it gives a natural
        // 3D perspective. Drag the canvas or tap Reset Camera to change the view.
        transformer = CoordinateTransformer(
            canvasSize: canvasSize,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation
        )

        let mass1 = config.simulationMass1
        let mass2 = config.simulationMass2
        let separation = config.simulationSeparation

        // Clamp initial separation to above ISCO (3 rₛ) for orbital stability.
        // We use 3.5 rₛ to provide a small margin above the marginally stable orbit.
        let rs = 2.0 * GravitySimulationEngine.G * mass1 / GravitySimulationEngine.cSquared
        let minSeparation = max(3.5 * rs, GravitySimulationEngine.softening * 2)
        let safeSeparation = max(separation, minSeparation)

        // Body1 at the origin; body2 along the x-axis at the initial separation.
        let pos1 = Vector3D(x: 0, y: 0, z: 0)
        let pos2 = Vector3D(x: safeSeparation, y: 0, z: 0)

        // Schwarzschild circular orbit speed: v = √(GM / (r - 1.5 rₛ))
        // The denominator (r - 1.5 rₛ) diverges at the photon sphere.
        let denominator = max(safeSeparation - 1.5 * rs, 0.1)
        let orbitalSpeed = sqrt(GravitySimulationEngine.G * mass1 / denominator)

        // Apply inclination: rotate the tangential velocity from the y-axis
        // toward the z-axis by the inclination angle i.
        //   vy = orbitalSpeed · cos(i)   (in-plane component)
        //   vz = orbitalSpeed · sin(i)   (out-of-plane component)
        // At i=0° this reduces to the flat 2D orbit: v = (0, orbitalSpeed, 0).
        let inclination = config.inclinationRad
        let vy2 = orbitalSpeed * cos(inclination)
        let vz2 = orbitalSpeed * sin(inclination)

        // Counter-velocity on body1 to conserve total linear momentum: p₁ + p₂ = 0.
        // Applied in both the y and z components so all three momentum components cancel.
        let vy1 = -(mass2 / mass1) * vy2
        let vz1 = -(mass2 / mass1) * vz2

        let celestial1 = CelestialBody(
            mass: mass1,
            position: pos1,
            velocity: Vector3D(x: 0, y: vy1, z: vz1)
        )
        let celestial2 = CelestialBody(
            mass: mass2,
            position: pos2,
            velocity: Vector3D(x: 0, y: vy2, z: vz2)
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
        transformer = CoordinateTransformer(
            canvasSize: size,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation
        )
        syncState()
    }

    /// Reinitialises the simulation with current config without changing run state.
    func applyConfigChange(canvasSize: CGSize) {
        setup(canvasSize: canvasSize)
    }

    // MARK: - Camera Control

    /// Resets the camera to its default orientation (azimuth = 0, elevation = 30°).
    ///
    /// Called when the user taps "Reset Camera". Restores the view angle that
    /// gives a natural 3D perspective on a flat orbit without losing any simulation state.
    func resetCamera() {
        cameraAzimuth = 0.0
        cameraElevation = .pi / 6
        transformer = CoordinateTransformer(
            canvasSize: currentCanvasSize,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation
        )
        syncState()
    }

    /// Rotates the camera by incremental delta angles and re-projects all visible state.
    ///
    /// Called by `SimulationCanvasView` in response to drag gestures:
    ///   - Horizontal drag → `deltaAzimuth`  (scene rotates left/right)
    ///   - Vertical drag   → `deltaElevation` (scene tilts up/down)
    ///
    /// Elevation is clamped to [-π/2, π/2] to prevent the view flipping upside-down.
    /// After adjusting the angles, the transformer is rebuilt and all canvas positions
    /// are re-projected from the engine's current 3D state.
    ///
    /// - Parameters:
    ///   - deltaAzimuth: Increment to add to `cameraAzimuth` (radians).
    ///   - deltaElevation: Increment to add to `cameraElevation` (radians).
    func rotateCamera(deltaAzimuth: Double, deltaElevation: Double) {
        cameraAzimuth += deltaAzimuth
        cameraElevation = max(-.pi / 2, min(.pi / 2, cameraElevation + deltaElevation))
        transformer = CoordinateTransformer(
            canvasSize: currentCanvasSize,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation
        )
        syncState()
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
    ///
    /// ## Dynamic Zoom
    ///
    /// Tracks the farthest any body reaches from the origin (3D magnitude).
    /// Zooms out instantly if a body exceeds the current extent; zooms back in
    /// gradually via exponential decay (~3 s at 60 fps) after brief excursions.
    /// The transformer is only rebuilt when `maxExtent` actually changes, avoiding
    /// unnecessary allocations during steady-state orbits.
    private func syncState() {
        guard let engine else { return }

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
            // Slowly decay toward the target so zoom recovers over ~3 seconds at 60 fps
            let decayRate = 0.995
            maxExtent = max(targetExtent, maxExtent * decayRate)
        }

        if maxExtent != previousExtent {
            transformer = CoordinateTransformer(
                canvasSize: currentCanvasSize,
                simulationSeparation: maxExtent,
                azimuth: cameraAzimuth,
                elevation: cameraElevation
            )
        }

        // Project 3D positions to 2D canvas coordinates
        body1Position = transformer.simulationToCanvas(engine.body1.position)
        body2Position = transformer.simulationToCanvas(engine.body2.position)

        // Project 3D trails to arrays of 2D canvas points
        body1Trail = transformer.transformTrail(engine.body1.trail)
        body2Trail = transformer.transformTrail(engine.body2.trail)

        // Depth-sort: the body with larger depth is farther from the camera
        // and must be rendered first so the nearer body occludes it correctly.
        let depth1 = transformer.depthOf(engine.body1.position)
        let depth2 = transformer.depthOf(engine.body2.position)
        planetIsBehindStar = depth2 > depth1

        metrics = engine.metrics
        coordinateScale = transformer.scale
    }
}
