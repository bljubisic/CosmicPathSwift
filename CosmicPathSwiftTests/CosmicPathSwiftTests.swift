//
//  CosmicPathSwiftTests.swift
//  CosmicPathSwiftTests
//
//  Unit tests for the simulation engine, coordinate transformer,
//  and view model using mock engine injection.
//
//  ## 3D Migration Notes
//
//  All former `Vector2D` references have been replaced with `Vector3D`.
//  Tests that verify coordinate projection now explicitly pass
//  `azimuth: 0, elevation: 0` to the transformer so results are in the
//  flat x-y plane and match the expected numerical values exactly.
//  A separate test covers the 3D projection with non-zero elevation.
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
        body2.position = body2.position + Vector3D(x: dt, y: 0, z: 0)
    }
}

// MARK: - Vector3D Tests

struct Vector3DTests {
    @Test func addition() {
        let a = Vector3D(x: 1, y: 2, z: 3)
        let b = Vector3D(x: 4, y: 5, z: 6)
        let result = a + b
        #expect(result.x == 5)
        #expect(result.y == 7)
        #expect(result.z == 9)
    }

    @Test func subtraction() {
        let a = Vector3D(x: 5, y: 3, z: 2)
        let b = Vector3D(x: 2, y: 1, z: 1)
        let result = a - b
        #expect(result.x == 3)
        #expect(result.y == 2)
        #expect(result.z == 1)
    }

    @Test func scalarMultiplication() {
        let v = Vector3D(x: 2, y: 3, z: 4)
        let result = 2.0 * v
        #expect(result.x == 4)
        #expect(result.y == 6)
        #expect(result.z == 8)
    }

    @Test func negation() {
        let v = Vector3D(x: 1, y: -2, z: 3)
        let neg = -v
        #expect(neg.x == -1)
        #expect(neg.y ==  2)
        #expect(neg.z == -3)
    }

    @Test func dotProduct() {
        // Perpendicular unit vectors → dot = 0
        let a = Vector3D(x: 1, y: 0, z: 0)
        let b = Vector3D(x: 0, y: 1, z: 0)
        #expect(a.dot(b) == 0)

        // Parallel → dot = magnitude squared
        let c = Vector3D(x: 3, y: 4, z: 0)
        #expect(c.dot(c) == 25)
    }

    @Test func crossProduct() {
        // Standard basis cross products
        let x = Vector3D(x: 1, y: 0, z: 0)
        let y = Vector3D(x: 0, y: 1, z: 0)
        let z = Vector3D(x: 0, y: 0, z: 1)

        // x × y = z
        let xCrossY = x.cross(y)
        #expect(abs(xCrossY.x) < 1e-10)
        #expect(abs(xCrossY.y) < 1e-10)
        #expect(abs(xCrossY.z - 1.0) < 1e-10)

        // y × z = x
        let yCrossZ = y.cross(z)
        #expect(abs(yCrossZ.x - 1.0) < 1e-10)
        #expect(abs(yCrossZ.y) < 1e-10)
        #expect(abs(yCrossZ.z) < 1e-10)

        // Anti-commutativity: y × x = -z
        let yCrossX = y.cross(x)
        #expect(abs(yCrossX.z + 1.0) < 1e-10)
    }

    @Test func crossProductMagnitudeIsAngularMomentum() {
        // For a circular orbit in the x-y plane:
        // r = (r, 0, 0), v = (0, v, 0) → L = |r × v| = r*v
        let r: Double = 150
        let v: Double = 25
        let pos = Vector3D(x: r, y: 0, z: 0)
        let vel = Vector3D(x: 0, y: v, z: 0)
        let L = pos.cross(vel).magnitude
        #expect(abs(L - r * v) < 1e-10)
    }

    @Test func magnitude() {
        let v = Vector3D(x: 1, y: 2, z: 2)  // magnitude = 3
        #expect(abs(v.magnitude - 3.0) < 1e-10)
        #expect(Vector3D.zero.magnitude == 0)
    }

    @Test func normalized() {
        let v = Vector3D(x: 0, y: 0, z: 5)
        let n = v.normalized
        #expect(abs(n.x) < 1e-10)
        #expect(abs(n.y) < 1e-10)
        #expect(abs(n.z - 1.0) < 1e-10)

        #expect(Vector3D.zero.normalized == .zero)
    }
}

// MARK: - CoordinateTransformer Tests

struct CoordinateTransformerTests {

