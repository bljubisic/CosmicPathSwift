//
//  HabitableZoneTests.swift
//  CosmicPathSwiftTests
//
//  Tests for the habitable-zone physics (luminosity, bounds, equilibrium
//  temperature, status), the ring geometry helper, and the ViewModel wiring.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Physics

struct HabitableZonePhysicsTests {

    @Test func sunHasUnitLuminosityAndConservativeBounds() {
        let zone = HabitableZone(luminosity: HabitableZonePhysics.starLuminosity(solarMasses: 1))
        #expect(abs(zone.luminosity - 1) < 1e-12)
        #expect(abs(zone.innerAU - 0.953) < 0.01)
        #expect(abs(zone.outerAU - 1.374) < 0.01)
    }

    @Test(arguments: [0.43, 2.0, 55.0])
    func luminosityIncreasesAcrossPiecewiseBoundary(boundary: Double) {
        let below = HabitableZonePhysics.starLuminosity(solarMasses: boundary * 0.999)
        let at = HabitableZonePhysics.starLuminosity(solarMasses: boundary)
        let above = HabitableZonePhysics.starLuminosity(solarMasses: boundary * 1.001)
        #expect(below < at)
        #expect(at < above)
    }

    @Test func luminosityIsMonotonicOverSliderRange() {
        let masses = stride(from: 0.1, through: 60, by: 0.01).map { $0 }
        let luminosities = masses.map { HabitableZonePhysics.starLuminosity(solarMasses: $0) }
        #expect(zip(luminosities, luminosities.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func blackHoleLuminosityScalesLinearlyWithFractionAndMass() {
        let base = HabitableZonePhysics.blackHoleLuminosity(solarMasses: 1, eddingtonFraction: 1e-4)
        let doubleFraction = HabitableZonePhysics.blackHoleLuminosity(solarMasses: 1, eddingtonFraction: 2e-4)
        let tripleMass = HabitableZonePhysics.blackHoleLuminosity(solarMasses: 3, eddingtonFraction: 1e-4)
        #expect(abs(base - 3.2) < 1e-9)
        #expect(abs(doubleFraction / base - 2) < 1e-9)
        #expect(abs(tripleMass / base - 3) < 1e-9)
    }

    @Test func defaultBlackHoleZoneLiesOutsideISCO() {
        var config = SimulationConfig()
        config.isBlackHoleMode = true
        let zone = HabitableZone.forCentralBody(of: config)
        let isco = 6 * GravitySimulationEngine.G * config.simulationMass1 / GravitySimulationEngine.cSquared
        #expect(zone.innerPx > isco)
    }

    @Test func earthEquilibriumTemperature() {
        let temperature = HabitableZonePhysics.equilibriumTemperature(luminosity: 1, distanceAU: 1)
        #expect(abs(temperature - 255) < 1)
    }

    @Test(arguments: [
        (0.9, HabitableStatus.tooHot),
        (1.0, HabitableStatus.habitable),
        (1.5, HabitableStatus.tooCold),
    ])
    func statusForSun(distanceAU: Double, expected: HabitableStatus) {
        let zone = HabitableZone(luminosity: 1)
        #expect(zone.status(atDistanceAU: distanceAU) == expected)
    }
}

// MARK: - Ring Geometry

struct HabitableZoneRingTests {

    @Test(arguments: [
        Vector3D(x: 0, y: 0, z: 1),
        Vector3D(x: 0.3, y: -0.5, z: 0.8),
        Vector3D(x: 1, y: 0, z: 0),
    ])
    func ringPointsLieOnCircleInPlane(normal: Vector3D) {
        let center = Vector3D(x: 10, y: -4, z: 2)
        let radius = 42.0
        let points = HabitableZonePhysics.ringPoints(center: center, normal: normal, radius: radius, samples: 32)
        let unitNormal = normal.normalized

        #expect(points.count == 32)
        for point in points {
            let offset = point - center
            #expect(abs(offset.dot(unitNormal)) < 1e-9)
            #expect(abs(offset.magnitude - radius) < 1e-9)
        }
    }
}

// MARK: - ViewModel

@MainActor
struct HabitableZoneViewModelTests {

    private func makeViewModel() -> SimulationViewModel {
        SimulationViewModel { bodies in MockSimulationEngine(bodies: bodies) }
    }

    private let canvas = CGSize(width: 400, height: 300)

    @Test func ringsEmptyInThreeBodyMode() {
        let vm = makeViewModel()
        vm.config.mode = .threeBody
        vm.setup(canvasSize: canvas)
        #expect(vm.habitableZone == nil)
        #expect(vm.habitableZoneInnerRing.isEmpty)
        #expect(vm.habitableZoneOuterRing.isEmpty)
        #expect(vm.habitableStatus == nil)
    }

    @Test func ringsEmptyWhenToggleOff() {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        #expect(!vm.habitableZoneInnerRing.isEmpty)

        vm.setHabitableZoneVisible(false)
        #expect(vm.habitableZone == nil)
        #expect(vm.habitableZoneInnerRing.isEmpty)
        #expect(vm.habitableZoneOuterRing.isEmpty)
        #expect(vm.planetEquilibriumTemperature == nil)
    }

    @Test func ringsAreCirclesAroundStarWhenViewedTopDown() throws {
        let vm = makeViewModel()
        vm.cameraElevation = 0
        vm.setup(canvasSize: canvas)

        let zone = try #require(vm.habitableZone)
        let expected = zone.innerPx * vm.coordinateScale
        let star = vm.body1Position
        #expect(vm.habitableZoneInnerRing.count == SimulationViewModel.habitableZoneRingSamples)
        for point in vm.habitableZoneInnerRing {
            let distance = hypot(point.x - star.x, point.y - star.y)
            #expect(abs(distance - expected) < 1e-6)
        }
    }

    @Test func defaultConfigIsHabitable() throws {
        let vm = makeViewModel()
        vm.setup(canvasSize: canvas)
        #expect(vm.habitableStatus == .habitable)
        let temperature = try #require(vm.planetEquilibriumTemperature)
        #expect(abs(temperature - 255) < 1)
        #expect(!vm.isHabitableZoneOffScreen)
    }

    @Test func heavyStarZoneIsOffScreen() {
        let vm = makeViewModel()
        vm.config.mass1Multiplier = 10
        vm.setup(canvasSize: canvas)
        #expect(vm.isHabitableZoneOffScreen)
        #expect(vm.habitableStatus == .tooHot)
    }
}
