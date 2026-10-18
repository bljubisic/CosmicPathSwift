//
//  ThreeBodyPresetTests.swift
//  CosmicPathSwiftTests
//
//  Tests for 3-body initial conditions, the N-body engine features
//  (merges, ejection, metrics), and the ViewModel in 3-body mode.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Helpers

private func threeBodyConfig(_ preset: ThreeBodyPreset) -> SimulationConfig {
    var config = SimulationConfig()
    config.mode = .threeBody
    config.threeBodyPreset = preset
    return config
}

private func maxPairwiseDistance(_ bodies: [CelestialBody]) -> Double {
    var result = 0.0
    for i in bodies.indices {
        for j in bodies.indices where j > i {
            result = max(result, (bodies[i].position - bodies[j].position).magnitude)
        }
    }
    return result
}

/// Dimensionless period of the Chenciner–Montgomery figure-eight.
private let figureEightPeriod = 6.32591398

// MARK: - Preset Tests

struct ThreeBodyPresetTests {

    @Test(arguments: ThreeBodyPreset.allCases)
    func presetIsInCenterOfMassFrame(preset: ThreeBodyPreset) {
        let bodies = InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset))
        let totalMass = NBodyGravity.totalMass(bodies)
        #expect(bodies.count == 3)
        #expect(NBodyGravity.centerOfMass(bodies).magnitude < 1e-9)
        // Relative to a typical momentum scale, net momentum must vanish.
        #expect(NBodyGravity.totalMomentum(bodies).magnitude / totalMass < 1e-9)
    }

    @Test(arguments: ThreeBodyPreset.allCases)
    func presetHasDistinctIDs(preset: ThreeBodyPreset) {
        let bodies = InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset))
        #expect(bodies.map(\.id) == [0, 1, 2])
    }

    @Test(arguments: ThreeBodyPreset.allCases)
    func presetStartsOutsideCollisionDistance(preset: ThreeBodyPreset) {
        let bodies = InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset))
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let distance = (bodies[i].position - bodies[j].position).magnitude
                #expect(distance > GravitySimulationEngine.collisionDistance(bodies[i], bodies[j]))
            }
        }
    }

    /// With GR off, the figure-eight is periodic: after one period every body is
    /// back where it started (within 1% of the length unit).
    @Test func figureEightIsPeriodicWithoutGR() {
        let config = threeBodyConfig(.figureEight)
        let units = InitialConditions.units(for: .figureEight, config: config)
        let start = NBodyGravity.withAccelerations(
            InitialConditions.threeBody(preset: .figureEight, config: config), grEnabled: false)

        let dt = ThreeBodyPreset.figureEight.timeStep
        let period = figureEightPeriod * units.length / units.velocity
        var bodies = start
        for _ in 0..<Int((period / dt).rounded()) {
            bodies = NBodyGravity.verletStep(bodies, dt: dt, grEnabled: false)
        }

        for (now, then) in zip(bodies, start) {
            #expect((now.position - then.position).magnitude < 0.01 * units.length)
        }
    }

    /// With GR on (as in the app), the figure-eight measurably drifts within one
    /// period but stays a bound, collision-free system.
    @Test func figureEightDriftsWithGRButStaysBound() {
        let config = threeBodyConfig(.figureEight)
        let units = InitialConditions.units(for: .figureEight, config: config)
        let start = InitialConditions.threeBody(preset: .figureEight, config: config)
        let engine = GravitySimulationEngine(bodies: start)

        let dt = ThreeBodyPreset.figureEight.timeStep
        let period = figureEightPeriod * units.length / units.velocity
        for _ in 0..<Int((period / dt).rounded()) {
            engine.step(dt: dt)
        }

        let maxOffset = zip(engine.bodies, start).map { ($0.position - $1.position).magnitude }.max() ?? 0
        #expect(maxOffset > 0.01 * units.length)
        #expect(engine.bodies.count == 3)
        #expect(engine.systemMetrics.collision == nil)
        #expect(engine.systemMetrics.ejectedBodyID == nil)
        #expect(maxPairwiseDistance(engine.bodies) < 2.5 * maxPairwiseDistance(start))
    }

    /// A Routh-stable Lagrange triangle (one dominant mass) rotates rigidly: all
    /// three sides stay within 2% of their initial length over 3 orbits, with GR on.
    @Test func lagrangeTriangleWithDominantMassKeepsShape() {
        let units = InitialConditions.PresetUnits(length: 150, mass: 25)
        let start = NBodyGravity.centerOfMassFrame(
            InitialConditions.lagrange(massMultipliers: [10, 0.1, 0.1], velocityFactor: 1, units: units))
        let engine = GravitySimulationEngine(bodies: start)

        let omega = start[1].velocity.magnitude / start[1].position.magnitude
        let dt = ThreeBodyPreset.lagrangeTriangle.timeStep
        let steps = Int((3 * 2 * Double.pi / omega / dt).rounded())

        for step in 0..<steps {
            engine.step(dt: dt)
            guard step % 50 == 0 else { continue }
            let b = engine.bodies
            for (i, j) in [(0, 1), (1, 2), (0, 2)] {
                let side = (b[i].position - b[j].position).magnitude
                #expect(abs(side - units.length) / units.length < 0.02)
            }
        }
    }

    /// The Pythagorean preset is chaotic but must end in an ejection, not a merge.
    @Test func pythagoreanEndsInEjection() {
        let preset = ThreeBodyPreset.pythagorean
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset)))
        let units = InitialConditions.units(for: preset, config: threeBodyConfig(preset))
        let timeLimit = 80 * units.length / units.velocity

        while engine.systemMetrics.elapsedTime < timeLimit
                && engine.systemMetrics.ejectedBodyID == nil
                && engine.systemMetrics.collision == nil {
            engine.step(dt: preset.timeStep)
        }

        #expect(engine.systemMetrics.collision == nil)
        #expect(engine.systemMetrics.ejectedBodyID != nil)
        #expect(engine.systemMetrics.maxVelocityFractionOfC < 0.5)
    }

    /// The moon stays gravitationally bound to the planet for 10 planetary years.
    @Test func sunPlanetMoonMoonStaysWithPlanet() {
        let preset = ThreeBodyPreset.sunPlanetMoon
        let start = InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset))
        let engine = GravitySimulationEngine(bodies: start)
        let moonDistance = (start[2].position - start[1].position).magnitude
        let year = 2 * Double.pi * CelestialConstants.baseAU / (start[1].velocity - start[0].velocity).magnitude

        #expect(start.map(\.kind) == [.star, .planet, .moon])
        while engine.systemMetrics.elapsedTime < 10 * year {
            engine.step(dt: preset.timeStep)
            let distance = (engine.bodies[2].position - engine.bodies[1].position).magnitude
            if distance < 0.5 * moonDistance || distance > 2 * moonDistance {
                Issue.record("Moon left the planet at t=\(engine.systemMetrics.elapsedTime)")
                break
            }
        }
        #expect(engine.systemMetrics.collision == nil)
    }

    /// Custom with velocity factor 1 and equal masses reproduces the Lagrange preset.
    @Test func customWithDefaultsMatchesLagrange() {
        let custom = InitialConditions.threeBody(preset: .custom, config: threeBodyConfig(.custom))
        let lagrange = InitialConditions.threeBody(preset: .lagrangeTriangle, config: threeBodyConfig(.lagrangeTriangle))
        for (a, b) in zip(custom, lagrange) {
            #expect((a.position - b.position).magnitude < 1e-9)
            #expect((a.velocity - b.velocity).magnitude < 1e-9)
        }
    }

    /// Custom spread scales the triangle and the velocity factor scales speeds.
    @Test func customSlidersScaleGeometryAndVelocity() {
        var config = threeBodyConfig(.custom)
        let base = InitialConditions.threeBody(preset: .custom, config: config)
        config.customSpreadAU = 2
        config.customVelocityFactor = 0.5
        let scaled = InitialConditions.threeBody(preset: .custom, config: config)

        let baseSide = (base[0].position - base[1].position).magnitude
        let scaledSide = (scaled[0].position - scaled[1].position).magnitude
        #expect(abs(scaledSide / baseSide - 2) < 1e-9)
        #expect(scaled[0].velocity.magnitude < base[0].velocity.magnitude)
    }
}

