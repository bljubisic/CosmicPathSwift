//
//  ScaleProfileTests.swift
//  CosmicPathSwiftTests
//
//  Issue #21, PR 1: the constants now travel as a `ScaleProfile` value. The
//  Visual profile must reproduce the original app exactly, down to the bit.
//

import Testing
import Foundation
import CoreGraphics
@testable import CosmicPathSwift

// MARK: - Visual Profile Values

struct VisualScaleProfileTests {
    private let visual = ScaleProfile.visual

    @Test func constantsMatchTheOriginalNumbers() {
        #expect(visual.constants.G == 500)
        #expect(visual.constants.c == 200)
        #expect(visual.constants.cSquared == 40_000)
        #expect(visual.solarMass == 200)
        #expect(visual.earthMass == 5)
        #expect(visual.au == 150)
        #expect(visual.blackHoleBaseMass == 5000)
        #expect(visual.defaultSoftening == 5)
        #expect(visual.units.lengthSymbol == "px")
    }

    @Test func staticAliasesPointAtTheVisualProfile() {
        #expect(GravitySimulationEngine.G == visual.constants.G)
        #expect(GravitySimulationEngine.c == visual.constants.c)
        #expect(GravitySimulationEngine.cSquared == visual.constants.cSquared)
        #expect(GravitySimulationEngine.softening == visual.defaultSoftening)
        #expect(CelestialConstants.baseAU == visual.au)
        #expect(CelestialConstants.baseSolarMass == visual.solarMass)
        #expect(CelestialConstants.baseEarthMass == visual.earthMass)
        #expect(CelestialConstants.blackHoleSolarMass == visual.blackHoleBaseMass)
        #expect(SimulationConfig().scale == visual)
    }

    @Test func schwarzschildRadiusIsMassOverForty() {
        #expect(visual.constants.schwarzschildRadius(mass: 200) == 5)
        #expect(visual.constants.schwarzschildRadius(mass: 5000) == 125)
    }

    @Test func blackHoleRuleNeedsEightPixelsAndBlackHoleMode() {
        let rule = visual.blackHoleRule
        #expect(rule.isBlackHole(schwarzschildRadius: 8, isBlackHoleMode: true))
        #expect(!rule.isBlackHole(schwarzschildRadius: 7.9, isBlackHoleMode: true))
        #expect(!rule.isBlackHole(schwarzschildRadius: 125, isBlackHoleMode: false))
        #expect(BlackHoleRule.byObjectType.isBlackHole(schwarzschildRadius: 1e-9, isBlackHoleMode: true))
    }

    @Test(arguments: [(200.0, 5.0), (2000.0, 5.0), (200.0, 20.0), (40.0, 2.0)])
    func starSurfaceMatchesTheOriginalFormula(mass: Double, softening: Double) {
        let rs = 2.0 * 500 * mass / 40_000
        #expect(visual.starSurfaceRadius(mass: mass, softening: softening) == max(2.0 * rs, softening * 2))
    }

    @Test(arguments: [(200.0, 5.0), (5000.0, 5.0), (200.0, 0.01), (1000.0, 50.0)])
    func rocheLimitMatchesTheOriginalFormula(centralMass: Double, planetMass: Double) {
        let original = 10.0 * pow(2.0 * centralMass / max(planetMass, 0.1), 1.0 / 3.0)
        #expect(visual.rocheLimit(centralMass: centralMass, planetMass: planetMass) == original)
        #expect(GravitySimulationEngine.rocheLimit(centralMass: centralMass, planetMass: planetMass) == original)
    }

    @Test(arguments: [(25.0, 25.0, 5.0), (7.2, 12.0, 5.0), (2000.0, 25.0, 5.0), (25.0, 4000.0, 10.0)])
    func collisionDistanceMatchesTheOriginalFormula(massA: Double, massB: Double, softening: Double) {
        let rsA = 2.0 * 500 * massA / 40_000
        let rsB = 2.0 * 500 * massB / 40_000
        let original = max(2.0 * rsA, 2.0 * rsB, 2.0 * softening)
        #expect(visual.collisionDistance(massA: massA, massB: massB, softening: softening) == original)
    }

