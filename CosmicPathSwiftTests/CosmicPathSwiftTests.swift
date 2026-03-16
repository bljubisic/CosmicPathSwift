//
//  CosmicPathSwiftTests.swift
//  CosmicPathSwiftTests
//
//  Unit tests for the simulation engine, coordinate transformer,
//  and view model using mock engine injection.
//

import Testing
import Foundation
@testable import CosmicPathSwift

// MARK: - Mock Engine

/// A mock simulation engine for testing the ViewModel in isolation.
class MockSimulationEngine: SimulationEngineProtocol {
    var body1: CelestialBody
    var body2: CelestialBody
    var metrics = RelativisticMetrics()
    var stepCount = 0

    init(body1: CelestialBody, body2: CelestialBody) {
        self.body1 = body1
        self.body2 = body2
    }

    func step(dt: Double) {
        stepCount += 1
        // Move body2 slightly each step to simulate motion
        body2.position = body2.position + Vector2D(x: dt, y: 0)
    }
}

// MARK: - Vector2D Tests

struct Vector2DTests {
    @Test func addition() {
        let a = Vector2D(x: 1, y: 2)
        let b = Vector2D(x: 3, y: 4)
        let result = a + b
        #expect(result.x == 4)
        #expect(result.y == 6)
    }

    @Test func subtraction() {
        let a = Vector2D(x: 5, y: 3)
        let b = Vector2D(x: 2, y: 1)
        let result = a - b
        #expect(result.x == 3)
        #expect(result.y == 2)
    }

    @Test func scalarMultiplication() {
        let v = Vector2D(x: 2, y: 3)
        let result = 2.0 * v
        #expect(result.x == 4)
        #expect(result.y == 6)
    }

    @Test func dotProduct() {
        let a = Vector2D(x: 1, y: 0)
        let b = Vector2D(x: 0, y: 1)
        #expect(a.dot(b) == 0) // Perpendicular

        let c = Vector2D(x: 3, y: 4)
        let d = Vector2D(x: 3, y: 4)
        #expect(c.dot(d) == 25) // Parallel
    }

    @Test func magnitude() {
        let v = Vector2D(x: 3, y: 4)
        #expect(v.magnitude == 5)
        #expect(Vector2D.zero.magnitude == 0)
    }

    @Test func normalized() {
        let v = Vector2D(x: 0, y: 5)
        let n = v.normalized
        #expect(abs(n.x) < 1e-10)
        #expect(abs(n.y - 1.0) < 1e-10)

        let zero = Vector2D.zero.normalized
        #expect(zero == .zero)
    }
}

// MARK: - CoordinateTransformer Tests

struct CoordinateTransformerTests {
    @Test func originMapsToCenter() {
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300))
        let result = transformer.simulationToCanvas(.zero)
        #expect(result.x == 200)
        #expect(result.y == 150)
    }

    @Test func offsetMapsCorrectly() {
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300))
        let result = transformer.simulationToCanvas(Vector2D(x: 50, y: -30))
        #expect(result.x == 250)
        #expect(result.y == 120)
    }

    @Test func trailTransformation() {
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 200, height: 200))
        let trail = [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 10, y: 10)
        ]
        let result = transformer.transformTrail(trail)
        #expect(result.count == 2)
        #expect(result[0] == CGPoint(x: 100, y: 100))
        #expect(result[1] == CGPoint(x: 110, y: 110))
    }
}

// MARK: - GravitySimulationEngine Tests

struct GravitySimulationEngineTests {
    @Test func accelerationDirectsTowardSource() {
        let body1 = CelestialBody(mass: 100, position: .zero, velocity: .zero)
        let body2 = CelestialBody(mass: 1, position: Vector2D(x: 100, y: 0), velocity: .zero)

        let (a1, a2) = GravitySimulationEngine.computeAccelerations(body1: body1, body2: body2)

        // body1 should accelerate toward body2 (positive x)
        #expect(a1.x > 0)
        // body2 should accelerate toward body1 (negative x)
        #expect(a2.x < 0)
    }

    @Test func heavierBodyAcceleratesLess() {
        let body1 = CelestialBody(mass: 1000, position: .zero, velocity: .zero)
        let body2 = CelestialBody(mass: 1, position: Vector2D(x: 100, y: 0), velocity: .zero)

        let (a1, a2) = GravitySimulationEngine.computeAccelerations(body1: body1, body2: body2)

        // The lighter body should have much larger acceleration magnitude
        #expect(abs(a2.x) > abs(a1.x))
    }