// MARK: - N-Body Engine Tests

struct NBodyEngineTests {

    /// Two bodies on a head-on course plus a distant third: the pair merges,
    /// conserving total mass and momentum; the heavier body's ID survives.
    @Test func mergeConservesMassAndMomentum() {
        let bodies = [
            CelestialBody(id: 0, mass: 40, position: Vector3D(x: -30, y: 0, z: 0),
                          velocity: Vector3D(x: 20, y: 3, z: 0)),
            CelestialBody(id: 1, mass: 10, position: Vector3D(x: 30, y: 0, z: 0),
                          velocity: Vector3D(x: -25, y: 0, z: 1)),
            CelestialBody(id: 2, mass: 5, position: Vector3D(x: 0, y: 2000, z: 0),
                          velocity: Vector3D(x: 1, y: 0, z: 0))
        ]
        let massBefore = NBodyGravity.totalMass(bodies)
        let momentumBefore = NBodyGravity.totalMomentum(bodies)
        let engine = GravitySimulationEngine(bodies: bodies)

        for _ in 0..<5000 where engine.systemMetrics.collision == nil {
            engine.step(dt: 0.01)
        }

        let collision = engine.systemMetrics.collision
        #expect(collision?.0 == 0)
        #expect(collision?.1 == 1)
        #expect(engine.bodies.count == 2)
        #expect(abs(NBodyGravity.totalMass(engine.bodies) - massBefore) < 1e-9)
        #expect((NBodyGravity.totalMomentum(engine.bodies) - momentumBefore).magnitude < 1e-6)
        #expect(engine.systemMetrics.statusLabel == "Merged")
    }

