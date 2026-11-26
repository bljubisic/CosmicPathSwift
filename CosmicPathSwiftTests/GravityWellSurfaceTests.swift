//
//  GravityWellSurfaceTests.swift
//  CosmicPathSwiftTests
//
//  Depth of the gravity-well sheet (issue #38): the log-weighted, softened,
//  soft-capped Newtonian wells and the Flamm's paraboloid funnel.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Newtonian wells

struct NewtonianWellTests {

    private let width = 10.0
    private let depthScale = 50.0
    private let cap = 70.0

    private func surface(_ sources: [WellSource], strength: Double = 1) -> GravityWellSurface {
        GravityWellSurface(
            sources: sources,
            profile: .newtonian(wellWidth: width, depthScale: depthScale, cap: cap),
            strength: strength
        )
    }

    @Test func isSymmetricAroundOneBody() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 1)])
        let right = sheet.depth(x: 25, y: 0)
        #expect(abs(sheet.depth(x: -25, y: 0) - right) < 1e-12)
        #expect(abs(sheet.depth(x: 0, y: 25) - right) < 1e-12)
        #expect(abs(sheet.depth(x: 15, y: 20) - right) < 1e-12)
    }

    @Test func isDeepestAtTheBodyAndShallowsOutward() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 1)])
        let depths = [0.0, 5, 20, 80, 400].map { sheet.depth(x: $0, y: 0) }
        #expect(zip(depths, depths.dropFirst()).allSatisfy { $0 > $1 })
        #expect(depths.last! > 0)
    }

    /// Softening keeps the bottom finite: one body of weight 1 gives cap · tanh(scale / cap).
    @Test func softeningKeepsTheBottomFinite() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 1)])
        let expected = cap * tanh(depthScale / cap)
        #expect(abs(sheet.depth(x: 0, y: 0) - expected) < 1e-9)
    }

    @Test func heavierBodiesHaveDeeperWells() {
        let sheet = surface([WellSource(x: -500, y: 0, mass: 1), WellSource(x: 500, y: 0, mass: 40)])
        #expect(sheet.depth(x: 500, y: 0) > sheet.depth(x: -500, y: 0))
    }

    /// Black Hole Mode's 5000× mass: a linear sum leaves the light body's well
    /// at 0.02% of the hole's; log weighting keeps it clearly visible.
    @Test func logWeightingKeepsLightWellsVisible() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 5000), WellSource(x: 1000, y: 0, mass: 1)])
        let ratio = sheet.depth(x: 1000, y: 0) / sheet.depth(x: 0, y: 0)
        #expect(ratio > 0.05)
        #expect(ratio < 0.5)
    }

    @Test func weightsAreLogarithmicWithAFloor() {
        let sheet = surface([
            WellSource(x: 0, y: 0, mass: 1e6), WellSource(x: 0, y: 0, mass: 1), WellSource(x: 0, y: 0, mass: 0)
        ])
        #expect(sheet.weight(of: 0) == 1)
        #expect(sheet.weight(of: 1) == GravityWellSurface.minimumWeight)
        #expect(sheet.weight(of: 2) == 0)

        let equal = surface([WellSource(x: 0, y: 0, mass: 3), WellSource(x: 9, y: 0, mass: 3)])
        #expect(equal.weight(of: 0) == 1)
        #expect(equal.weight(of: 1) == 1)

        // Above the floor: log1p(1) / log1p(10) ≈ 0.29.
        let pair = surface([WellSource(x: 0, y: 0, mass: 100), WellSource(x: 0, y: 0, mass: 10)])
        #expect(abs(pair.weight(of: 1) - log1p(1) / log1p(10)) < 1e-12)
    }

    /// The soft cap never exceeds the cap and leaves no flat bottom.
    @Test func softCapHasNoFlatBottom() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 1)], strength: 3)
        let bottom = sheet.depth(x: 0, y: 0)
        #expect(bottom < cap)
        #expect(bottom > sheet.depth(x: width * 0.1, y: 0))
    }

    /// A body drawn bigger than the well (Visual Black Hole Mode's disc) widens its own well only.
    @Test func minimumWidthWidensOnlyThatWell() {
        let sheet = surface([
            WellSource(x: 0, y: 0, mass: 5000, minimumWidth: 40), WellSource(x: 1000, y: 0, mass: 1)
        ])
        #expect(sheet.wellWidth(of: 0) == 40)
        #expect(sheet.wellWidth(of: 1) == width)
        let narrow = surface([WellSource(x: 0, y: 0, mass: 5000), WellSource(x: 1000, y: 0, mass: 1)])
        #expect(sheet.depth(x: 30, y: 0) > narrow.depth(x: 30, y: 0))
    }

    @Test func zeroStrengthIsFlat() {
        let sheet = surface([WellSource(x: 0, y: 0, mass: 1)], strength: 0)
        #expect(sheet.depth(x: 0, y: 0) == 0)
        #expect(sheet.depth(x: 30, y: 0) == 0)
    }

    @Test func noBodiesIsFlat() {
        #expect(surface([]).depth(x: 0, y: 0) == 0)
    }
}

// MARK: - Flamm's paraboloid

struct FlammWellTests {

    private let rs = 2.0
    private let rim = 40.0

