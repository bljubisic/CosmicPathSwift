# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Open in Xcode via `CosmicPathSwift.xcodeproj`. There is no CLI build script — use Xcode or `xcodebuild`:

```bash
# Build
xcodebuild -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all tests
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test (Swift Testing framework, use -only-testing with the suite name)
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CosmicPathSwiftTests/GravitySimulationEngineTests
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.

## Architecture

MVVM with a protocol-based physics engine for testability.

### Data flow

```
SimulationEngineProtocol  ←  GravitySimulationEngine (production)
        ↑                 ←  MockSimulationEngine     (tests)
        |
SimulationViewModel  (@Observable)
        |
ContentView  (GeometryReader → portrait or landscape layout)
   ├── SimulationCanvasView   (Canvas rendering)
   ├── MetricsPanelView       (read-only metrics display)
   └── ControlPanelView       (buttons + sliders; sliders hidden in landscape)
```

### Key design decisions

**Physics engine injection** — `SimulationViewModel` takes an `engineFactory` closure at init, defaulting to `GravitySimulationEngine`. Tests pass `MockSimulationEngine` this way without any mocking framework.

**Coordinate spaces** — The engine works in simulation space (origin at center, units are pixels). `CoordinateTransformer` converts to canvas space (origin at top-left) before the ViewModel exposes positions to views. Don't mix these spaces.

**Scaled physics constants** — `G = 500`, `c = 200` (not SI units). Mass multipliers in `SimulationConfig` map to `CelestialConstants.baseSolarMass / baseEarthMass` internal values. Black hole mode switches `body1.mass` to `blackHoleSolarMass = 5000` to make the Schwarzschild radius visually meaningful (threshold: `rs > 8px`).

**Simulation loop** — A `Timer` at 60 fps calls `tick()`, which runs `stepsPerFrame = 4` Velocity-Verlet integration steps per frame. The integrator is in `GravitySimulationEngine.step(dt:)` using the 1PN Einstein-Infeld-Hoffmann equation.

**Orientation layout** — `ContentView` uses `GeometryReader` to detect landscape (`width > height`) and switches layouts. Landscape hides mass/distance sliders and the black hole toggle (`showParameterControls: false` on `ControlPanelView`).

**Canvas rendering** — `SimulationCanvasView` uses SwiftUI `Canvas` (not `UIKit`) for the spacetime grid and orbital trails. The grid warp is purely visual — `warpPoint(_:toward:strength:)` displaces grid lines toward `body1Position`.
