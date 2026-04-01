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
    var isBlackHoleMode: Bool = false
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
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300), simulationSeparation: 150)
        let result = transformer.simulationToCanvas(.zero)
        #expect(result.x == 200)
        #expect(result.y == 150)
    }

    @Test func offsetMapsCorrectlyWithScale() {
        // Canvas 400x300, separation 100 → scale = min(400,300)*0.7/100 = 2.1
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300), simulationSeparation: 100)
        let scale = transformer.scale
        let result = transformer.simulationToCanvas(Vector2D(x: 50, y: -30))
        #expect(abs(result.x - (200 + 50 * scale)) < 0.01)
        #expect(abs(result.y - (150 + (-30) * scale)) < 0.01)
    }

    @Test func scaleAdjustsWithSeparation() {
        let small = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300), simulationSeparation: 100)
        let large = CoordinateTransformer(canvasSize: CGSize(width: 400, height: 300), simulationSeparation: 300)
        // Larger separation should produce a smaller scale
        #expect(large.scale < small.scale)
    }

    @Test func trailTransformation() {
        // Use separation = 140 so scale = min(200,200)*0.7/140 = 1.0
        let transformer = CoordinateTransformer(canvasSize: CGSize(width: 200, height: 200), simulationSeparation: 140)
        let trail = [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 10, y: 10)
        ]
        let result = transformer.transformTrail(trail)
        let scale = transformer.scale
        #expect(result.count == 2)
        #expect(result[0] == CGPoint(x: 100, y: 100))
        #expect(abs(result[1].x - (100 + 10 * scale)) < 0.01)
        #expect(abs(result[1].y - (100 + 10 * scale)) < 0.01)
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
        let orbiter = CelestialBody(mass: 1, position: Vector2D(x: 100, y: 0), velocity: .zero)

        // Small mass with black hole mode: not a black hole (r_s too small)
        let smallBody = CelestialBody(mass: 100, position: .zero, velocity: .zero)
        let smallEngine = GravitySimulationEngine(body1: smallBody, body2: orbiter)
        smallEngine.isBlackHoleMode = true
        smallEngine.step(dt: 0) // trigger metrics update
        #expect(!smallEngine.metrics.isBlackHole)

        // Large mass without toggle: not flagged as black hole
        let bigBody = CelestialBody(mass: 5000, position: .zero, velocity: .zero)
        let bigEngine = GravitySimulationEngine(body1: bigBody, body2: orbiter)
        #expect(!bigEngine.metrics.isBlackHole)

        // Large mass with toggle: is a black hole
        bigEngine.isBlackHoleMode = true
        bigEngine.step(dt: 0)
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
        engine.isBlackHoleMode = true
        #expect(!engine.metrics.isAbsorbed)

        // Step until absorbed or max iterations
        for _ in 0..<1000 {
            engine.step(dt: 0.01)
            if engine.metrics.isAbsorbed { break }
        }

        #expect(engine.metrics.isAbsorbed)
    }

    @Test func properTimeAccumulates() {
        let body1 = CelestialBody(mass: 200, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector2D(x: 150, y: 0),
            velocity: Vector2D(x: 0, y: 25)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        #expect(engine.metrics.properTime == 0)

        for _ in 0..<100 {
            engine.step(dt: 0.02)
        }

        // Proper time should have accumulated and be less than coordinate time
        #expect(engine.metrics.properTime > 0)
        let coordinateTime = 100 * 0.02
        #expect(engine.metrics.properTime < coordinateTime)
    }

    @Test func grCorrectionCausesPrecession() {
        // Set up a nearly circular orbit and run for many orbits
        let mass: Double = 500
        let r: Double = 80.0
        let rs = 2.0 * GravitySimulationEngine.G * mass / GravitySimulationEngine.cSquared

        // Relativistic circular orbit speed
        let v = sqrt(GravitySimulationEngine.G * mass / max(r - 1.5 * rs, 0.1))

        let body1 = CelestialBody(mass: mass, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 1,
            position: Vector2D(x: r, y: 0),
            velocity: Vector2D(x: 0, y: v)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        // Run for many steps to allow precession to accumulate
        for _ in 0..<10000 {
            engine.step(dt: 0.01)
        }

        // Precession angle should be non-zero (GR effect)
        #expect(abs(engine.metrics.precessionAngle) > 0.01)
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
        engine.isBlackHoleMode = true

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

@MainActor
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
        // Set multipliers so simulationSeparation = 100 (baseAU=150, so 100/150 ≈ 0.667)
        vm.config.separationAU = 100.0 / CelestialConstants.baseAU
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        // Body2 starts at (separation, 0) from center, scaled by coordinateScale
        let expectedX = 200.0 + vm.config.simulationSeparation * vm.coordinateScale
        #expect(abs(vm.body2Position.x - expectedX) < 0.01)
        #expect(abs(vm.body2Position.y - 150) < 0.01)
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