    private func surface(strength: Double = 1) -> GravityWellSurface {
        GravityWellSurface(
            sources: [WellSource(x: 0, y: 0, mass: 10), WellSource(x: 16, y: 0, mass: 1e-6)],
            profile: .flamm(schwarzschildRadius: rs, rimRadius: rim),
            strength: strength
        )
    }

    private func z(_ r: Double) -> Double { 2 * (rs * (r - rs)).squareRoot() }

    /// depth = z(rim) − z(r), z = 2√(rₛ(r − rₛ)); the orbiter adds nothing.
    @Test func followsFlammsParaboloid() {
        let sheet = surface()
        for r in [2.5, 6, 16, 30] {
            #expect(abs(sheet.depth(x: r, y: 0) - (z(rim) - z(r))) < 1e-9)
        }
        #expect(abs(sheet.depth(x: 0, y: 6) - (z(rim) - z(6))) < 1e-9)
    }

    @Test func isDeepestInsideTheHorizon() {
        let sheet = surface()
        #expect(sheet.depth(x: 0, y: 0) == z(rim))
        #expect(sheet.depth(x: 1, y: 1) == z(rim))
        #expect(sheet.horizonDepth == z(rim))
    }

    @Test func isFlatAtAndBeyondTheRim() {
        let sheet = surface()
        #expect(sheet.depth(x: rim, y: 0) == 0)
        #expect(sheet.depth(x: rim * 2, y: 0) == 0)
    }

    @Test func strengthExaggeratesTheFunnel() {
        #expect(abs(surface(strength: 2).depth(x: 6, y: 0) - 2 * surface().depth(x: 6, y: 0)) < 1e-9)
        #expect(surface(strength: 0).depth(x: 0, y: 0) == 0)
    }
}

// MARK: - Choosing the profile

@MainActor
struct GravityWellSurfaceFactoryTests {

    private func bodies() -> [CelestialBody] {
        [
            CelestialBody(id: 0, kind: .star, mass: 200, position: .zero, velocity: .zero),
            CelestialBody(id: 1, kind: .planet, mass: 5, position: Vector3D(x: 150, y: 0, z: 30), velocity: .zero)
        ]
    }

    @Test func visualUsesNewtonianWellsWithAWidthFloor() {
        let config = SimulationConfig()
        let sheet = GravityWellSurface.make(bodies: bodies(), config: config, viewExtent: 150, strength: 1)
        let softening = InitialConditions.softening(config: config)
        let width = max(softening, GravityWellSurface.wellWidthFraction * 150)
        #expect(sheet.profile == .newtonian(
            wellWidth: width,
            depthScale: GravityWellSurface.depthFraction * 150,
            cap: GravityWellSurface.capFraction * 150
        ))
        #expect(sheet.sources.count == 2)
    }

    /// Bodies are flattened onto the orbital plane: z is dropped.
    @Test func flattensInclinedOrbits() {
        let sheet = GravityWellSurface.make(bodies: bodies(), config: SimulationConfig(), viewExtent: 150, strength: 1)
        #expect(sheet.sources[1] == WellSource(x: 150, y: 0, mass: 5))
    }

    /// Visual Black Hole Mode draws the hole rₛ wide, so its well is at least 2 rₛ wide.
    @Test func blackHoleModeWidensTheHolesWell() {
        var config = SimulationConfig()
        config.isBlackHoleMode = true
        let hole = CelestialBody(id: 0, kind: .star, mass: 5000, position: .zero, velocity: .zero)
        let planet = CelestialBody(id: 1, kind: .planet, mass: 5, position: Vector3D(x: 300, y: 0, z: 0), velocity: .zero)
        let sheet = GravityWellSurface.make(bodies: [hole, planet], config: config, viewExtent: 300, strength: 1)
        let rs = config.scale.constants.schwarzschildRadius(mass: 5000)
        #expect(sheet.sources[0].minimumWidth == 2 * rs)
        #expect(sheet.sources[1].minimumWidth == 0)
    }

    @Test func strongFieldUsesFlamm() {
        var config = SimulationConfig()
        config.advanced.scale = .realistic
        config.isBlackHoleMode = true
        #expect(config.isStrongField)
        let hole = CelestialBody(id: 0, kind: .star, mass: 10, position: .zero, velocity: .zero)
        let probe = CelestialBody(id: 1, kind: .planet, mass: 1e-9, position: Vector3D(x: 160, y: 0, z: 0), velocity: .zero)
        let sheet = GravityWellSurface.make(bodies: [hole, probe], config: config, viewExtent: 160, strength: 1)
        let rs = config.scale.constants.schwarzschildRadius(mass: 10)
        #expect(sheet.profile == .flamm(
            schwarzschildRadius: rs, rimRadius: max(GravityWellSurface.rimFraction * 160, 2 * rs)
        ))
    }
}

// MARK: - View mode

struct CanvasViewModeTests {

    @Test func cyclesThroughEveryMode() {
        #expect(CanvasViewMode.twoD.next == .split)
        #expect(CanvasViewMode.split.next == .threeD)
        #expect(CanvasViewMode.threeD.next == .twoD)
    }

    @Test func onlyTwoDHidesTheWells() {
        #expect(!CanvasViewMode.twoD.showsWells)
        #expect(CanvasViewMode.split.showsWells)
        #expect(CanvasViewMode.threeD.showsWells)
    }
}
