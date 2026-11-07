//
//  IntegratorTests.swift
//  CosmicPathSwiftTests
//
//  Selectable integrators (issue #20, PR 5): convergence order against an
//  exact circular orbit, long-run energy behaviour, momentum conservation,
//  and bit-for-bit compatibility of the default with the original Verlet step.
//

import Testing
import Foundation
@testable import CosmicPathSwift

struct IntegratorTests {
    private let G = GravitySimulationEngine.G
    private let cSquared = GravitySimulationEngine.cSquared
    private let softening = GravitySimulationEngine.softening

    /// Mass of each body in the two-body test orbits.
    private let mass = 100.0
    /// Separation of the circular orbit (well above the softening length).
    private let separation = 100.0

    // MARK: - Fixtures

    /// Two equal masses on a circular orbit about the origin, in the CoM frame.
    ///
    /// The relative orbit moves like a test particle around M = 2m. Under the
    /// app's force law a circular orbit of radius d needs v² = GM / (d − 3GM/c²)
    /// (with GR off, the c² term is absent). Returns the bodies and the period.
    private func circularOrbit(grEnabled: Bool) -> ([CelestialBody], Double) {
        let gm = G * 2 * mass
        let grShift = grEnabled ? 3 * gm / cSquared : 0
        let relativeSpeed = sqrt(gm / (separation - grShift))
        let bodies = pair(halfSeparation: separation / 2, halfSpeed: relativeSpeed / 2)
        return (prepared(bodies, grEnabled: grEnabled), 2 * .pi * separation / relativeSpeed)
    }

    /// Two equal masses starting at apoapsis of a Newtonian ellipse of eccentricity e.
    private func eccentricOrbit(eccentricity e: Double) -> ([CelestialBody], Double) {
        let gm = G * 2 * mass
        let apoapsisSpeed = sqrt(gm * (1 - e) / separation)
        let semiMajorAxis = separation / (1 + e)
        let bodies = pair(halfSeparation: separation / 2, halfSpeed: apoapsisSpeed / 2)
        return (prepared(bodies, grEnabled: false), 2 * .pi * sqrt(pow(semiMajorAxis, 3) / gm))
    }

    private func pair(halfSeparation: Double, halfSpeed: Double) -> [CelestialBody] {
        [
            CelestialBody(id: 0, kind: .star, mass: mass, position: Vector3D(x: halfSeparation, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: halfSpeed, z: 0)),
            CelestialBody(id: 1, kind: .star, mass: mass, position: Vector3D(x: -halfSeparation, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: -halfSpeed, z: 0))
        ]
    }

    /// Bodies with `acceleration` = a(t), as every integrator expects on entry.
    private func prepared(_ bodies: [CelestialBody], grEnabled: Bool) -> [CelestialBody] {
        NBodyGravity.withAccelerations(bodies, softening: softening, grEnabled: grEnabled)
    }

    /// Integrates `steps` steps of size `dt` and returns the final bodies.
    private func run(
        _ kind: IntegratorKind, _ bodies: [CelestialBody], dt: Double, steps: Int, grEnabled: Bool
    ) -> [CelestialBody] {
        (0..<steps).reduce(bodies) { state, _ in
            kind.step(state, dt: dt, softening: softening, grEnabled: grEnabled)
        }
    }

    /// Largest position error after one period, when the bodies should be back at the start.
    private func errorAfterOnePeriod(_ kind: IntegratorKind, stepsPerPeriod: Int, grEnabled: Bool) -> Double {
        let (initial, period) = circularOrbit(grEnabled: grEnabled)
        let final = run(kind, initial, dt: period / Double(stepsPerPeriod), steps: stepsPerPeriod, grEnabled: grEnabled)
        return zip(initial, final).map { ($0.position - $1.position).magnitude }.max() ?? 0
    }

    /// Error ratio when the step is halved: ≈ 2^order.
    private func convergenceRatio(_ kind: IntegratorKind, grEnabled: Bool = false) -> Double {
        errorAfterOnePeriod(kind, stepsPerPeriod: 64, grEnabled: grEnabled)
            / errorAfterOnePeriod(kind, stepsPerPeriod: 128, grEnabled: grEnabled)
    }

    // MARK: - Convergence Order

    @Test func verletIsSecondOrder() {
        let ratio = convergenceRatio(.velocityVerlet)
        #expect((3...5).contains(ratio), "ratio \(ratio)")
    }

    @Test(arguments: [IntegratorKind.rk4, .yoshida4])
    func fourthOrderIntegrators(kind: IntegratorKind) {
        let ratio = convergenceRatio(kind)
        #expect((12...20).contains(ratio), "\(kind) ratio \(ratio)")
    }

