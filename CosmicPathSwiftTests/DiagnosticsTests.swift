//
//  DiagnosticsTests.swift
//  CosmicPathSwiftTests
//
//  Diagnostics (issue #20, PR 6): orbital elements, the conserved energy and
//  angular momentum of the 2-body relative orbit, precession against the
//  weak-field formula, 3-body ΔL/L, the run recorder, and the CSV export.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Orbital Elements

struct OrbitalElementsTests {
    private let G = GravitySimulationEngine.G

    /// Relative state at periapsis of an ellipse with semi-major axis a and eccentricity e.
    private func periapsisState(a: Double, e: Double, mass: Double) -> (Vector3D, Vector3D) {
        let rp = a * (1 - e)
        let speed = sqrt(G * mass * (1 + e) / rp)
        return (Vector3D(x: rp, y: 0, z: 0), Vector3D(x: 0, y: speed, z: 0))
    }

    @Test func ellipseElementsAreRecovered() throws {
        let mass = 205.0
        let (r, v) = periapsisState(a: 300, e: 0.4, mass: mass)
        let elements = OrbitalElements.osculating(relativePosition: r, relativeVelocity: v, totalMass: mass)

        #expect(abs(elements.semiMajorAxis - 300) < 1e-9 * 300)
        #expect(abs(elements.eccentricity - 0.4) < 1e-9)
        let period = try #require(elements.period)
        let expected = 2 * Double.pi * sqrt(300 * 300 * 300 / (G * mass))
        #expect(abs(period - expected) < 1e-9 * expected)
    }

    @Test func hyperbolicStateHasNoPeriod() {
        let mass = 205.0
        let r = Vector3D(x: 100, y: 0, z: 0)
        let escape = sqrt(2 * G * mass / 100)
        let v = Vector3D(x: 0, y: 1.5 * escape, z: 0)
        let elements = OrbitalElements.osculating(relativePosition: r, relativeVelocity: v, totalMass: mass)
        #expect(elements.period == nil)
        #expect(elements.eccentricity > 1)
    }
}

// MARK: - Relative-Orbit Invariants

struct RelativeOrbitInvariantTests {
    private let G = GravitySimulationEngine.G

    /// The GR-corrected energy and |r × v| of the relative orbit stay constant
    /// when the integration itself is very accurate (RK4, fine dt, GR on).
    @Test func energyAndAngularMomentumAreConservedByForceLaw() {
        let star = CelestialBody(id: 0, kind: .star, mass: 200, position: .zero, velocity: .zero)
        let rp = 210.0
        let speed = sqrt(G * 205 * 1.3 / rp)
        let planet = CelestialBody(id: 1, kind: .planet, mass: 5,
                                   position: Vector3D(x: rp, y: 0, z: 0), velocity: Vector3D(x: 0, y: speed, z: 0))
        var bodies = NBodyGravity.withAccelerations([star, planet], softening: 5)

        func invariants(_ bodies: [CelestialBody]) -> (Double, Double) {
            let r = bodies[1].position - bodies[0].position
            let v = bodies[1].velocity - bodies[0].velocity
            return (RelativeOrbit.energy(r: r, v: v, totalMass: 205, softening: 5),
                    RelativeOrbit.angularMomentum(r: r, v: v))
        }

        let (e0, l0) = invariants(bodies)
        for _ in 0..<4000 {
            bodies = IntegratorKind.rk4.step(bodies, dt: 0.005, softening: 5)
        }
        let (e1, l1) = invariants(bodies)
        #expect(abs((e1 - e0) / e0) < 1e-8)
        #expect(abs((l1 - l0) / l0) < 1e-8)
    }

    /// Default 2-body orbit for three orbits with the default Verlet integrator.
    @Test func engineDriftStaysSmallOverThreeOrbits() {
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: SimulationConfig()))
        while engine.metrics.orbitsCompleted < 3 {
            engine.step(dt: 0.02)
        }
        #expect(engine.metrics.elapsedTime > 0)
        #expect(abs(engine.metrics.energyDrift) < 1e-3)
        #expect(abs(engine.metrics.angularMomentumDrift) < 1e-3)
    }

    @Test func elapsedTimeAdvancesByDt() {
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: SimulationConfig()))
        for _ in 0..<10 { engine.step(dt: 0.02) }
        #expect(abs(engine.metrics.elapsedTime - 0.2) < 1e-12)
    }
}

// MARK: - Precession

struct PrecessionTests {
    /// An orbit at a = 3 AU with e = 0.5 (the default masses).
    private var wideEccentricConfig: SimulationConfig {
        var config = SimulationConfig()
        config.separationAU = 3
        config.advanced.initial.eccentricity = 0.5
        return config
    }