    @Test func stepAdvancesPositions() {
        let body1 = CelestialBody(mass: 200, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector2D(x: 150, y: 0),
            velocity: Vector2D(x: 0, y: 25)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        let initialPos = engine.body2.position

        engine.step(dt: 0.02)

        // Position should have changed
        #expect(engine.body2.position != initialPos)
    }

    @Test func metricsAreComputed() {
        let body1 = CelestialBody(mass: 200, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector2D(x: 150, y: 0),
            velocity: Vector2D(x: 0, y: 25)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        #expect(engine.metrics.schwarzschildRadius > 0)
        #expect(engine.metrics.photonSphereRadius > engine.metrics.schwarzschildRadius)
        #expect(engine.metrics.iscoRadius > engine.metrics.photonSphereRadius)
        #expect(engine.metrics.timeDilationFactor > 0)
        #expect(engine.metrics.timeDilationFactor <= 1.0)
    }

    @Test func blackHoleDetection() {
        // Small mass: not a black hole
        let smallBody = CelestialBody(mass: 100, position: .zero, velocity: .zero)
        let orbiter = CelestialBody(mass: 1, position: Vector2D(x: 100, y: 0), velocity: .zero)
        let smallEngine = GravitySimulationEngine(body1: smallBody, body2: orbiter)
        #expect(!smallEngine.metrics.isBlackHole)

        // Large mass: is a black hole
        let bigBody = CelestialBody(mass: 5000, position: .zero, velocity: .zero)
        let bigEngine = GravitySimulationEngine(body1: bigBody, body2: orbiter)
        #expect(bigEngine.metrics.isBlackHole)
    }

    @Test func absorptionAtEventHorizon() {
        // Place body2 just outside the event horizon of a massive body
        let body1 = CelestialBody(mass: 10000, position: .zero, velocity: .zero)
        let rs = 2.0 * GravitySimulationEngine.G * 10000.0 / GravitySimulationEngine.cSquared

        // Start body2 just barely outside event horizon, falling inward
        let body2 = CelestialBody(
            mass: 1,
            position: Vector2D(x: rs + 1, y: 0),
            velocity: Vector2D(x: -50, y: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        #expect(!engine.metrics.isAbsorbed)

        // Step until absorbed or max iterations
        for _ in 0..<1000 {
            engine.step(dt: 0.01)
            if engine.metrics.isAbsorbed { break }
        }

        #expect(engine.metrics.isAbsorbed)
    }

    @Test func absorbedEngineStopsUpdating() {
        let body1 = CelestialBody(mass: 10000, position: .zero, velocity: .zero)
        let rs = 2.0 * GravitySimulationEngine.G * 10000.0 / GravitySimulationEngine.cSquared
        let body2 = CelestialBody(
            mass: 1,
            position: Vector2D(x: rs + 1, y: 0),
            velocity: Vector2D(x: -50, y: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        // Force absorption
        for _ in 0..<1000 {
            engine.step(dt: 0.01)
            if engine.metrics.isAbsorbed { break }
        }

        let posAfterAbsorption = engine.body2.position

        // Further steps should not change position
        engine.step(dt: 0.01)
        #expect(engine.body2.position == posAfterAbsorption)
    }
}

// MARK: - SimulationViewModel Tests (with Mock Engine)

struct SimulationViewModelTests {
    @Test func setupCreatesEngine() {
        var engineCreated = false
        let vm = SimulationViewModel { body1, body2 in
            engineCreated = true
            return MockSimulationEngine(body1: body1, body2: body2)
        }

        vm.setup(canvasSize: CGSize(width: 400, height: 300))
        #expect(engineCreated)
    }

    @Test func startAndPauseToggleRunning() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        #expect(!vm.isRunning)
        vm.start()
        #expect(vm.isRunning)
        vm.pause()
        #expect(!vm.isRunning)
    }

    @Test func resetStopsSimulation() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        vm.start()
        #expect(vm.isRunning)

        vm.reset(canvasSize: CGSize(width: 400, height: 300))
        #expect(!vm.isRunning)
    }

    @Test func body1PositionAtCanvasCenter() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        // Body1 starts at origin (0,0), which maps to canvas center
        #expect(vm.body1Position.x == 200)
        #expect(vm.body1Position.y == 150)
    }

    @Test func body2PositionOffsetFromCenter() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.config.initialSeparation = 100
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        // Body2 starts at (separation, 0) from center
        #expect(vm.body2Position.x == 300)
        #expect(vm.body2Position.y == 150)
    }
}

// MARK: - RelativisticMetrics Tests

struct RelativisticMetricsTests {
    @Test func timeDilationColorCyan() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.95
        #expect(metrics.timeDilationColor == .cyan)
    }

    @Test func timeDilationColorBlue() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.8
        #expect(metrics.timeDilationColor == .blue)
    }

    @Test func timeDilationColorPurple() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.6
        #expect(metrics.timeDilationColor == .purple)
    }

    @Test func timeDilationColorRed() {
        var metrics = RelativisticMetrics()
        metrics.timeDilationFactor = 0.3
        #expect(metrics.timeDilationColor == .red)
    }
}
