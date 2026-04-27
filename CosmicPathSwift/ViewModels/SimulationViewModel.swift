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
import ReplayKit
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

    /// True while a ReplayKit screen recording is in progress.
    var isRecording: Bool = false

    /// Set to `true` by `stopRecording()` once the recorded video file is ready.
    /// Observed by `ContentView`, which calls `consumePendingRecording()` to retrieve
    /// the URL and present a share/save sheet, then resets this flag.
    var hasPendingRecording: Bool = false

    /// Current coordinate scale factor (simulation units → canvas pixels).
    /// Used by the view to scale body radii proportionally with zoom.
    var coordinateScale: Double = 1.0

    /// Canvas-space positions and opacities of active bleed particles.
    /// Projected from 3D each frame in `syncState()` for rendering in `SimulationCanvasView`.
    var bleedParticleData: [(position: CGPoint, opacity: Double)] = []

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

    /// True once `setup()` has been called at least once. Used by the canvas view
    /// to distinguish first appearance (needs full init) from re-appearance after
    /// a portrait layout switch (only needs a canvas resize, not engine recreation).
    var isSetup: Bool { engine != nil }

    /// File URL of the recorded video produced by `stopRecording()`.
    /// Consumed by `ContentView` via `consumePendingRecording()` for the share/save sheet.
    /// The caller is responsible for deleting this file after use.
    private var pendingRecordingURL: URL?

    private let engineFactory: @Sendable (CelestialBody, CelestialBody) -> SimulationEngineProtocol
    private var engine: SimulationEngineProtocol?
    private var simulationTask: Task<Void, Never>?
    private var transformer = CoordinateTransformer(canvasSize: .zero)
    private var currentCanvasSize: CGSize = .zero

    /// Tracks the maximum distance any body reaches from the centre of mass, used to
    /// dynamically zoom out so the entire orbit always fits on screen.
    private var maxExtent: Double = 0

    /// Instantaneous centre of mass in simulation space, updated every frame.
    /// Used as the `centerOffset` for the coordinate transformer so the view
    /// stays centred on the two-body system even when numerical integration
    /// causes the CoM to drift slightly from the origin over many orbits.
    private var currentCOM: Vector3D = .zero

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
    /// ## ISCO and Unstable Orbits
    ///
    /// The initial separation is only clamped to `softening * 2` — no ISCO floor.
    /// This means the user can place the planet inside the ISCO (r < 3 rₛ), where
    /// no stable circular orbit exists. When r < ISCO, the initial tangential
    /// velocity is set to the Newtonian value √(GM/r) rather than the Schwarzschild
    /// formula (which diverges near the photon sphere). The sub-circular GR speed
    /// causes the orbit to decay and plunge toward the central body.
    ///
    /// - Normal mode: a "star collision" fires when sep ≤ star surface radius.
    /// - BH mode: an "absorption" fires when sep ≤ rₛ (existing check).
    ///
    /// ## Momentum Conservation
    ///
    /// Body1 receives an equal and opposite velocity (scaled by mass ratio) so
    /// the total system momentum is zero. This keeps the centre of mass fixed.
    func setup(canvasSize: CGSize) {
        currentCanvasSize = canvasSize

        // Compute initial CoM: body1 starts at origin, body2 at (separation, 0, 0).
        // CoM = mass2 * separation / totalMass along x.
        let mass1 = config.simulationMass1
        let mass2 = config.simulationMass2
        let separation = config.simulationSeparation
        let totalMass = mass1 + mass2
        let initialCOM = Vector3D(x: mass2 * separation / totalMass, y: 0, z: 0)
        currentCOM = initialCOM

        // Reserve extra room based on the farthest body's distance from the CoM,
        // not from the origin. This prevents the initial view being too wide when
        // m2 is comparable to m1 (large planet or black hole mass ratio).
        // body2 dist from CoM = separation * m1 / total  (the heavier body is farther)
        // body1 dist from CoM = separation * m2 / total
        let initialMaxFromCOM = separation * max(mass1, mass2) / totalMass
        maxExtent = initialMaxFromCOM * CelestialConstants.orbitMarginFactor

        // Note: the default camera elevation (π/6 = 30°) compresses the orbit
        // vertically by cos(30°) ≈ 0.87, making a perfectly circular orbit
        // appear as a slight ellipse. This is intentional — it gives a natural
        // 3D perspective. Drag the canvas or tap Reset Camera to change the view.
        transformer = CoordinateTransformer(
            canvasSize: canvasSize,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation,
            centerOffset: currentCOM
        )

        // Only prevent numerical blow-up at very small separations; no ISCO floor.
        // Allowing r < ISCO lets the user create genuinely unstable/plunging orbits.
        let rs = 2.0 * GravitySimulationEngine.G * mass1 / GravitySimulationEngine.cSquared
        let minSeparation = GravitySimulationEngine.softening * 2
        let safeSeparation = max(separation, minSeparation)

        // Body1 at the origin; body2 along the x-axis at the initial separation.
        let pos1 = Vector3D(x: 0, y: 0, z: 0)
        let pos2 = Vector3D(x: safeSeparation, y: 0, z: 0)

        // Choose initial tangential speed based on whether r is above or below the ISCO.
        //
        // Above ISCO (r ≥ 3 rₛ): use the Schwarzschild circular speed
        //     v = √(GM / (r − 1.5 rₛ))
        // which exactly cancels the effective-potential gradient and gives a
        // stable nearly-circular orbit.
        //
        // Below ISCO (r < 3 rₛ): the Schwarzschild formula diverges toward
        // the photon sphere (r = 1.5 rₛ) and gives unphysically large speed
        // that would fling the planet away rather than letting it plunge.
        // Instead we use the Newtonian speed √(GM/r), which is sub-circular
        // in GR terms. The extra inward pull from the -3GML²/(c²r⁴) term then
        // dominates and the orbit decays toward the central body.
        let isco = 3.0 * rs
        let orbitalSpeed: Double
        if safeSeparation >= isco {
            let denominator = safeSeparation - 1.5 * rs
            orbitalSpeed = sqrt(GravitySimulationEngine.G * mass1 / denominator)
        } else {
            orbitalSpeed = sqrt(GravitySimulationEngine.G * mass1 / safeSeparation)
        }

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
        // Silently discard any in-progress recording rather than surfacing
        // a save/share sheet mid-reset, which would be jarring for the user.
        if isRecording {
            RPScreenRecorder.shared().stopRecording { _, _ in }
            isRecording = false
        }
        // Clean up any unconsumed temp file from a previous recording.
        if let url = pendingRecordingURL {
            try? FileManager.default.removeItem(at: url)
            pendingRecordingURL = nil
            hasPendingRecording = false
        }
        pause()
        // Restore all user-adjustable parameters to their defaults so the
        // simulation starts fresh regardless of what the sliders were set to.
        config = SimulationConfig()
        // Reset camera to the default 30° elevation view so the orbit is
        // always recognisable after reset.
        cameraAzimuth = 0.0
        cameraElevation = .pi / 6
        setup(canvasSize: canvasSize)
    }

    /// Updates the coordinate transformer when the canvas is resized without disturbing the simulation.
    func resizeCanvas(_ size: CGSize) {
        currentCanvasSize = size
        transformer = CoordinateTransformer(
            canvasSize: size,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation,
            centerOffset: currentCOM
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
            elevation: cameraElevation,
            centerOffset: currentCOM
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
            elevation: cameraElevation,
            centerOffset: currentCOM
        )
        syncState()
    }

    // MARK: - Screen Recording

    /// Starts a ReplayKit screen recording of the simulation.
    ///
    /// Has no effect if the device does not support recording (`isAvailable`),
    /// or if a recording is already in progress. `isRecording` is set to `true`
    /// only after ReplayKit confirms the recording has started successfully.
    func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !isRecording else { return }
        recorder.startRecording { error in
            Task { @MainActor [weak self] in
                if error == nil {
                    self?.isRecording = true
                }
            }
        }
    }

    /// Stops the current screen recording and writes the clip to a temporary `.mp4` file.
    ///
    /// On success, sets `hasPendingRecording = true`. The caller observes this flag
    /// and calls `consumePendingRecording()` to retrieve the URL for the share/save sheet.
    /// The caller is responsible for deleting the temp file after use.
    /// Has no effect if no recording is in progress.
    func stopRecording() {
        guard isRecording else { return }
        // Write the clip to a uniquely-named temp file so concurrent calls
        // don't collide, and so it persists until the share sheet is dismissed.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit_\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mp4")
        RPScreenRecorder.shared().stopRecording(withOutput: tempURL) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.isRecording = false
                if error == nil {
                    self?.pendingRecordingURL = tempURL
                    self?.hasPendingRecording = true
                }
            }
        }
    }

    /// Returns the pending recording URL and clears the pending state.
    ///
    /// Call this immediately after observing `hasPendingRecording == true` to
    /// consume the URL exactly once. The caller owns the file and must delete it
    /// after the share/save sheet is dismissed.
    func consumePendingRecording() -> URL? {
        let url = pendingRecordingURL
        pendingRecordingURL = nil
        hasPendingRecording = false
        return url
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

        // Compute instantaneous centre of mass. Even if numerical integration
        // causes tiny momentum drift each step, measuring extents from the CoM
        // rather than from the fixed origin prevents the zoom from ratcheting
        // outward orbit by orbit as the CoM slowly walks away from the origin.
        let totalMass = engine.body1.mass + engine.body2.mass
        let com = (engine.body1.position * engine.body1.mass
                 + engine.body2.position * engine.body2.mass) * (1.0 / totalMass)
        let previousCOM = currentCOM
        currentCOM = com

        let extent1 = (engine.body1.position - com).magnitude
        let extent2 = (engine.body2.position - com).magnitude
        let currentMax = max(extent1, extent2)

        // minExtent based on the CoM-relative initial half-separation so the view
        // is correctly sized for all mass ratios (not just m1 >> m2).
        let configTotal = config.simulationMass1 + config.simulationMass2
        let initialMaxFromCOM = config.simulationSeparation
            * max(config.simulationMass1, config.simulationMass2) / configTotal
        let minExtent = initialMaxFromCOM * CelestialConstants.orbitMarginFactor

        // 15% headroom around the farthest body so neither sits at the canvas edge.
        let targetExtent = max(currentMax * 1.15, minExtent)
        let previousExtent = maxExtent

        if targetExtent > maxExtent {
            // Zoom out immediately so bodies are never clipped off-screen.
            maxExtent = targetExtent
        } else {
            // Zoom in at different rates depending on state:
            //   • Active orbit: 0.999/frame ≈ 6% oscillation for a 2-second eccentric orbit.
            //     Slow recovery (~13 s to halve) keeps the view stable rather than "bouncing"
            //     as the planet oscillates between perihelion and aphelion.
            //   • After absorption: 0.96/frame recovers in < 0.5 s once the planet is gone,
            //     so the canvas snaps back rather than staying zoomed out indefinitely.
            let decayRate = metrics.isAbsorbed ? 0.96 : 0.999
            maxExtent = max(targetExtent, maxExtent * decayRate)
        }

        if maxExtent != previousExtent || currentCOM != previousCOM {
            transformer = CoordinateTransformer(
                canvasSize: currentCanvasSize,
                simulationSeparation: maxExtent,
                azimuth: cameraAzimuth,
                elevation: cameraElevation,
                centerOffset: currentCOM
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

        // Project bleed particles from 3D simulation space to 2D canvas coordinates.
        bleedParticleData = engine.bleedParticles.map { p in
            (position: transformer.simulationToCanvas(p.position), opacity: p.life)
        }

        metrics = engine.metrics
        coordinateScale = transformer.scale
    }
}