    @Test func timeUnitMakesOneAUAroundTheSunTakeAYear() {
        let period = 2 * Double.pi * sqrt(pow(150, 3) / (500 * 200))
        let year = period * visual.units.secondsPerTime
        #expect(abs(year - SIConstants.julianYear) / SIConstants.julianYear < 1e-12)
    }
}

// MARK: - Bit-for-bit Engine Check

/// Verlet with the original force law and literal constants (G = 500,
/// c² = 40,000), copied from the engine before the constants became a
/// parameter. The engine with `.visual` must reproduce it exactly.
private enum OriginalPhysics {
    static func accelerations(_ bodies: [CelestialBody], softening: Double) -> [Vector3D] {
        bodies.indices.map { i in
            bodies.indices.reduce(Vector3D.zero) { total, j in
                guard j != i else { return total }
                let separation = bodies[i].position - bodies[j].position
                let relativeVelocity = bodies[i].velocity - bodies[j].velocity
                let dist = max(separation.magnitude, softening)
                let r2 = dist * dist
                let gm = 500.0 * bodies[j].mass
                let l = separation.cross(relativeVelocity).magnitude
                let aGR = -3.0 * gm * l * l / (40_000.0 * r2 * r2)
                return total + (-gm / r2 + aGR) * separation.normalized
            }
        }
    }

    static func run(_ start: [CelestialBody], dt: Double, steps: Int, softening: Double) -> [CelestialBody] {
        var bodies = zip(start, accelerations(start, softening: softening)).map { body, acc in
            var copy = body
            copy.acceleration = acc
            return copy
        }
        for _ in 0..<steps {
            let drifted = bodies.map { body -> CelestialBody in
                var moved = body
                moved.position = body.position + body.velocity * dt + 0.5 * body.acceleration * (dt * dt)
                return moved
            }
            let newAcc = accelerations(drifted, softening: softening)
            bodies = zip(drifted, newAcc).map { body, acc in
                var kicked = body
                kicked.velocity = body.velocity + 0.5 * (body.acceleration + acc) * dt
                kicked.acceleration = acc
                return kicked
            }
        }
        return bodies
    }
}

struct VisualEngineBitForBitTests {
    private static let steps = 500

    private func expectIdentical(_ engineBodies: [CelestialBody], _ reference: [CelestialBody]) {
        #expect(engineBodies.count == reference.count)
        for (a, b) in zip(engineBodies, reference) {
            #expect(a.position == b.position)
            #expect(a.velocity == b.velocity)
        }
    }

    @Test func twoBodyEngineMatchesTheOriginalPhysics() {
        var config = SimulationConfig()
        config.advanced.initial.eccentricity = 0.3
        config.inclinationDeg = 20
        let start = InitialConditions.twoBody(config: config)
        let engine = GravitySimulationEngine(bodies: start, scale: .visual)
        for _ in 0..<Self.steps { engine.step(dt: config.timeStep) }

        let reference = OriginalPhysics.run(start, dt: config.timeStep, steps: Self.steps, softening: 5)
        expectIdentical(engine.bodies, reference)
    }

    @Test func blackHoleEngineMatchesTheOriginalPhysics() {
        var config = SimulationConfig()
        config.isBlackHoleMode = true
        config.separationAU = 5
        let start = InitialConditions.twoBody(config: config)
        let engine = GravitySimulationEngine(bodies: start, scale: .visual)
        engine.isBlackHoleMode = true
        for _ in 0..<Self.steps { engine.step(dt: config.timeStep) }

        let reference = OriginalPhysics.run(start, dt: config.timeStep, steps: Self.steps, softening: 5)
        expectIdentical(engine.bodies, reference)
        #expect(engine.metrics.isBlackHole)
    }

    @Test func threeBodyEngineMatchesTheOriginalPhysics() {
        let preset = ThreeBodyPreset.figureEight
        let start = InitialConditions.threeBody(preset: preset, config: SimulationConfig())
        let engine = GravitySimulationEngine(bodies: start, scale: .visual)
        for _ in 0..<Self.steps { engine.step(dt: preset.timeStep) }

        let reference = OriginalPhysics.run(start, dt: preset.timeStep, steps: Self.steps, softening: 5)
        expectIdentical(engine.bodies, reference)
    }