    /// Origin (0,0,0) must always map to the canvas center regardless of camera angles.
    @Test func originMapsToCenter() {
        let transformer = CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 300),
            simulationSeparation: 150,
            azimuth: 0,
            elevation: 0
        )
        let result = transformer.simulationToCanvas(.zero)
        #expect(result.x == 200)
        #expect(result.y == 150)
    }

    /// At azimuth=0, elevation=0, the projection is a flat top-down view:
    /// canvasX = centerX + x*scale, canvasY = centerY + y*scale.
    @Test func flatProjectionMapsCorrectly() {
        let transformer = CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 300),
            simulationSeparation: 100,
            azimuth: 0,
            elevation: 0
        )
        let scale = transformer.scale
        let result = transformer.simulationToCanvas(Vector3D(x: 50, y: -30, z: 0))
        #expect(abs(result.x - (200 + 50 * scale)) < 0.01)
        #expect(abs(result.y - (150 + (-30) * scale)) < 0.01)
    }

    /// Larger separation must produce a smaller scale (zoom-out to fit).
    @Test func scaleAdjustsWithSeparation() {
        let small = CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 300),
            simulationSeparation: 100,
            azimuth: 0,
            elevation: 0
        )
        let large = CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 300),
            simulationSeparation: 300,
            azimuth: 0,
            elevation: 0
        )
        #expect(large.scale < small.scale)
    }

    /// At elevation=π/2 (edge-on), a point with z≠0 should affect screen-Y
    /// while a point in the x-y plane (z=0) produces screenY=0.
    @Test func elevationProjectsZAxis() {
        let transformer = CoordinateTransformer(
            canvasSize: CGSize(width: 400, height: 400),
            simulationSeparation: 100,
            azimuth: 0,
            elevation: .pi / 2  // edge-on
        )
        let scale = transformer.scale
        let center = CGPoint(x: 200, y: 200)

        // Point on x-axis with z=0: at edge-on view screenY = cos(π/2)*y + sin(π/2)*z = 0
        let onPlane = transformer.simulationToCanvas(Vector3D(x: 50, y: 0, z: 0))
        #expect(abs(onPlane.y - center.y) < 0.01)

        // Point with z=20: screenY = sin(π/2)*20 = 20 → canvasY = center + 20*scale
        let offPlane = transformer.simulationToCanvas(Vector3D(x: 0, y: 0, z: 20))
        #expect(abs(offPlane.y - (center.y + 20 * scale)) < 0.01)
    }

    /// Batch trail transformation should preserve count and match individual projections.
    @Test func trailTransformation() {
        let transformer = CoordinateTransformer(
            canvasSize: CGSize(width: 200, height: 200),
            simulationSeparation: 100,
            azimuth: 0,
            elevation: 0
        )
        let scale = transformer.scale
        let trail = [
            Vector3D(x: 0,  y: 0,  z: 0),
            Vector3D(x: 10, y: 10, z: 0)
        ]
        let result = transformer.transformTrail(trail)
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
        let body2 = CelestialBody(mass: 1, position: Vector3D(x: 100, y: 0, z: 0), velocity: .zero)

        let (a1, a2) = GravitySimulationEngine.computeAccelerations(body1: body1, body2: body2)

        // body1 should accelerate toward body2 (positive x direction)
        #expect(a1.x > 0)
        // body2 should accelerate toward body1 (negative x direction)
        #expect(a2.x < 0)
    }

    @Test func heavierBodyAcceleratesLess() {
        let body1 = CelestialBody(mass: 1000, position: .zero, velocity: .zero)
        let body2 = CelestialBody(mass: 1, position: Vector3D(x: 100, y: 0, z: 0), velocity: .zero)

        let (a1, a2) = GravitySimulationEngine.computeAccelerations(body1: body1, body2: body2)

        // The lighter body should have much larger acceleration magnitude
        #expect(abs(a2.x) > abs(a1.x))
    }

    @Test func stepAdvancesPositions() {
        let body1 = CelestialBody(mass: 200, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector3D(x: 150, y: 0, z: 0),
            velocity: Vector3D(x: 0, y: 25, z: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        let initialPos = engine.body2.position

        engine.step(dt: 0.02)

        #expect(engine.body2.position != initialPos)
    }

    /// A non-zero inclination should produce a non-zero z-velocity after a step,
    /// confirming that the orbit actually leaves the x-y plane.
    @Test func inclinedOrbitDevelopsZComponent() {
        let mass: Double = 200
        let r: Double = 150
        let rs = 2.0 * GravitySimulationEngine.G * mass / GravitySimulationEngine.cSquared
        let v = sqrt(GravitySimulationEngine.G * mass / max(r - 1.5 * rs, 0.1))
        let inclination = Double.pi / 4  // 45°

        let body1 = CelestialBody(mass: mass, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector3D(x: r, y: 0, z: 0),
            velocity: Vector3D(x: 0, y: v * cos(inclination), z: v * sin(inclination))
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        for _ in 0..<100 {
            engine.step(dt: 0.02)
        }

        // After 100 steps, z-position should have diverged from zero (inclined orbit)
        #expect(abs(engine.body2.position.z) > 0.01)
    }

    @Test func metricsAreComputed() {
        let body1 = CelestialBody(mass: 200, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 5,
            position: Vector3D(x: 150, y: 0, z: 0),
            velocity: Vector3D(x: 0, y: 25, z: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        #expect(engine.metrics.schwarzschildRadius > 0)
        #expect(engine.metrics.photonSphereRadius > engine.metrics.schwarzschildRadius)
        #expect(engine.metrics.iscoRadius > engine.metrics.photonSphereRadius)
        #expect(engine.metrics.timeDilationFactor > 0)
        #expect(engine.metrics.timeDilationFactor <= 1.0)
    }

    @Test func blackHoleDetection() {
        let orbiter = CelestialBody(mass: 1, position: Vector3D(x: 100, y: 0, z: 0), velocity: .zero)

        // Small mass with black hole mode: rₛ too small → not flagged
        let smallBody = CelestialBody(mass: 100, position: .zero, velocity: .zero)
        let smallEngine = GravitySimulationEngine(body1: smallBody, body2: orbiter)
        smallEngine.isBlackHoleMode = true
        smallEngine.step(dt: 0)
        #expect(!smallEngine.metrics.isBlackHole)

        // Large mass without toggle: not flagged
        let bigBody = CelestialBody(mass: 5000, position: .zero, velocity: .zero)
        let bigEngine = GravitySimulationEngine(body1: bigBody, body2: orbiter)
        #expect(!bigEngine.metrics.isBlackHole)

        // Large mass with toggle: flagged as black hole
        bigEngine.isBlackHoleMode = true
        bigEngine.step(dt: 0)
        #expect(bigEngine.metrics.isBlackHole)
    }

    @Test func absorptionAtEventHorizon() {
        let body1 = CelestialBody(mass: 10000, position: .zero, velocity: .zero)
        let rs = 2.0 * GravitySimulationEngine.G * 10000.0 / GravitySimulationEngine.cSquared

        // Start body2 just outside the event horizon, falling inward
        let body2 = CelestialBody(
            mass: 1,
            position: Vector3D(x: rs + 1, y: 0, z: 0),
            velocity: Vector3D(x: -50, y: 0, z: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        engine.isBlackHoleMode = true
        #expect(!engine.metrics.isAbsorbed)

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
            position: Vector3D(x: 150, y: 0, z: 0),
            velocity: Vector3D(x: 0, y: 25, z: 0)
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
        let mass: Double = 500
        let r: Double = 80.0
        let rs = 2.0 * GravitySimulationEngine.G * mass / GravitySimulationEngine.cSquared
        let v = sqrt(GravitySimulationEngine.G * mass / max(r - 1.5 * rs, 0.1))

        let body1 = CelestialBody(mass: mass, position: .zero, velocity: .zero)
        let body2 = CelestialBody(
            mass: 1,
            position: Vector3D(x: r, y: 0, z: 0),
            velocity: Vector3D(x: 0, y: v, z: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)

        for _ in 0..<10000 {
            engine.step(dt: 0.01)
        }

        // GR correction causes the perihelion to precess — angle must be non-zero
        #expect(abs(engine.metrics.precessionAngle) > 0.01)
    }

    @Test func absorbedEngineStopsUpdating() {
        let body1 = CelestialBody(mass: 10000, position: .zero, velocity: .zero)
        let rs = 2.0 * GravitySimulationEngine.G * 10000.0 / GravitySimulationEngine.cSquared
        let body2 = CelestialBody(
            mass: 1,
            position: Vector3D(x: rs + 1, y: 0, z: 0),
            velocity: Vector3D(x: -50, y: 0, z: 0)
        )

        let engine = GravitySimulationEngine(body1: body1, body2: body2)
        engine.isBlackHoleMode = true

        for _ in 0..<1000 {
            engine.step(dt: 0.01)
            if engine.metrics.isAbsorbed { break }
        }

        let posAfterAbsorption = engine.body2.position

        // Further steps must not change position once absorbed
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

    /// Body1 starts at the origin — must project to canvas center at any camera angle.
    @Test func body1PositionAtCanvasCenter() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        #expect(vm.body1Position.x == 200)
        #expect(vm.body1Position.y == 150)
    }

    /// Body2 starts at (separation, 0, 0).  At azimuth=0 the x-axis maps directly to
    /// screen-x, so body2Position.x = centerX + separation * scale regardless of elevation.
    @Test func body2PositionOffsetFromCenter() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.config.separationAU = 100.0 / CelestialConstants.baseAU
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        // Body2 is on the x-axis (y=0, z=0). Azimuth rotation maps x→screenX unchanged.
        // Elevation blend: screenY = cos(θ)*y' + sin(θ)*z = 0. So y stays at center.
        let expectedX = 200.0 + vm.config.simulationSeparation * vm.coordinateScale
        #expect(abs(vm.body2Position.x - expectedX) < 0.01)
        #expect(abs(vm.body2Position.y - 150) < 0.01)
    }

    /// Rotating the camera should not change body1's canvas position (it is at the origin).
    @Test func rotateCameraPreservesOriginProjection() {
        let vm = SimulationViewModel { body1, body2 in
            MockSimulationEngine(body1: body1, body2: body2)
        }
        vm.setup(canvasSize: CGSize(width: 400, height: 300))

        vm.rotateCamera(deltaAzimuth: 0.5, deltaElevation: 0.3)

        // Origin always projects to canvas center
        #expect(vm.body1Position.x == 200)
        #expect(vm.body1Position.y == 150)
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
