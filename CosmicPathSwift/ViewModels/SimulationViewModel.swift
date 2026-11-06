//
//  SimulationViewModel.swift
//  CosmicPathSwift
//
//  ViewModel that drives the gravitational simulation in both 2-body
//  (star–planet) and 3-body modes. Bridges the physics engine to the SwiftUI
//  view layer, converting 3D simulation-space coordinates to 2D canvas-space
//  positions via an orthographic camera with adjustable azimuth and elevation.
//
//  ## Responsibilities
//
//  1. **Initial conditions**: Delegates to `InitialConditions` for the
//     star–planet pair or the selected 3-body preset.
//
//  2. **Coordinate transformation**: Projects 3D simulation-space positions
//     to 2D canvas-space positions via `CoordinateTransformer`, which applies
//     an azimuth rotation and elevation tilt before scaling to canvas coordinates.
//
//  3. **Dynamic zoom**: Tracks the farthest body extent each frame and
//     adjusts the transformer scale so the whole system always fits on screen,
//     with gradual zoom-back-in recovery via exponential decay. Ejected bodies
//     are ignored so the camera stays on the remaining bound system.
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

    /// Canvas-space position of every body, projected from 3D. Index-aligned
    /// with the engine's `bodies` (index 0 = star / black hole in 2-body mode).
    var bodyPositions: [CGPoint] = []

    /// Canvas-space trail of every body, projected from 3D.
    var bodyTrails: [[CGPoint]] = []

    /// Rendering category of every body (star / planet / moon).
    var bodyKinds: [BodyKind] = []

    /// Stable ID of every body; survives merges and selects the 3-body colour.
    var bodyIDs: [Int] = []

    /// Simulation mass of every body (used for rₛ rings and grid warp).
    var bodyMasses: [Double] = []

    /// Mass of every body relative to its mode's reference mass. Drives rendered
    /// size and the legend: in 2-body mode these are the slider multipliers.
    var bodyMassMultipliers: [Double] = []

    /// Body indices sorted far-to-near along the camera axis, so drawing in this
    /// order makes nearer bodies occlude farther ones. Updated every frame.
    var renderOrder: [Int] = []

    var isRunning: Bool = false
    var metrics = RelativisticMetrics()
    var systemMetrics = SystemMetrics()
    var config = SimulationConfig() {
        didSet {
            let needsRestart = config.advanced.initial != oldValue.advanced.initial
                || config.advanced.engine != oldValue.advanced.engine
            if needsRestart, isSetup {
                // Starting conditions and physics settings only take effect at
                // setup, so restart with them (the sheet only allows editing them
                // while paused).
                setup(canvasSize: currentCanvasSize)
            } else if config.advanced.display != oldValue.advanced.display {
                // Display options only change projection, so re-project at once;
                // this makes them work while paused as well as while running.
                syncState()
            }
        }
    }

    /// Warning shown in the Advanced sheet when the eccentricity brings the
    /// planet's closest approach inside a danger radius (2-body only).
    var periapsisWarning: String? {
        InitialConditions.periapsisWarning(config: config)
    }

    // MARK: - Chaos Twin State

    /// Canvas positions of the unperturbed twin's bodies. Empty without a twin.
    var ghostPositions: [CGPoint] = []

    /// Canvas trails of the twin's bodies, index-aligned with `ghostPositions`.
    var ghostTrails: [[CGPoint]] = []

    /// IDs of the twin's bodies (for their palette colours).
    var ghostIDs: [Int] = []

    /// Largest main-vs-twin body distance in length units; nil without a twin.
    var twinDivergence: Double?

    /// Simulated time at which the runs diverged, if they have.
    var twinDivergenceTime: Double?

    /// True when the chosen accuracy and speed need more steps per frame than
    /// `TimeSettings.maxStepsPerFrame`, so the simulation runs slower than asked.
    private(set) var isSpeedLimited: Bool = false

    /// Integration step actually used: the scenario's `timeStep` scaled by the
    /// Accuracy multiplier from the Advanced sheet.
    var effectiveTimeStep: Double {
        config.timeStep * config.advanced.time.timeStepMultiplier
    }

    /// Screen recording state and the finished clip awaiting share/save.
    let recorder = ScreenRecorder()

    /// Current coordinate scale factor (simulation units → canvas pixels).
    /// Used by the view to scale body radii proportionally with zoom.
    var coordinateScale: Double = 1.0

    /// Canvas-space positions and opacities of active bleed particles.
    /// Projected from 3D each frame in `syncState()` for rendering in `SimulationCanvasView`.
    var bleedParticleData: [(position: CGPoint, opacity: Double)] = []

    /// Canvas-space velocity arrow per body (index-aligned with `bodyPositions`).
    /// Empty unless enabled in the Advanced sheet.
    var velocityArrows: [CanvasArrow] = []

    /// Canvas-space acceleration arrow per body. Empty unless enabled.
    var accelerationArrows: [CanvasArrow] = []

    // MARK: - Habitable Zone State

    /// Canvas-space polygon of the habitable zone's inner (hot) edge, drawn in
    /// the planet's orbital plane around body1. Empty when no zone is shown.
    var habitableZoneInnerRing: [CGPoint] = []

    /// Canvas-space polygon of the habitable zone's outer (cold) edge.
    var habitableZoneOuterRing: [CGPoint] = []

    /// Where the planet currently sits relative to the zone; nil when no zone is
    /// shown or the planet has been absorbed.
    var habitableStatus: HabitableStatus?

    /// Planet's equilibrium temperature in kelvin; nil under the same conditions
    /// as `habitableStatus`.
    var planetEquilibriumTemperature: Double?

    /// True when even the zone's inner edge lies well beyond the current view.
    /// The zone is deliberately not included in the zoom extent, so a heavy star
    /// doesn't shrink the orbit to a dot; the badge reports it instead.
    var isHabitableZoneOffScreen: Bool = false

    /// Number of vertices in each projected habitable-zone ring.
    static let habitableZoneRingSamples = HabitableZoneProjection.ringSamples

    /// Habitable zone of body1 in 2-body mode, or nil in 3-body mode or when hidden.
    /// Depends only on config, so it is constant during a run.
    var habitableZone: HabitableZone? {
        guard !isThreeBodyMode, config.showHabitableZone else { return nil }
        return HabitableZone.forCentralBody(of: config)
    }

    /// True in black hole mode when the zone's inner edge lies inside the ISCO,
    /// where no stable circular orbit exists.
    var isHabitableZoneInsideISCO: Bool {
        guard let zone = habitableZone, metrics.isBlackHole else { return false }
        return zone.innerPx < metrics.iscoRadius
    }

    // MARK: - Two-Body Shims

    /// Canvas position of the central body (star / black hole) in 2-body mode.
    var body1Position: CGPoint { bodyPositions.first ?? .zero }

    /// Canvas position of the orbiting planet in 2-body mode.
    var body2Position: CGPoint { bodyPositions.count > 1 ? bodyPositions[1] : body1Position }

    /// True in 3-body mode.
    var isThreeBodyMode: Bool { config.mode == .threeBody }

    /// Legend label for each body: slider labels in 2-body mode, otherwise the
    /// body letter and its mass in preset units (e.g. "A 3", "B 4", "C 5").
    var bodyLabels: [String] {
        guard isThreeBodyMode else { return [config.mass1Label, config.mass2Label] }
        return zip(bodyIDs, bodyMassMultipliers).map { id, multiplier in
            "\(SystemMetrics.letter(for: id)) \(String(format: "%.3g", multiplier))"
        }
    }

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

    /// Builds an engine from the initial bodies and the Advanced physics settings.
    typealias EngineFactory = @Sendable ([CelestialBody], EngineSettings) -> SimulationEngineProtocol

    private let engineFactory: EngineFactory
    private var engine: SimulationEngineProtocol?
    private var simulationTask: Task<Void, Never>?
    private var transformer = CoordinateTransformer(canvasSize: .zero)
    private var currentCanvasSize: CGSize = .zero

    /// Turns the speed and accuracy multipliers into whole steps per frame.
    private var stepPlanner = FrameStepPlanner()

    /// Unperturbed copy of the 3-body system for the chaos experiment, if enabled.
    private var chaosTwin: ChaosTwin?

    /// Tracks the maximum distance any body reaches from the centre of mass, used to
    /// dynamically zoom out so the entire system always fits on screen.
    private var maxExtent: Double = 0

    /// Smallest extent the zoom may shrink to: the initial extent × orbit margin.
    private var minimumExtent: Double = 0

    /// Reference mass for `bodyMassMultipliers` in 3-body mode (the preset's mass unit).
    private var massUnit: Double = 1

    /// Dynamical time √(R³/GM) of the initial system; scales the vector arrows.
    private var vectorDynamicalTime: Double = 0

    /// Longest arrow allowed, in simulation units (the initial view extent).
    private var vectorMaxLength: Double = 0

    /// Instantaneous centre of mass in simulation space, updated every frame.
    /// Used as the `centerOffset` for the coordinate transformer so the view
    /// stays centred on the system even when numerical integration causes the
    /// CoM to drift slightly from the origin over many orbits.
    private var currentCOM: Vector3D = .zero

    // MARK: - Init

    init(
        engineFactory: @escaping EngineFactory = { bodies, settings in
            GravitySimulationEngine(bodies: bodies, settings: settings)
        }
    ) {
        self.engineFactory = engineFactory
    }

    // MARK: - Setup

    /// Initialises the simulation for the current mode and config.
    ///
    /// Initial conditions come from `InitialConditions` (see that file for the
    /// orbital-speed, inclination, and preset scaling details). The initial view
    /// is sized from the farthest body's distance from the CoM, not from the
    /// origin, so it is correct for every mass ratio.
    ///
    /// Note: the default camera elevation (π/6 = 30°) compresses the orbit
    /// vertically by cos(30°) ≈ 0.87, making a circular orbit appear as a slight
    /// ellipse. This is intentional — it gives a natural 3D perspective.
    func setup(canvasSize: CGSize) {
        currentCanvasSize = canvasSize

        let bodies: [CelestialBody]
        switch config.mode {
        case .twoBody:
            bodies = InitialConditions.twoBody(config: config)
            massUnit = 1
        case .threeBody:
            bodies = InitialConditions.threeBody(preset: config.threeBodyPreset, config: config)
            massUnit = InitialConditions.units(for: config.threeBodyPreset, config: config).mass
        }

        currentCOM = NBodyGravity.centerOfMass(bodies)
        let initialExtent = bodies.map { ($0.position - currentCOM).magnitude }.max() ?? CelestialConstants.baseAU
        minimumExtent = initialExtent * CelestialConstants.orbitMarginFactor
        maxExtent = minimumExtent
        transformer = makeTransformer()
        vectorDynamicalTime = VectorOverlay.dynamicalTime(
            extent: initialExtent, totalMass: NBodyGravity.totalMass(bodies)
        )
        vectorMaxLength = minimumExtent

        engine = engineFactory(bodies, config.advanced.engine)
        engine?.isBlackHoleMode = config.mode == .twoBody && config.isBlackHoleMode
        chaosTwin = makeChaosTwin()
        stepPlanner.reset()
        updateSpeedLimited()
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

    /// Stops the simulation and restores defaults. The selected mode and 3-body
    /// preset are kept so Reset restarts the scenario the user is looking at,
    /// and the Advanced settings are kept so experienced users don't have to
    /// re-enter them (use `restoreAdvancedDefaults()` for that).
    func reset(canvasSize: CGSize) {
        // Silently discard any in-progress recording rather than surfacing
        // a save/share sheet mid-reset, which would be jarring for the user.
        recorder.discard()
        pause()

        var defaults = SimulationConfig()
        defaults.mode = config.mode
        defaults.threeBodyPreset = config.threeBodyPreset
        defaults.advanced = config.advanced
        config = defaults
        applyIntegrationSettings()

        // Reset camera to the default 30° elevation view so the orbit is
        // always recognisable after reset.
        cameraAzimuth = CameraPreset.tilted.azimuth
        cameraElevation = CameraPreset.tilted.elevation
        setup(canvasSize: canvasSize)
    }

    /// Updates the coordinate transformer when the canvas is resized without disturbing the simulation.
    func resizeCanvas(_ size: CGSize) {
        currentCanvasSize = size
        transformer = makeTransformer()
        syncState()
    }

    /// Reinitialises the simulation with current config without changing run state.
    func applyConfigChange(canvasSize: CGSize) {
        setup(canvasSize: canvasSize)
    }

    /// Advances one frame while paused ("Step One Frame" in the Advanced sheet).
    /// Does nothing while running. Always runs at least one step, so it still
    /// moves at speeds where a frame would otherwise contain no step.
    func stepFrame() {
        guard !isRunning, engine != nil else { return }
        advance(steps: max(planSteps(), 1))
        syncState()
    }

    /// Returns every Advanced setting to its default ("Restore defaults" in the sheet).
    /// If the starting conditions or physics settings were changed, the simulation restarts with the
    /// standard ones (see `config.didSet`); otherwise the run is left alone.
    func restoreAdvancedDefaults() {
        config.advanced = AdvancedSettings()
    }

    /// Shows or hides the habitable zone. Only affects rendering, so it works
    /// while the simulation is running and doesn't restart it.
    func setHabitableZoneVisible(_ visible: Bool) {
        config.showHabitableZone = visible
        syncState()
    }

    // MARK: - Mode & Preset Selection

    /// Switches between 2-body and 3-body mode and restarts the simulation.
    func selectMode(_ mode: SimulationMode, canvasSize: CGSize) {
        guard mode != config.mode else { return }
        config.mode = mode
        applyIntegrationSettings()
        applyConfigChange(canvasSize: canvasSize)
    }

    /// Selects a 3-body preset (with its own time step) and restarts the simulation.
    func selectPreset(_ preset: ThreeBodyPreset, canvasSize: CGSize) {
        config.threeBodyPreset = preset
        applyIntegrationSettings()
        applyConfigChange(canvasSize: canvasSize)
    }

    /// Sets `timeStep` / `stepsPerFrame` for the current mode and preset.
    private func applyIntegrationSettings() {
        switch config.mode {
        case .twoBody:
            let defaults = SimulationConfig()
            config.timeStep = defaults.timeStep
            config.stepsPerFrame = defaults.stepsPerFrame
        case .threeBody:
            config.timeStep = config.threeBodyPreset.timeStep
            config.stepsPerFrame = config.threeBodyPreset.stepsPerFrame
        }
    }

    // MARK: - Camera Control

    /// Resets the camera to its default orientation (azimuth = 0, elevation = 30°).
    ///
    /// Called when the user taps "Reset Camera". Restores the view angle that
    /// gives a natural 3D perspective on a flat orbit without losing any simulation state.
    func resetCamera() {
        applyCameraPreset(.tilted)
    }

    /// Turns the camera to a fixed orientation (Advanced sheet) without touching the simulation.
    func applyCameraPreset(_ preset: CameraPreset) {
        cameraAzimuth = preset.azimuth
        cameraElevation = preset.elevation
        transformer = makeTransformer()
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
        transformer = makeTransformer()
        syncState()
    }

    /// Builds a transformer from the current canvas size, zoom extent, camera, and CoM.
    private func makeTransformer() -> CoordinateTransformer {
        CoordinateTransformer(
            canvasSize: currentCanvasSize,
            simulationSeparation: maxExtent,
            azimuth: cameraAzimuth,
            elevation: cameraElevation,
            centerOffset: currentCOM
        )
    }

    // MARK: - Simulation Loop

    /// One rendered frame: runs the planned number of steps, then syncs state.
    /// Internal (not private) so tests can drive frames without the timer.
    func tick() {
        guard engine != nil else { return }
        advance(steps: planSteps())
        syncState()
    }

    /// Steps for the next frame. The multipliers are read every frame, so
    /// changes in the Advanced sheet apply immediately, even while running.
    /// The cap shrinks for costlier integrators and when a chaos twin shares the frame.
    private func planSteps() -> Int {
        let cap = FrameStepPlanner.stepCap(
            integrator: config.advanced.engine.integrator, engineCount: chaosTwin == nil ? 1 : 2
        )
        let steps = stepPlanner.steps(baseSteps: config.stepsPerFrame, time: config.advanced.time, maxSteps: cap)
        updateSpeedLimited()
        return steps
    }

    private func advance(steps: Int) {
        guard let engine else { return }
        let dt = effectiveTimeStep
        for _ in 0..<steps {
            engine.step(dt: dt)
            chaosTwin?.step(dt: dt)
        }
    }

    /// Builds the unperturbed twin when the chaos experiment is on (3-body, ε > 0).
    private func makeChaosTwin() -> ChaosTwin? {
        guard isThreeBodyMode, config.advanced.initial.isTwinActive else { return nil }
        let preset = config.threeBodyPreset
        let unperturbed = InitialConditions.threeBody(preset: preset, config: config, applyingNudge: false)
        let lengthUnit = InitialConditions.units(for: preset, config: config).length
        // Same physics settings as the main run, so only the nudge differs.
        return ChaosTwin(engine: engineFactory(unperturbed, config.advanced.engine), lengthUnit: lengthUnit)
    }

    /// Projects the twin's bodies and trails and refreshes the divergence readout.
    private func updateChaosTwin(mainBodies: [CelestialBody]) {
        guard let chaosTwin else {
            if !ghostPositions.isEmpty || twinDivergence != nil {
                ghostPositions = []
                ghostTrails = []
                ghostIDs = []
                twinDivergence = nil
                twinDivergenceTime = nil
            }
            return
        }
        chaosTwin.measureDivergence(against: mainBodies)
        let twinBodies = chaosTwin.bodies
        let trailLimit = config.advanced.display.trailPointLimit
        ghostPositions = twinBodies.map { transformer.simulationToCanvas($0.position) }
        ghostTrails = twinBodies.map { transformer.transformTrail(Array($0.trail.suffix(trailLimit))) }
        ghostIDs = twinBodies.map(\.id)
        twinDivergence = chaosTwin.relativeDivergence
        twinDivergenceTime = chaosTwin.divergenceTime
    }

    /// Copies the planner's flag, writing only on change to avoid needless view updates.
    private func updateSpeedLimited() {
        if isSpeedLimited != stepPlanner.isSpeedLimited {
            isSpeedLimited = stepPlanner.isSpeedLimited
        }
    }

    /// Syncs positions, trails, and metrics from the engine to observable state.
    private func syncState() {
        guard let engine else { return }
        let bodies = engine.bodies

        updateZoom(for: bodies)
        projectBodies(bodies)

        // Project bleed particles from 3D simulation space to 2D canvas coordinates.
        bleedParticleData = engine.bleedParticles.map { particle in
            (position: transformer.simulationToCanvas(particle.position), opacity: particle.life)
        }

        updateVectorArrows(bodies)
        updateChaosTwin(mainBodies: bodies)

        metrics = engine.metrics
        systemMetrics = engine.systemMetrics
        coordinateScale = transformer.scale

        updateHabitableZone(bodies)
    }

    // MARK: - Vectors

    /// Projects velocity / acceleration arrows for the enabled kinds.
    private func updateVectorArrows(_ bodies: [CelestialBody]) {
        let display = config.advanced.display
        velocityArrows = display.showVelocityVectors ? arrows(.velocity, for: bodies) : []
        accelerationArrows = display.showAccelerationVectors ? arrows(.acceleration, for: bodies) : []
    }

    private func arrows(_ kind: VectorOverlay.Kind, for bodies: [CelestialBody]) -> [CanvasArrow] {
        VectorOverlay.arrows(
            for: bodies, kind: kind, dynamicalTime: vectorDynamicalTime,
            maxLength: vectorMaxLength, transformer: transformer
        )
    }

    // MARK: - Habitable Zone

    /// Re-projects the habitable-zone rings and updates the planet's status.
    private func updateHabitableZone(_ bodies: [CelestialBody]) {
        let projection: HabitableZoneProjection
        if let zone = habitableZone, bodies.count >= 2 {
            projection = .project(
                zone: zone, star: bodies[0], planet: bodies[1], transformer: transformer,
                maxExtent: maxExtent, isAbsorbed: metrics.isAbsorbed
            )
        } else {
            projection = .empty
        }
        habitableZoneInnerRing = projection.innerRing
        habitableZoneOuterRing = projection.outerRing
        habitableStatus = projection.status
        planetEquilibriumTemperature = projection.equilibriumTemperature
        isHabitableZoneOffScreen = projection.isOffScreen
    }

    /// Re-centres on the CoM and adjusts zoom so every tracked body fits.
    ///
    /// ## Dynamic Zoom
    ///
    /// Tracks the farthest any tracked body reaches from the CoM. Zooms out
    /// instantly if a body exceeds the current extent; zooms back in gradually via
    /// exponential decay after brief excursions. An ejected body is not tracked
    /// (neither for the CoM nor the extent), so the camera stays on the remaining
    /// bound system instead of zooming out forever. The transformer is only rebuilt
    /// when the extent or CoM actually changes.
    ///
    /// With Lock Zoom on (Advanced sheet) the extent is left as it is, so the scale
    /// stays fixed; the view still follows the CoM.
    private func updateZoom(for bodies: [CelestialBody]) {
        let ejectedID = engine?.systemMetrics.ejectedBodyID
        let tracked = bodies.filter { $0.id != ejectedID || bodies.count == 1 }

        // Measuring extents from the instantaneous CoM rather than the fixed origin
        // prevents the zoom from ratcheting outward as the CoM slowly drifts.
        let previousCOM = currentCOM
        currentCOM = NBodyGravity.centerOfMass(tracked)
        let currentMax = tracked.map { ($0.position - currentCOM).magnitude }.max() ?? 0

        // 15% headroom around the farthest body so none sits at the canvas edge.
        let targetExtent = max(currentMax * 1.15, minimumExtent)
        let previousExtent = maxExtent

        if config.advanced.display.lockZoom {
            // Keep the current extent.
        } else if targetExtent > maxExtent {
            // Zoom out immediately so bodies are never clipped off-screen.
            maxExtent = targetExtent
        } else {
            // Zoom in at different rates depending on state:
            //   • Active orbit: 0.999/frame ≈ 6% oscillation for a 2-second eccentric orbit.
            //     Slow recovery (~13 s to halve) keeps the view stable rather than "bouncing"
            //     as the planet oscillates between perihelion and aphelion.
            //   • After absorption or ejection: 0.96/frame recovers in < 0.5 s once the
            //     body is gone, so the canvas snaps back rather than staying zoomed out.
            let bodyLeft = metrics.isAbsorbed || ejectedID != nil
            let decayRate = bodyLeft ? 0.96 : 0.999
            maxExtent = max(targetExtent, maxExtent * decayRate)
        }

        if maxExtent != previousExtent || currentCOM != previousCOM {
            transformer = makeTransformer()
        }
    }

    /// Projects every body's position and trail to canvas space and depth-sorts them.
    private func projectBodies(_ bodies: [CelestialBody]) {
        bodyPositions = bodies.map { transformer.simulationToCanvas($0.position) }
        // The engine keeps a longer buffer; project only the points the user asked for.
        let trailLimit = config.advanced.display.trailPointLimit
        bodyTrails = bodies.map { transformer.transformTrail(Array($0.trail.suffix(trailLimit))) }
        bodyKinds = bodies.map(\.kind)
        bodyIDs = bodies.map(\.id)
        bodyMasses = bodies.map(\.mass)

        if isThreeBodyMode {
            bodyMassMultipliers = bodies.map { $0.mass / massUnit }
        } else {
            // Slider multipliers, so tidal stripping doesn't shrink the rendered planet.
            bodyMassMultipliers = [config.mass1Multiplier, config.mass2Multiplier]
        }

        // Larger depth = farther from the camera = drawn first.
        let depths = bodies.map { transformer.depthOf($0.position) }
        renderOrder = bodies.indices.sorted { depths[$0] > depths[$1] }
    }
}
