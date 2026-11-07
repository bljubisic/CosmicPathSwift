# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Open in Xcode via `CosmicPathSwift.xcodeproj`. There is no CLI build script — use Xcode or `xcodebuild`:

```bash
# Build
xcodebuild -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>'

# Run all tests
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>'

# Run a single test (Swift Testing framework, use -only-testing with the suite name)
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>' -only-testing:CosmicPathSwiftTests/GravitySimulationEngineTests
```

There is no iPhone 16 simulator on this machine; pick a UDID from `xcrun simctl list devices available` (e.g. the iOS 27.2 iPhone 17). Pass `-only-testing:CosmicPathSwiftTests` to skip the slow UI tests.

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

**Physics engine injection** — `SimulationViewModel` takes an `engineFactory: (EngineSetup) -> SimulationEngineProtocol` closure at init, defaulting to `GravitySimulationEngine(bodies:settings:scale:)`. `EngineSetup` carries the bodies, `config.advanced.engine` (integrator, softening, collision mode) and `config.scale`; the view model passes it to every engine it builds, including the chaos twin, and changing those settings restarts the setup. Tests pass `MockSimulationEngine` this way (`{ MockSimulationEngine(bodies: $0.bodies) }`) without any mocking framework.

**Coordinate spaces** — The engine works in simulation space (origin at center, units are pixels). `CoordinateTransformer` converts to canvas space (origin at top-left) before the ViewModel exposes positions to views. Don't mix these spaces.

**Scaled physics constants** — constants travel as a `ScaleProfile` value (`Physics/ScaleProfile.swift`): G and c, slider-unit conversions (M☉, M⊕, AU), and the size rules that used to be in pixels (black hole threshold, star surface, Roche radius, merge distance). Physics functions take a `constants:` parameter defaulting to Visual; engines read `scale`. `ScaleProfile.visual` is the original app: `G = 500`, `c = 200` (not SI units), and the static `GravitySimulationEngine.G` / `c` / `cSquared` / `softening` and `CelestialConstants.base*` are aliases of it. Mass multipliers in `SimulationConfig` map to `CelestialConstants.baseSolarMass / baseEarthMass` internal values. Black hole mode switches `body1.mass` to `blackHoleSolarMass = 5000` to make the Schwarzschild radius visually meaningful (threshold: `rs > 8px`).

**Simulation loop** — A 60 fps task calls `tick()`, which runs `stepsPerFrame` integration steps per frame (scaled by the Advanced accuracy/speed multipliers and capped by `FrameStepPlanner.stepCap`, which divides the budget by the integrator's force evaluations per step and by the number of engines). The integrator is selectable in `EngineSettings` — Velocity-Verlet (default, `NBodyGravity.verletStep`), RK4 or Yoshida 4 (`Physics/Integrators.swift`). Verlet and Yoshida use v(t) in the velocity-dependent GR term, so they are only 1st-order in it; RK4 is not. Softening also comes from `EngineSettings` (default 5 px) — use the engine's `softeningLength`, not the static constant. the GR force (`NBodyGravity.pairAcceleration`) is Newtonian gravity plus a Schwarzschild-style −3GmL²/(c²r⁴) correction, which gives the correct perihelion precession but is not the full 1PN Einstein-Infeld-Hoffmann equations.

**Diagnostics** — The Advanced sheet's Diagnostics section charts ΔE/E and ΔL/L and exports a CSV. In 2-body mode the relative orbit's E = ½v² − GM/r − GML²/(c²r³) and L = |r×v| are exactly conserved by the force law (`RelativeOrbit`), so their drift is pure integrator error; tidal mass loss is excluded like merges are in 3-body (`SystemMetrics.energyDrift` is Newtonian and includes the GR term's drift; its ΔL/L is exact). `DiagnosticsRecorder` keeps one sample per `stride` frames, ignores syncs where time didn't advance, and at 1000 samples drops every other one and doubles the stride. Habitable-zone settings (`config.advanced.habitableZone`) are render-only: they re-project via `syncState()` without restarting.

**Orientation layout** — `ContentView` uses `GeometryReader` to detect landscape (`width > height`) and switches layouts. Landscape hides mass/distance sliders and the black hole toggle (`showParameterControls: false` on `ControlPanelView`).

**Canvas rendering** — `SimulationCanvasView` uses SwiftUI `Canvas` (not `UIKit`) for the spacetime grid and orbital trails. The grid warp is purely visual — `warpPoint(_:toward:strength:)` displaces grid lines toward `body1Position`.
