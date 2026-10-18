//
//  NBodyGravityTests.swift
//  CosmicPathSwiftTests
//
//  Unit tests for the stateless N-body gravity helpers: pairwise GR-corrected
//  accelerations, conservation helpers, and the Velocity-Verlet step.
//

import Testing
import Foundation
@testable import CosmicPathSwift

struct NBodyGravityTests {

    private let G = GravitySimulationEngine.G

    /// A deliberately asymmetric 3-body configuration with no special symmetry.
    private var scatteredBodies: [CelestialBody] {
        [
            CelestialBody(id: 0, mass: 30, position: Vector3D(x: 10, y: -40, z: 5),
                          velocity: Vector3D(x: 3, y: 1, z: 0)),
            CelestialBody(id: 1, mass: 50, position: Vector3D(x: -70, y: 20, z: -8),
                          velocity: Vector3D(x: -1, y: 4, z: 2)),
            CelestialBody(id: 2, mass: 12, position: Vector3D(x: 45, y: 90, z: 0),
                          velocity: Vector3D(x: 0, y: -6, z: 1))
        ]
    }

    // MARK: - Accelerations

    /// Newton's third law: with GR off, Σ mᵢaᵢ = 0 for any configuration.
    @Test func newtonsThirdLawHoldsWithGROff() {
        let bodies = scatteredBodies
        let accelerations = NBodyGravity.accelerations(of: bodies, grEnabled: false)
        let netForce = zip(bodies, accelerations).reduce(Vector3D.zero) { sum, pair in
            sum + pair.0.mass * pair.1
        }
        #expect(netForce.magnitude < 1e-9)
    }

    /// With two bodies and GR off, the result is plain Newtonian gravity GM/r².
    @Test func twoBodyAccelerationIsNewtonianWithGROff() {
        let bodies = [
            CelestialBody(mass: 200, position: .zero, velocity: .zero),
            CelestialBody(mass: 5, position: Vector3D(x: 150, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: 25, z: 0))
        ]
        let acc = NBodyGravity.accelerations(of: bodies, grEnabled: false)
        #expect(abs(acc[1].x - (-G * 200 / (150 * 150))) < 1e-12)
        #expect(abs(acc[0].x - (G * 5 / (150 * 150))) < 1e-12)
    }

    /// With a stationary source, the orbiter's acceleration must equal the original
    /// single-pair Schwarzschild formula a = (−GM/r² − 3GML²/(c²r⁴)) r̂.
    @Test func twoBodyAccelerationMatchesOriginalFormula() {
        let r = 150.0, v = 25.0, mass = 200.0
        let bodies = [
            CelestialBody(mass: mass, position: .zero, velocity: .zero),
            CelestialBody(mass: 5, position: Vector3D(x: r, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: v, z: 0))
        ]
        let acc = NBodyGravity.accelerations(of: bodies)
        let L = r * v
        let expected = -G * mass / (r * r)
            - 3 * G * mass * L * L / (GravitySimulationEngine.cSquared * pow(r, 4))
        #expect(abs(acc[1].x - expected) < 1e-12)
        #expect(abs(acc[1].y) < 1e-12)
    }

    /// The GR term uses relative velocity, so boosting every body by the same
    /// velocity must not change any acceleration (Galilean frame independence).
    @Test func accelerationsAreBoostInvariant() {
        let bodies = scatteredBodies
        let boost = Vector3D(x: 40, y: -25, z: 10)
        let boosted = bodies.map { body -> CelestialBody in
            var copy = body
            copy.velocity = body.velocity + boost
            return copy
        }
        let original = NBodyGravity.accelerations(of: bodies)
        let shifted = NBodyGravity.accelerations(of: boosted)
        for (a, b) in zip(original, shifted) {
            #expect((a - b).magnitude < 1e-12)
        }
    }

    /// The GR correction always adds extra attraction for a tangentially moving body.
    @Test func grCorrectionStrengthensAttraction() {
        let separation = Vector3D(x: 100, y: 0, z: 0)
        let relVelocity = Vector3D(x: 0, y: 30, z: 0)
        let withGR = NBodyGravity.pairAcceleration(
            sourceMass: 200, separation: separation, relativeVelocity: relVelocity)
        let withoutGR = NBodyGravity.pairAcceleration(
            sourceMass: 200, separation: separation, relativeVelocity: relVelocity, grEnabled: false)
        #expect(withGR.x < withoutGR.x)
        #expect(withoutGR.x < 0)
    }

    /// Distances below the softening length are clamped so the force stays finite.
    @Test func softeningKeepsForceFinite() {
        let acc = NBodyGravity.pairAcceleration(
            sourceMass: 200,
            separation: Vector3D(x: 0.001, y: 0, z: 0),
            relativeVelocity: .zero
        )
        let soft = GravitySimulationEngine.softening
        #expect(abs(acc.x - (-G * 200 / (soft * soft))) < 1e-9)
    }