    /// A body launched at twice the escape speed from a binary is flagged as ejected.
    @Test func ejectionDetectedForEscapingBody() {
        let G = GravitySimulationEngine.G
        let binaryMass = 200.0
        let escapeSpeed = sqrt(2 * G * binaryMass / 200)
        let binarySpeed = sqrt(G * 100 / (4 * 25))
        let bodies = NBodyGravity.centerOfMassFrame([
            CelestialBody(id: 0, mass: 100, position: Vector3D(x: 0, y: 25, z: 0),
                          velocity: Vector3D(x: binarySpeed, y: 0, z: 0)),
            CelestialBody(id: 1, mass: 100, position: Vector3D(x: 0, y: -25, z: 0),
                          velocity: Vector3D(x: -binarySpeed, y: 0, z: 0)),
            CelestialBody(id: 2, mass: 1, position: Vector3D(x: 200, y: 0, z: 0),
                          velocity: Vector3D(x: 2 * escapeSpeed, y: 0, z: 0))
        ])
        let engine = GravitySimulationEngine(bodies: bodies)

        for _ in 0..<20000 where engine.systemMetrics.ejectedBodyID == nil {
            engine.step(dt: 0.02)
        }

        #expect(engine.systemMetrics.ejectedBodyID == 2)
        #expect(engine.bodies.count == 3)
        #expect(engine.systemMetrics.statusLabel == "Ejected")
    }

