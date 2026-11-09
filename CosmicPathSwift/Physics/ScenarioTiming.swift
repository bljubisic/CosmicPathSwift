//
//  ScenarioTiming.swift
//  CosmicPathSwift
//
//  Converts each scenario's Visual time step to other scales (issue #21, PR 2).
//
//  Scenario time steps (`SimulationConfig.timeStep`, `ThreeBodyPreset.timeStep`)
//  were tuned in Visual units. The Realistic scale runs the same scenario at a
//  different size and mass, so its natural time unit differs. The time ratio
//  is the fastest pair's dynamical time in the scale ÷ the same in Visual;
//  multiplying `dt` by it keeps the same number of steps per orbit, and so the
//  same accuracy.
//

import Foundation

enum ScenarioTiming {

    /// Fastest pair's dynamical time: the minimum over pairs of 1/ω for a
    /// circular orbit at the pair's separation under the app's force law,
    ///     1/ω = √(r²(r − 3GM/c²) / GM),   M = mᵢ + mⱼ
    /// (√(r³/GM) when GR is weak). The GR factor matters in Visual, where it
    /// shortens a 1 AU orbit by 2.5%; without it the scales would differ in
    /// steps per orbit. r − 3GM/c² is floored at 0.1 r like the circular speed.
    ///
    /// For 2-body it is the orbit itself; for Sun–Earth–Moon the Earth–Moon pair.
    /// Returns 0 for fewer than two bodies or degenerate pairs.
    static func referenceTime(bodies: [CelestialBody], constants: PhysicalConstants) -> Double {
        var fastest = Double.infinity
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let distance = (bodies[i].position - bodies[j].position).magnitude
                let gm = constants.G * (bodies[i].mass + bodies[j].mass)
                guard distance > 0, gm > 0 else { continue }
                let grShortened = max(distance - 3 * gm / constants.cSquared, distance * minimumGRFactor)
                fastest = min(fastest, sqrt(distance * distance * grShortened / gm))
            }
        }
        return fastest.isFinite ? fastest : 0
    }

    /// Floor of (r − 3GM/c²)/r, matching `InitialConditions.SunPlanetMoon.circularSpeed`.
    private static let minimumGRFactor: Double = 0.1

    /// Time-unit ratio of `config`'s scale to Visual. Exactly 1 in Visual, so
    /// the Visual scale is untouched.
    static func timeRatio(config: SimulationConfig) -> Double {
        guard config.advanced.scale != .visual else { return 1 }
        if config.isStrongField { return strongFieldTimeRatio(config: config) }
        var visualConfig = config
        visualConfig.advanced.scale = .visual
        visualConfig.isBlackHoleMode = false
        var scaledConfig = config
        scaledConfig.isBlackHoleMode = false

        let scaled = referenceTime(bodies: initialBodies(config: scaledConfig), constants: config.scale.constants)
        let visual = referenceTime(bodies: initialBodies(config: visualConfig), constants: ScaleProfile.visual.constants)
        guard scaled > 0, visual > 0 else { return 1 }
        return scaled / visual
    }

    /// Strong field has no matching Visual scenario, so its baseline is the
    /// Visual default 2-body orbit (same Advanced starting conditions). The
    /// ratio keeps Visual's steps per orbit: ≈ 10 µs per step at 8 rₛ around 10 M☉.
    private static func strongFieldTimeRatio(config: SimulationConfig) -> Double {
        var baseline = SimulationConfig()
        baseline.advanced.initial = config.advanced.initial
        let scaled = referenceTime(bodies: initialBodies(config: config), constants: config.scale.constants)
        let visual = referenceTime(bodies: initialBodies(config: baseline), constants: ScaleProfile.visual.constants)
        guard scaled > 0, visual > 0 else { return 1 }
        return scaled / visual
    }

    /// Simulated time between 2-body trail points when it shouldn't follow the
    /// time step, or nil for the default spacing (one default step × time ratio).
    ///
    /// S2's step resolves its fast periapsis passage (e = 0.884, ≈ 44,500 steps
    /// per orbit against Visual's ≈ 1,800), so a step-spaced trail would cover
    /// only ~2% of the orbit (issue #27). S2 instead records one point per
    /// period / `DisplaySettings.baseTrailPoints`: the default trail traces one
    /// full orbit.
    ///
    /// The period is Kepler's 2π√(a³/G(M + m)) for the scenario's semi-major
    /// axis, which the run matches to 0.5%. Osculating elements of the starting
    /// state would overestimate it by ~2%: S2 starts at periapsis with the
    /// GR-corrected speed that makes a(1 + e) the other turning point, and at
    /// e = 0.884 the Newtonian a is very sensitive to that speed.
    static func trailSampleInterval(config: SimulationConfig) -> Double? {
        guard config.mode == .twoBody, config.isGalacticCenter else { return nil }
        let gm = config.scale.constants.G * (config.simulationMass1 + config.simulationMass2)
        let semiMajorAxis = config.simulationSeparation
        guard gm > 0, semiMajorAxis > 0 else { return nil }
        let period = 2 * .pi * sqrt(semiMajorAxis * semiMajorAxis * semiMajorAxis / gm)
        return period / Double(DisplaySettings.baseTrailPoints)
    }

    /// Unperturbed starting bodies of `config`'s scenario.
    private static func initialBodies(config: SimulationConfig) -> [CelestialBody] {
        switch config.mode {
        case .twoBody:
            return InitialConditions.twoBody(config: config)
        case .threeBody:
            return InitialConditions.threeBody(preset: config.threeBodyPreset, config: config, applyingNudge: false)
        }
    }
}

// MARK: - ScaleComparison

/// How much stronger GR is in the Visual scale than in reality.
enum ScaleComparison {

    /// (GM/c²L) in Visual ÷ (GM/c²L) in reality for the current scenario.
    ///
    /// 2-body uses the central body and 1 AU, so Black Hole Mode (25× heavier
    /// in Visual) shows its larger factor; 3-body uses the preset's units.
    /// About 1.69×10⁶ for a 1 M☉ star.
    static func grMagnification(config: SimulationConfig) -> Double {
        var visual = config
        visual.advanced.scale = .visual
        var real = config
        real.advanced.scale = .realistic
        real.isBlackHoleMode = false

        let visualCompactness: Double
        let realCompactness: Double
        switch config.mode {
        case .twoBody:
            visualCompactness = compactness(mass: visual.simulationMass1, length: visual.scale.au, visual.scale)
            realCompactness = compactness(mass: real.simulationMass1, length: real.scale.au, real.scale)
        case .threeBody:
            let visualUnits = InitialConditions.units(for: config.threeBodyPreset, config: visual)
            let realUnits = InitialConditions.units(for: config.threeBodyPreset, config: real)
            visualCompactness = compactness(mass: visualUnits.mass, length: visualUnits.length, visual.scale)
            realCompactness = compactness(mass: realUnits.mass, length: realUnits.length, real.scale)
        }
        return realCompactness > 0 ? visualCompactness / realCompactness : 0
    }

    /// GM/(c²L), the dimensionless strength of GR at distance L from mass M.
    private static func compactness(mass: Double, length: Double, _ scale: ScaleProfile) -> Double {
        guard length > 0 else { return 0 }
        return scale.constants.G * mass / (scale.constants.cSquared * length)
    }
}