    // MARK: - Conservation Helpers

    @Test func centerOfMassIsMassWeighted() {
        let bodies = [
            CelestialBody(mass: 3, position: Vector3D(x: 0, y: 0, z: 0), velocity: .zero),
            CelestialBody(mass: 1, position: Vector3D(x: 4, y: 8, z: -4), velocity: .zero)
        ]
        let com = NBodyGravity.centerOfMass(bodies)
        #expect(abs(com.x - 1) < 1e-12)
        #expect(abs(com.y - 2) < 1e-12)
        #expect(abs(com.z + 1) < 1e-12)
    }

    @Test func totalMomentumSumsMassTimesVelocity() {
        let bodies = [
            CelestialBody(mass: 2, position: .zero, velocity: Vector3D(x: 1, y: 0, z: 0)),
            CelestialBody(mass: 3, position: .zero, velocity: Vector3D(x: 0, y: -2, z: 1))
        ]
        let p = NBodyGravity.totalMomentum(bodies)
        #expect(p == Vector3D(x: 2, y: -6, z: 3))
    }

    /// Two equal masses at rest a distance d apart: E = −G m² / d.
    @Test func newtonianEnergyOfStaticPair() {
        let bodies = [
            CelestialBody(mass: 10, position: .zero, velocity: .zero),
            CelestialBody(mass: 10, position: Vector3D(x: 50, y: 0, z: 0), velocity: .zero)
        ]
        let energy = NBodyGravity.newtonianEnergy(bodies)
        #expect(abs(energy - (-G * 100 / 50)) < 1e-9)
    }

    /// Kinetic term: a free body with no partners has E = ½mv².
    @Test func newtonianEnergyIncludesKineticTerm() {
        let body = CelestialBody(mass: 4, position: .zero, velocity: Vector3D(x: 3, y: 4, z: 0))
        #expect(abs(NBodyGravity.newtonianEnergy([body]) - 50) < 1e-12)
    }

    /// L = Σ m (r × v): a single body at (r,0,0) moving with (0,v,0) has L = m·r·v ẑ.
    @Test func angularMomentumOfCircularMotion() {
        let body = CelestialBody(mass: 2, position: Vector3D(x: 10, y: 0, z: 0),
                                 velocity: Vector3D(x: 0, y: 5, z: 0))
        let L = NBodyGravity.angularMomentum([body])
        #expect(abs(L.z - 100) < 1e-12)
        #expect(abs(L.x) < 1e-12 && abs(L.y) < 1e-12)
    }

    /// Shifting to the CoM frame puts the CoM at the origin with zero net momentum
    /// while preserving relative positions and velocities.
    @Test func centerOfMassFrameRemovesDriftAndOffset() {
        let shifted = NBodyGravity.centerOfMassFrame(scatteredBodies)
        #expect(NBodyGravity.centerOfMass(shifted).magnitude < 1e-9)
        #expect(NBodyGravity.totalMomentum(shifted).magnitude < 1e-9)

        let originalGap = scatteredBodies[1].position - scatteredBodies[0].position
        let shiftedGap = shifted[1].position - shifted[0].position
        #expect((originalGap - shiftedGap).magnitude < 1e-9)
    }

    // MARK: - Integrator

    /// Velocity-Verlet with GR off conserves momentum to round-off and energy closely.
    @Test func verletStepConservesMomentumAndEnergy() {
        // Circular equal-mass binary (separation 100) plus a light outer body at r = 400.
        // ω² = G·200/100³ → v = ω·50 for each binary member; outer v = √(G·200/400).
        let binarySpeed = sqrt(G * 200 / 1e6) * 50
        let outerSpeed = sqrt(G * 200 / 400)
        let triple = [
            CelestialBody(mass: 100, position: Vector3D(x: 50, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: binarySpeed, z: 0)),
            CelestialBody(mass: 100, position: Vector3D(x: -50, y: 0, z: 0),
                          velocity: Vector3D(x: 0, y: -binarySpeed, z: 0)),
            CelestialBody(mass: 1, position: Vector3D(x: 0, y: 400, z: 0),
                          velocity: Vector3D(x: -outerSpeed, y: 0, z: 0))
        ]
        var bodies = NBodyGravity.centerOfMassFrame(triple)
        bodies = NBodyGravity.withAccelerations(bodies, grEnabled: false)
        let e0 = NBodyGravity.newtonianEnergy(bodies)

        for _ in 0..<2000 {
            bodies = NBodyGravity.verletStep(bodies, dt: 0.01, grEnabled: false)
        }

        #expect(NBodyGravity.totalMomentum(bodies).magnitude < 1e-8)
        let drift = abs(NBodyGravity.newtonianEnergy(bodies) - e0) / abs(e0)
        #expect(drift < 1e-3)
    }
}