    @Test func defaultScaleIsVisual() {
        let start = InitialConditions.twoBody(config: SimulationConfig())
        #expect(GravitySimulationEngine(bodies: start).scale == .visual)
    }
}

// MARK: - Factory Wiring

@MainActor
struct EngineSetupWiringTests {
    private final class ScaleRecorder: @unchecked Sendable {
        var scales: [ScaleProfile?] = []
    }

    @Test func factoryReceivesTheConfigScaleForMainAndTwinEngines() {
        let recorder = ScaleRecorder()
        let vm = SimulationViewModel { setup in
            let engine = MockSimulationEngine(bodies: setup.bodies, scale: setup.scale)
            recorder.scales.append(engine.scale)
            return engine
        }
        vm.config.mode = .threeBody
        vm.config.advanced.initial.chaosEpsilon = 1e-6
        vm.config.advanced.initial.showUnperturbedTwin = true
        vm.setup(canvasSize: CGSize(width: 400, height: 300))
        #expect(recorder.scales.count == 2)
        #expect(recorder.scales.allSatisfy { $0 == .visual })
    }
}

// MARK: - ZoomController

struct ZoomControllerTests {
    private func body(id: Int, x: Double, mass: Double = 1) -> CelestialBody {
        CelestialBody(id: id, kind: .star, mass: mass, position: Vector3D(x: x, y: 0, z: 0), velocity: .zero)
    }

    @Test func resetSizesTheViewFromTheFarthestBody() {
        var zoom = ZoomController()
        let extent = zoom.reset(for: [body(id: 0, x: -100), body(id: 1, x: 100)], fallbackExtent: 150)
        #expect(extent == 100)
        #expect(zoom.minimumExtent == 100 * CelestialConstants.orbitMarginFactor)
        #expect(zoom.maxExtent == zoom.minimumExtent)
        #expect(zoom.centerOfMass == .zero)
    }

    @Test func zoomsOutAtOnceAndBackInGradually() {
        var zoom = ZoomController()
        _ = zoom.reset(for: [body(id: 0, x: -100), body(id: 1, x: 100)], fallbackExtent: 150)
        let far = [body(id: 0, x: -500), body(id: 1, x: 500)]
        let changed = zoom.update(bodies: far, ejectedID: nil, bodyLeft: false, lockZoom: false)
        #expect(changed)
        #expect(zoom.maxExtent == 500 * ZoomController.headroom)

        let near = [body(id: 0, x: -100), body(id: 1, x: 100)]
        _ = zoom.update(bodies: near, ejectedID: nil, bodyLeft: false, lockZoom: false)
        #expect(zoom.maxExtent == 500 * ZoomController.headroom * ZoomController.activeDecayRate)
    }

    @Test func lockZoomKeepsTheExtent() {
        var zoom = ZoomController()
        _ = zoom.reset(for: [body(id: 0, x: -100), body(id: 1, x: 100)], fallbackExtent: 150)
        let before = zoom.maxExtent
        _ = zoom.update(bodies: [body(id: 0, x: -900), body(id: 1, x: 900)],
                        ejectedID: nil, bodyLeft: false, lockZoom: true)
        #expect(zoom.maxExtent == before)
    }

    @Test func ejectedBodyIsIgnored() {
        var zoom = ZoomController()
        let bodies = [body(id: 0, x: -100), body(id: 1, x: 100), body(id: 2, x: 10_000)]
        _ = zoom.reset(for: Array(bodies.prefix(2)), fallbackExtent: 150)
        _ = zoom.update(bodies: bodies, ejectedID: 2, bodyLeft: true, lockZoom: false)
        #expect(zoom.centerOfMass == .zero)
        #expect(zoom.maxExtent == zoom.minimumExtent)
    }

    @Test func emptySystemUsesTheFallbackExtent() {
        var zoom = ZoomController()
        let extent = zoom.reset(for: [], fallbackExtent: 150)
        #expect(extent == 150)
    }
}
