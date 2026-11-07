//
//  RandomLayoutTests.swift
//  CosmicPathSwiftTests
//
//  The seeded generator and the Custom preset's Random layout
//  (issue #20, PR 4).
//

import Testing
import Foundation
@testable import CosmicPathSwift

struct SeededGeneratorTests {

    /// Reference output of SplitMix64 for seed 0.
    @Test func matchesReferenceSplitMix64() {
        var generator = SeededGenerator(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
    }

    @Test func sameSeedGivesSameSequence() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            #expect(first.next() == second.next())
        }
    }

    @Test func unitValuesStayInRange() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<1000 {
            let value = generator.nextUnit()
            #expect(value >= 0 && value < 1)
        }
    }
}

struct RandomLayoutTests {

    private let units = InitialConditions.PresetUnits(length: 150, mass: 25)
    private let masses = [1.0, 2.0, 0.5]

    private func layout(seed: UInt64, velocityFactor: Double = 1) -> [CelestialBody] {
        InitialConditions.randomLayout(massMultipliers: masses, seed: seed,
                                       velocityFactor: velocityFactor, units: units)
    }

    @Test func sameSeedGivesTheSameLayout() {
        let first = layout(seed: 123)
        let second = layout(seed: 123)
        #expect(first.map(\.position) == second.map(\.position))
        #expect(first.map(\.velocity) == second.map(\.velocity))
    }

    @Test func differentSeedsGiveDifferentLayouts() {
        #expect(layout(seed: 1).map(\.position) != layout(seed: 2).map(\.position))
    }

    @Test(arguments: 1...20)
    func layoutIsBoundAndInTheCenterOfMassFrame(seed: Int) {
        let bodies = layout(seed: UInt64(seed))
        #expect(NBodyGravity.centerOfMass(bodies).magnitude < 1e-9)
        #expect(NBodyGravity.totalMomentum(bodies).magnitude < 1e-9)
        #expect(NBodyGravity.newtonianEnergy(bodies) < 0)
    }

    @Test(arguments: 1...20)
    func bodiesStartWellSeparated(seed: Int) {
        let bodies = layout(seed: UInt64(seed))
        let minimum = InitialConditions.randomLayoutMinimumSeparation * units.length
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                #expect((bodies[i].position - bodies[j].position).magnitude >= minimum - 1e-9)
            }
        }
    }

    @Test func keepsTheUsersMasses() {
        #expect(layout(seed: 9).map(\.mass) == masses.map { $0 * units.mass })
    }

    @Test func velocityFactorScalesTheSpeeds() {
        let normal = layout(seed: 5)
        let slower = layout(seed: 5, velocityFactor: 0.5)
        for (a, b) in zip(normal, slower) {
            #expect(abs(b.velocity.magnitude - 0.5 * a.velocity.magnitude) < 1e-9)
        }
    }

    @Test func customPresetUsesTheChosenLayout() {
        var config = SimulationConfig()
        config.mode = .threeBody
        config.threeBodyPreset = .custom
        let triangle = InitialConditions.threeBody(preset: .custom, config: config)

        config.advanced.initial.customLayout = .random
        config.advanced.initial.customSeed = 77
        let random = InitialConditions.threeBody(preset: .custom, config: config)
        let again = InitialConditions.threeBody(preset: .custom, config: config)

        #expect(random.map(\.position) != triangle.map(\.position))
        #expect(random.map(\.position) == again.map(\.position))
    }
}