    private func runTenOrbits(_ config: SimulationConfig) -> GravitySimulationEngine {
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: config))
        while engine.metrics.orbitsCompleted < 10 && !engine.metrics.isAbsorbed {
            engine.step(dt: config.timeStep)
        }
        return engine
    }

    @Test func predictedFormulaMatchesDefinition() {
        // p = 2 rp ra / (rp + ra) = a(1 − e²) for rp = a(1−e), ra = a(1+e).
        let a = 450.0, e = 0.5, mass = 205.0
        let comparison = PrecessionComparison(
            measuredPerOrbit: 1, totalMass: mass, periapsis: a * (1 - e), apoapsis: a * (1 + e)
        )
        let gm = GravitySimulationEngine.G * mass
        let expected = 6 * Double.pi * gm / (GravitySimulationEngine.cSquared * a * (1 - e * e)) * 180 / .pi
        #expect(abs(comparison.predictedPerOrbit - expected) < 1e-12)
        #expect(abs(comparison.ratio - 1 / expected) < 1e-12)
    }

    /// Issue #20: measured precession agrees with 6πGM/(c²a(1−e²)) to ~5%.
    @Test func measuredPrecessionMatchesWeakFieldFormula() throws {
        let engine = runTenOrbits(wideEccentricConfig)
        let metrics = engine.metrics
        let periapsis = try #require(metrics.periapsisDistance)
        let apoapsis = try #require(metrics.apoapsisDistance)
        let comparison = PrecessionComparison(
            measuredPerOrbit: metrics.precessionAngle / Double(metrics.orbitsCompleted),
            totalMass: NBodyGravity.totalMass(engine.bodies),
            periapsis: periapsis, apoapsis: apoapsis
        )
        #expect(abs(comparison.ratio - 1) < 0.05)
        // The next-order term makes the measured value slightly larger.
        #expect(comparison.ratio > 1)
    }

    @Test func turningPointsMatchEllipse() throws {
        let config = wideEccentricConfig
        let engine = GravitySimulationEngine(bodies: InitialConditions.twoBody(config: config))
        while engine.metrics.orbitsCompleted < 1 {
            engine.step(dt: config.timeStep)
        }
        let a = config.simulationSeparation
        let periapsis = try #require(engine.metrics.periapsisDistance)
        let apoapsis = try #require(engine.metrics.apoapsisDistance)
        #expect(abs(periapsis - a * 0.5) < 0.01 * a * 0.5)
        #expect(abs(apoapsis - a * 1.5) < 0.01 * a * 1.5)
    }
}

// MARK: - 3-Body Angular Momentum

struct ThreeBodyAngularMomentumTests {
    @Test func figureEightConservesAngularMomentum() {
        let bodies = InitialConditions.threeBody(preset: .figureEight, config: SimulationConfig())
        let engine = GravitySimulationEngine(bodies: bodies)
        let dt = ThreeBodyPreset.figureEight.timeStep
        for _ in 0..<1000 { engine.step(dt: dt) }
        #expect(engine.systemMetrics.angularMomentumDrift < 1e-9)
    }

    /// Two bodies merging off-centre lose their internal angular momentum; that
    /// loss is excluded, so the drift stays at round-off level.
    @Test func mergeAngularMomentumIsExcluded() {
        let engine = GravitySimulationEngine(bodies: [
            CelestialBody(id: 0, kind: .star, mass: 10, position: Vector3D(x: 50, y: 3, z: 0),
                          velocity: Vector3D(x: -100, y: 0, z: 0)),
            CelestialBody(id: 1, kind: .star, mass: 10, position: Vector3D(x: -50, y: -3, z: 0),
                          velocity: Vector3D(x: 100, y: 0, z: 0)),
            CelestialBody(id: 2, kind: .star, mass: 10, position: Vector3D(x: 0, y: 2000, z: 0), velocity: .zero)
        ])
        for _ in 0..<100 { engine.step(dt: 0.01) }
        #expect(engine.bodies.count == 2)
        #expect(engine.systemMetrics.angularMomentumDrift < 1e-9)
    }
}

// MARK: - Recorder

@MainActor
struct DiagnosticsRecorderTests {
    private let bodies = [
        CelestialBody(id: 0, kind: .star, mass: 200, position: .zero, velocity: .zero),
        CelestialBody(id: 1, kind: .planet, mass: 5, position: Vector3D(x: 150, y: 0, z: 0),
                      velocity: Vector3D(x: 0, y: 26, z: 0))
    ]

    private func record(_ recorder: DiagnosticsRecorder, time: Double) {
        recorder.record(time: time, energyDrift: time * 1e-6, angularMomentumDrift: 0, bodies: bodies)
    }

    @Test func repeatedTimesAreIgnored() {
        let recorder = DiagnosticsRecorder()
        record(recorder, time: 0)
        record(recorder, time: 0)
        record(recorder, time: 1)
        record(recorder, time: 1)
        #expect(recorder.samples.map(\.time) == [0, 1])
    }

