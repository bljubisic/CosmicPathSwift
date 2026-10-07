//
//  GravitySimulationEngine+ThreeBody.swift
//  CosmicPathSwift
//
//  N-body features used whenever the engine is created with a body count
//  other than two: inelastic merges, ejection detection, time-sampled trails,
//  and system-wide metrics.
//
//  ## Collisions
//
//  Two bodies merge when they come within max(2rₛᵢ, 2rₛⱼ, 2·softening) of each
//  other. The merge is perfectly inelastic: the heavier body survives (keeping
//  its ID, kind, and trail) with the summed mass, the momentum-weighted velocity,
//  and the pair's CoM position. Total mass and momentum are conserved exactly.
//
//  ## Ejection
//
//  A body counts as ejected once it is more than 4× the initial system extent
//  from the CoM of the remaining bodies *and* its specific Newtonian energy
//  relative to them is positive (it can never come back). Only the first
//  ejection is recorded; the body keeps moving afterwards.
//

import Foundation

extension GravitySimulationEngine {

    // MARK: - Tuning Constants

    /// Ejection distance threshold, in multiples of the initial system extent.
    static let ejectionExtentMultiple: Double = 4.0

    /// Trail points recorded per dynamical time √(R³/GM) of the initial system.
    /// Sampling by simulated time (not per step) keeps trails comparable across
    /// presets whose time steps differ by more than an order of magnitude.
    static let trailSamplesPerDynamicalTime: Double = 100

    // MARK: - State

    /// Bookkeeping used only by the N-body scenario.
    struct NBodyState {
        /// Newtonian energy at t = 0, the baseline for ΔE/E₀.
        let initialEnergy: Double
        /// Largest distance of any body from the CoM at t = 0.
        let initialExtent: Double
        /// Simulated time between trail samples.
        let trailSampleInterval: Double
        /// Simulated time since the last trail sample.
        var timeSinceTrailSample: Double = 0
        /// Sum of the Newtonian energy changes caused by inelastic merges, so they
        /// can be excluded from the drift metric.
        var mergeEnergyChange: Double = 0

        init(bodies: [CelestialBody]) {
            let com = NBodyGravity.centerOfMass(bodies)
            let extent = bodies.map { ($0.position - com).magnitude }.max() ?? 0
            let mass = NBodyGravity.totalMass(bodies)
            initialEnergy = NBodyGravity.newtonianEnergy(bodies)
            initialExtent = extent

            if extent > 0 && mass > 0 {
                let dynamicalTime = sqrt(extent * extent * extent / (GravitySimulationEngine.G * mass))
                trailSampleInterval = dynamicalTime / GravitySimulationEngine.trailSamplesPerDynamicalTime
            } else {
                trailSampleInterval = 0
            }
        }
    }

    // MARK: - Step

    /// One N-body step: integrate, merge colliding bodies, sample trails,
    /// detect ejection, and refresh `systemMetrics`.
    func stepNBody(dt: Double) {
        integrate(dt: dt)
        systemMetrics.elapsedTime += dt
        resolveCollision()
        recordTrailsIfDue(dt: dt)
        detectEjection()
        updateSystemMetrics()
    }

    // MARK: - Collisions

    /// Distance at which two bodies merge: max(2rₛᵢ, 2rₛⱼ, 2·softening).
    static func collisionDistance(_ a: CelestialBody, _ b: CelestialBody) -> Double {
        let rsA = 2.0 * G * a.mass / cSquared
        let rsB = 2.0 * G * b.mass / cSquared
        return max(2.0 * rsA, 2.0 * rsB, 2.0 * softening)
    }

    /// Merges the first colliding pair found (at most one merge per step).
    private func resolveCollision() {
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let distance = (bodies[i].position - bodies[j].position).magnitude
                if distance <= Self.collisionDistance(bodies[i], bodies[j]) {
                    merge(i, j)
                    return
                }
            }
        }
    }

    /// Replaces bodies i and j with a single inelastically merged body.
    private func merge(_ i: Int, _ j: Int) {
        let energyBefore = NBodyGravity.newtonianEnergy(bodies)
        let (survivorIndex, absorbedIndex) = bodies[i].mass >= bodies[j].mass ? (i, j) : (j, i)
        let survivor = bodies[survivorIndex]
        let absorbed = bodies[absorbedIndex]

        let pair = [survivor, absorbed]
        var merged = survivor
        merged.mass = NBodyGravity.totalMass(pair)
        merged.position = NBodyGravity.centerOfMass(pair)
        merged.velocity = NBodyGravity.totalMomentum(pair) * (1.0 / merged.mass)

        var remaining = bodies
        remaining[survivorIndex] = merged
        remaining.remove(at: absorbedIndex)
        bodies = NBodyGravity.withAccelerations(remaining)

        nBodyState.mergeEnergyChange += NBodyGravity.newtonianEnergy(bodies) - energyBefore
        systemMetrics.collision = (survivor.id, absorbed.id)
    }

    // MARK: - Trails

    /// Appends trail points once per `trailSampleInterval` of simulated time.
    private func recordTrailsIfDue(dt: Double) {
        nBodyState.timeSinceTrailSample += dt
        guard nBodyState.timeSinceTrailSample >= nBodyState.trailSampleInterval else { return }
        nBodyState.timeSinceTrailSample = 0
        appendTrailPoints()
    }

    // MARK: - Ejection

    /// Records the first body that is far away and unbound from the others.
    private func detectEjection() {
        guard systemMetrics.ejectedBodyID == nil, bodies.count >= 2 else { return }
        let threshold = Self.ejectionExtentMultiple * nBodyState.initialExtent

        for i in bodies.indices {
            let others = bodies.indices.filter { $0 != i }.map { bodies[$0] }
            let othersMass = NBodyGravity.totalMass(others)
            guard othersMass > 0 else { continue }

            let offset = bodies[i].position - NBodyGravity.centerOfMass(others)
            let distance = offset.magnitude
            guard distance > threshold else { continue }

            let othersVelocity = NBodyGravity.totalMomentum(others) * (1.0 / othersMass)
            let relativeSpeed = (bodies[i].velocity - othersVelocity).magnitude
            let specificEnergy = 0.5 * relativeSpeed * relativeSpeed - Self.G * othersMass / distance
            if specificEnergy > 0 {
                systemMetrics.ejectedBodyID = bodies[i].id
                return
            }
        }
    }

    // MARK: - Metrics

    /// Refreshes energy drift, closest approach, and peak speed.
    func updateSystemMetrics() {
        let initialEnergy = nBodyState.initialEnergy
        if initialEnergy != 0 {
            let energy = NBodyGravity.newtonianEnergy(bodies) - nBodyState.mergeEnergyChange
            systemMetrics.energyDrift = (energy - initialEnergy) / abs(initialEnergy)
        }

        for i in bodies.indices {
            let speedFraction = bodies[i].velocity.magnitude / Self.c
            systemMetrics.maxVelocityFractionOfC = max(systemMetrics.maxVelocityFractionOfC, speedFraction)
            for j in bodies.indices where j > i {
                let distance = (bodies[i].position - bodies[j].position).magnitude
                systemMetrics.closestApproach = min(systemMetrics.closestApproach, distance)
            }
        }
    }
}