    /// System metrics are populated for a running 3-body system.
    @Test func systemMetricsTrackTimeApproachAndSpeed() {
        let preset = ThreeBodyPreset.figureEight
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset)))
        for _ in 0..<100 {
            engine.step(dt: preset.timeStep)
        }

        let metrics = engine.systemMetrics
        #expect(abs(metrics.elapsedTime - 100 * preset.timeStep) < 1e-9)
        #expect(metrics.closestApproach.isFinite && metrics.closestApproach > 0)
        #expect(metrics.maxVelocityFractionOfC > 0)
        #expect(abs(metrics.energyDrift) < 0.05)
        #expect(metrics.statusLabel == "Bound")
        #expect(engine.bodies.allSatisfy { !$0.trail.isEmpty })
    }

    /// 2-body features (absorption metrics) must not run in a 3-body engine.
    @Test func threeBodyEngineSkipsTwoBodyFeatures() {
        let preset = ThreeBodyPreset.figureEight
        let engine = GravitySimulationEngine(
            bodies: InitialConditions.threeBody(preset: preset, config: threeBodyConfig(preset)))
        engine.step(dt: preset.timeStep)
        #expect(!engine.isTwoBodyScenario)
        #expect(engine.metrics.orbitsCompleted == 0)
        #expect(engine.bleedParticles.isEmpty)
    }

    @Test func letterLabelsFollowIDs() {
        #expect(SystemMetrics.letter(for: 0) == "A")
        #expect(SystemMetrics.letter(for: 2) == "C")
    }
}

// MARK: - ViewModel 3-Body Tests

@MainActor
struct ThreeBodyViewModelTests {

    private let canvas = CGSize(width: 400, height: 300)

    private func makeViewModel(onCreate: @escaping @Sendable (Int) -> Void = { _ in }) -> SimulationViewModel {
        SimulationViewModel { bodies in
            onCreate(bodies.count)
            return MockSimulationEngine(bodies: bodies)
        }
    }

    @Test func threeBodyModeProducesThreeBodies() {
        let vm = makeViewModel()
        vm.config.mode = .threeBody
        vm.setup(canvasSize: canvas)

        #expect(vm.bodyPositions.count == 3)
        #expect(vm.bodyTrails.count == 3)
        #expect(vm.bodyKinds.count == 3)
        #expect(vm.bodyIDs == [0, 1, 2])
        #expect(vm.bodyLabels.count == 3)
    }

    @Test func selectingModeRerunsSetup() {
        final class Counts: @unchecked Sendable { var values: [Int] = [] }
        let counts = Counts()
        let vm = makeViewModel { counts.values.append($0) }
        vm.setup(canvasSize: canvas)

        vm.selectMode(.threeBody, canvasSize: canvas)
        vm.selectMode(.twoBody, canvasSize: canvas)

        #expect(counts.values == [2, 3, 2])
        #expect(vm.bodyPositions.count == 2)
        #expect(vm.config.timeStep == SimulationConfig().timeStep)
    }

    @Test func selectingPresetAppliesIntegrationSettings() {
        let vm = makeViewModel()
        vm.selectMode(.threeBody, canvasSize: canvas)
        vm.selectPreset(.pythagorean, canvasSize: canvas)

        #expect(vm.config.threeBodyPreset == .pythagorean)
        #expect(vm.config.timeStep == ThreeBodyPreset.pythagorean.timeStep)
        #expect(vm.config.stepsPerFrame == ThreeBodyPreset.pythagorean.stepsPerFrame)
        #expect(vm.bodyLabels == ["A 3", "B 4", "C 5"])
    }

    /// With bodies in the x-y plane and positive elevation, depth decreases as
    /// canvas-y increases, so far-to-near order is ascending canvas-y.
    @Test func renderOrderSortsFarToNear() {
        let vm = makeViewModel()
        vm.selectMode(.threeBody, canvasSize: canvas)
        vm.selectPreset(.pythagorean, canvasSize: canvas)

        #expect(vm.renderOrder.sorted() == [0, 1, 2])
        let ys = vm.renderOrder.map { vm.bodyPositions[$0].y }
        #expect(ys == ys.sorted())
    }

    @Test func resetKeepsModeAndPreset() {
        let vm = makeViewModel()
        vm.selectMode(.threeBody, canvasSize: canvas)
        vm.selectPreset(.sunPlanetMoon, canvasSize: canvas)
        vm.config.customVelocityFactor = 1.3

        vm.reset(canvasSize: canvas)

        #expect(vm.config.mode == .threeBody)
        #expect(vm.config.threeBodyPreset == .sunPlanetMoon)
        #expect(vm.config.customVelocityFactor == 1.0)
        #expect(vm.config.timeStep == ThreeBodyPreset.sunPlanetMoon.timeStep)
    }
}