    @Test func fullRecorderHalvesAndDoublesStride() {
        let recorder = DiagnosticsRecorder()
        for frame in 0..<DiagnosticsRecorder.capacity {
            record(recorder, time: Double(frame))
        }
        #expect(recorder.samples.count == DiagnosticsRecorder.capacity / 2)
        #expect(recorder.stride == 2)
        #expect(recorder.samples.first?.time == 0)

        // Later samples keep the doubled spacing.
        record(recorder, time: Double(DiagnosticsRecorder.capacity))
        record(recorder, time: Double(DiagnosticsRecorder.capacity + 1))
        let times = recorder.samples.map(\.time)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 == 2 })
    }

    @Test func resetEmptiesRecorder() {
        let recorder = DiagnosticsRecorder()
        for frame in 0..<DiagnosticsRecorder.capacity { record(recorder, time: Double(frame)) }
        recorder.reset()
        #expect(recorder.samples.isEmpty)
        #expect(recorder.stride == 1)
        record(recorder, time: 0)
        #expect(recorder.samples.count == 1)
    }

    @Test func sampleKeepsBodyState() throws {
        let recorder = DiagnosticsRecorder()
        record(recorder, time: 2)
        let sample = try #require(recorder.samples.first)
        #expect(sample.bodies.map(\.id) == [0, 1])
        #expect(sample.bodies[1].position == bodies[1].position)
        #expect(sample.bodies[1].velocity == bodies[1].velocity)
        #expect(sample.energyDrift == 2e-6)
    }
}

// MARK: - CSV

struct DiagnosticsCSVTests {
    private func sample(time: Double) -> DiagnosticsSample {
        DiagnosticsSample(
            time: time, energyDrift: 1.25e-7 * time, angularMomentumDrift: -3e-12,
            bodies: [
                .init(id: 0, mass: 200, position: Vector3D(x: -0.1, y: 0.2, z: 0), velocity: Vector3D(x: 0, y: -0.6, z: 0)),
                .init(id: 1, mass: 5, position: Vector3D(x: 149.9, y: 1.0 / 3.0, z: 0.5),
                      velocity: Vector3D(x: 0.01, y: 25.81, z: 0))
            ]
        )
    }

    private var config: SimulationConfig {
        var config = SimulationConfig()
        config.advanced.engine.integrator = .yoshida4
        return config
    }

    @Test func headerDescribesConfig() {
        let csv = DiagnosticsCSV.make(samples: [sample(time: 0)], config: config)
        let comments = csv.split(separator: "\n").filter { $0.hasPrefix("#") }
        #expect(comments.contains { $0.contains("integrator") && $0.contains("yoshida4") })
        #expect(comments.contains { $0.contains("softening") })
    }

    @Test func rowsParseBack() throws {
        let samples = [sample(time: 0), sample(time: 0.08), sample(time: 0.16)]
        let csv = DiagnosticsCSV.make(samples: samples, config: config)
        let lines = csv.split(separator: "\n").filter { !$0.hasPrefix("#") }

        #expect(lines.first == Substring(DiagnosticsCSV.columnHeader))
        let rows = lines.dropFirst().map { $0.split(separator: ",").map(String.init) }
        #expect(rows.count == samples.count * 2)

        let row = rows[3]   // second sample, planet
        let values = row.map { Double($0) }
        let expectedSample = samples[1]
        let planet = expectedSample.bodies[1]
        let expected: [Double] = [
            expectedSample.time, 1, planet.mass,
            planet.position.x, planet.position.y, planet.position.z,
            planet.velocity.x, planet.velocity.y, planet.velocity.z,
            expectedSample.energyDrift, expectedSample.angularMomentumDrift
        ]
        #expect(values.count == expected.count)
        for (value, target) in zip(values, expected) {
            let parsed = try #require(value)
            #expect(abs(parsed - target) <= 1e-9 * max(abs(target), 1e-300))
        }
    }
}

// MARK: - ViewModel

@MainActor
struct DiagnosticsViewModelTests {
    private let canvas = CGSize(width: 400, height: 300)

    private func makeViewModel() -> SimulationViewModel {
        SimulationViewModel { bodies, _ in MockSimulationEngine(bodies: bodies) }
    }

    @Test func tickingRecordsAndCameraDoesNot() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        #expect(vm.diagnostics.samples.count == 1)

        vm.tick()
        vm.tick()
        #expect(vm.diagnostics.samples.count == 3)

        vm.rotateCamera(deltaAzimuth: 0.3, deltaElevation: 0.1)
        vm.resizeCanvas(CGSize(width: 500, height: 300))
        vm.config.advanced.display.showSpacetimeGrid = false
        #expect(vm.diagnostics.samples.count == 3)
    }

    @Test func setupClearsSamples() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        vm.tick()
        vm.tick()
        vm.setup(canvasSize: canvas)
        #expect(vm.diagnostics.samples.count == 1)
    }

    @Test func threeBodyModeRecordsSystemTime() throws {
        let vm = makeViewModel()
        vm.config.mode = .threeBody
        vm.setup(canvasSize: canvas)
        vm.tick()
        let last = try #require(vm.diagnostics.samples.last)
        #expect(last.time > 0)
        #expect(last.bodies.count == 3)
        #expect(vm.orbitalElements == nil)
    }

    @Test func twoBodyHasOrbitalElements() throws {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        let elements = try #require(vm.orbitalElements)
        #expect(elements.semiMajorAxis > 0)
        // No orbit has completed yet.
        #expect(vm.precessionComparison == nil)
    }
}