    /// RK4 evaluates the velocity-dependent GR force at every stage, so it stays 4th-order with GR on.
    @Test func rk4StaysFourthOrderWithGR() {
        let ratio = convergenceRatio(.rk4, grEnabled: true)
        #expect((12...20).contains(ratio), "ratio \(ratio)")
    }

    // MARK: - Energy Behaviour

    /// |ΔE/E| sampled once per step, grouped per orbit (max within each orbit).
    private func energyErrorPerOrbit(_ kind: IntegratorKind, orbits: Int, stepsPerOrbit: Int) -> [Double] {
        let (initial, period) = eccentricOrbit(eccentricity: 0.5)
        let dt = period / Double(stepsPerOrbit)
        let e0 = NBodyGravity.newtonianEnergy(initial, softening: softening)
        var state = initial
        var perOrbit: [Double] = []
        for _ in 0..<orbits {
            var worst = 0.0
            for _ in 0..<stepsPerOrbit {
                state = kind.step(state, dt: dt, softening: softening, grEnabled: false)
                let drift = abs((NBodyGravity.newtonianEnergy(state, softening: softening) - e0) / e0)
                worst = max(worst, drift)
            }
            perOrbit.append(worst)
        }
        return perOrbit
    }

    /// Symplectic: the energy error oscillates but does not grow.
    @Test func verletEnergyErrorStaysBounded() {
        let errors = energyErrorPerOrbit(.velocityVerlet, orbits: 50, stepsPerOrbit: 200)
        let early = errors.prefix(5).max() ?? 0
        let late = errors.suffix(5).max() ?? 0
        #expect(early > 0)
        #expect(late < 2 * early, "early \(early), late \(late)")
    }

    /// Not symplectic: the energy error keeps growing with time.
    @Test func rk4EnergyErrorDrifts() {
        let errors = energyErrorPerOrbit(.rk4, orbits: 50, stepsPerOrbit: 200)
        #expect(errors[49] > 3 * errors[4], "orbit 5 \(errors[4]), orbit 50 \(errors[49])")
    }

    // MARK: - Compatibility & Conservation

    /// Three well-separated bodies that neither merge nor escape in 100 steps.
    private var threeBodies: [CelestialBody] {
        NBodyGravity.centerOfMassFrame([
            CelestialBody(id: 0, kind: .star, mass: 120, position: Vector3D(x: 100, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: 12, z: 1)),
            CelestialBody(id: 1, kind: .star, mass: 80, position: Vector3D(x: -60, y: 50, z: 0),
                          velocity: Vector3D(x: -8, y: -6, z: 0)),
            CelestialBody(id: 2, kind: .star, mass: 100, position: Vector3D(x: -40, y: -90, z: 10),
                          velocity: Vector3D(x: 9, y: -3, z: -1))
        ])
    }

    /// Default settings must reproduce the original Velocity-Verlet engine exactly.
    @Test func defaultEngineMatchesOriginalVerletBitForBit() {
        let engine = GravitySimulationEngine(bodies: threeBodies)
        var reference = NBodyGravity.withAccelerations(threeBodies)
        for _ in 0..<100 {
            engine.step(dt: 0.01)
            reference = NBodyGravity.verletStep(reference, dt: 0.01)
        }
        #expect(engine.bodies.map(\.position) == reference.map(\.position))
        #expect(engine.bodies.map(\.velocity) == reference.map(\.velocity))
    }

    @Test(arguments: IntegratorKind.allCases)
    func netMomentumStaysZero(kind: IntegratorKind) {
        let initial = prepared(threeBodies, grEnabled: true)
        let final = run(kind, initial, dt: 0.01, steps: 200, grEnabled: true)
        let scale = final.reduce(0) { $0 + $1.mass * $1.velocity.magnitude }
        #expect(NBodyGravity.totalMomentum(final).magnitude < 1e-9 * scale)
    }

    /// The three Yoshida sub-steps must add up to one full step.
    @Test func yoshidaWeightsSumToOne() {
        let w = IntegratorKind.yoshidaWeights
        #expect(abs(w.outer * 2 + w.middle - 1) < 1e-12)
        #expect(w.middle < 0)
    }

    @Test func forceEvaluationsPerStep() {
        #expect(IntegratorKind.velocityVerlet.forceEvaluationsPerStep == 1)
        #expect(IntegratorKind.yoshida4.forceEvaluationsPerStep == 3)
        #expect(IntegratorKind.rk4.forceEvaluationsPerStep == 4)
    }

    /// RK4 stores a(t+dt) so the acceleration arrows stay correct.
    @Test func rk4StoresAccelerationAtEndOfStep() {
        let initial = prepared(threeBodies, grEnabled: true)
        let stepped = IntegratorKind.rk4.step(initial, dt: 0.01, softening: softening)
        let expected = NBodyGravity.accelerations(of: stepped, softening: softening)
        #expect(stepped.map(\.acceleration) == expected)
    }
}
