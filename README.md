# CosmicPath

**Gravity and general relativity, running live on iPhone and iPad.**

CosmicPath is a SwiftUI orbital-mechanics sandbox. Watch two stars orbit each other on a
warping spacetime grid, drop a planet inside a black hole's Roche limit and see it torn
apart, follow star S2 around Sagittarius A\*, or nudge the three-body problem by one part in
a million and watch the copies diverge.

<!-- Screenshots: AppStore/screenshots is git-ignored. Commit a few captures
     (e.g. under docs/images/) and reference them here. -->

---

## Features

### Two-body and black holes
- **Binary orbits** with adjustable masses and separation, orbital trails and a warped
  spacetime grid.
- **General-relativistic correction** to Newtonian gravity, giving the correct perihelion
  precession (Mercury's 43″/century is reproduced to ~1% with Yoshida 4 at fine steps).
- **Black Hole Mode** – event horizon, photon sphere, ISCO and an accretion disk, with
  mergers when a body crosses the horizon.
- **Strong-field scenarios** in geometric units (G = c = 1):
  - **Probe** – a point mass a few Schwarzschild radii out, tracing a precessing rosette.
  - **Planet** – a rocky planet that is tidally disrupted inside the Roche limit.
  - **S2 around Sgr A\*** – the observed orbit (4.30 × 10⁶ M☉, a = 1031 AU, e = 0.884).

### Three-body
- Presets: **Figure-8** choreography, **Lagrange triangle**, **Sun–Planet–Moon**,
  **Pythagorean** problem (ends by ejecting a star) and custom/random layouts.
- **Chaos twin** – runs a copy perturbed by 10⁻⁶ next to the original so you can watch the
  trajectories diverge.

### Physics scales
- **Visual** – tuned, non-SI constants so everything fits on screen.
- **Realistic (planetary)** – AU, solar masses and days, paced by a real-time rate
  ("1 s = 1 month").
- **Realistic (strong field)** – geometric units for the black-hole scenarios.

### Tools
- **Habitable zone** overlay (conservative limits after Kasting et al. 1993, optimistic
  after Kopparapu et al. 2013).
- **Info sheet** ("What am I looking at?") explaining every element on screen.
- **Advanced settings** – integrator (Velocity-Verlet, RK4, Yoshida 4), softening, collision
  mode, accuracy/speed, initial eccentricity, camera presets (top, tilted, edge-on),
  velocity/acceleration vectors.
- **Diagnostics** – live ΔE/E and ΔL/L charts with CSV export.
- **Formula overlay** showing the equations behind the current scene.
- **Screen recording** via ReplayKit, with a share sheet.
- Portrait and landscape layouts, pinch to zoom, drag to rotate the camera.

---

## Requirements

| | |
|---|---|
| iOS / iPadOS | 18.2 or later |
| Xcode | 16.2 or later (iOS 18.2 SDK) |
| Dependencies | none (SwiftUI, Observation, Swift Charts, ReplayKit) |

## Getting started

```bash
git clone git@github.com:bljubisic/CosmicPathSwift.git
cd CosmicPathSwift
open CosmicPathSwift.xcodeproj
```

Pick an iPhone or iPad simulator and press **Run**.

### Building from the command line

Find a simulator UDID first:

```bash
xcrun simctl list devices available
```

```bash
xcodebuild -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>'
```

## Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. The unit
suite has 400+ tests covering the integrators, conservation laws, scales, scenarios and
formatting.

Unit tests only (skips the slower UI tests):

```bash
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>' -only-testing:CosmicPathSwiftTests
```

A single suite:

```bash
xcodebuild test -project CosmicPathSwift.xcodeproj -scheme CosmicPathSwift -destination 'id=<SIMULATOR_UDID>' -only-testing:CosmicPathSwiftTests/IntegratorTests
```

---

## Architecture

MVVM with a protocol-based physics engine, so the view model can be tested with a mock
engine and no mocking framework.

```
SimulationEngineProtocol  ←  GravitySimulationEngine (production)
        ↑                 ←  MockSimulationEngine     (tests)
        |
SimulationViewModel  (@Observable)
        |
ContentView  (portrait / landscape layout)
   ├── SimulationCanvasView   (SwiftUI Canvas: grid, trails, bodies)
   ├── MetricsPanelView       (read-only metrics)
   └── ControlPanelView       (buttons and sliders)
```

| Folder | Contents |
|---|---|
| `CosmicPathSwift/Physics` | Engine, force law (`NBodyGravity`), integrators, scale profiles, initial conditions, habitable zone, Sgr A\* data |
| `CosmicPathSwift/Models` | Configuration and settings types, scenarios, info-sheet content |
| `CosmicPathSwift/ViewModels` | `SimulationViewModel`, chaos twin, diagnostics recorder, zoom, screen recording |
| `CosmicPathSwift/Views` | SwiftUI views and the Advanced settings sections |
| `CosmicPathSwift/Utilities` | Coordinate transforms, grid warp, unit formatting, CSV export |
| `CosmicPathSwiftTests` | Swift Testing unit tests |
| `AppStore` | Screenshot/artwork capture script and App Store page texts |

Key points:

- **Coordinate spaces.** The engine works in simulation space (origin at the centre; units
  depend on the scale). `CoordinateTransformer` converts to canvas space before anything is
  drawn.
- **Scaled constants.** G, c and the size rules travel as a `ScaleProfile` value
  (`.visual`, `.realisticPlanetary`, `.realisticStrongField`), so the same engine runs every
  scale.
- **Simulation loop.** A 60 fps task calls `tick()`, which runs a capped number of
  integration steps per frame (`FrameStepPlanner`).
- **Force law.** Newtonian gravity plus a Schwarzschild-style −3GmL²/(c²r⁴) term. It gives
  the right precession and exact horizon / photon-sphere / ISCO radii, but it is not the
  full 1PN Einstein–Infeld–Hoffmann equations.

See [`CLAUDE.md`](CLAUDE.md) for a deeper tour of the design decisions.

---

## Deep links

Scenarios can be opened directly with `cosmicpath://scenario/<group>/<name>`:

| Link | Opens |
|---|---|
| `cosmicpath://scenario/black-hole/visual` | Visual Black Hole Mode |
| `cosmicpath://scenario/black-hole/probe` | Probe rosette near the horizon |
| `cosmicpath://scenario/black-hole/planet` | Planet torn apart by tides |
| `cosmicpath://scenario/black-hole/s2` | S2 around Sgr A\* |
| `cosmicpath://scenario/three-body/figure-8` | Figure-8 choreography |
| `cosmicpath://scenario/three-body/pythagorean` | Pythagorean problem |
| `cosmicpath://scenario/three-body/lagrange` | Lagrange triangle |
| `cosmicpath://scenario/three-body/sun-earth-moon` | Sun, planet and moon |
| `cosmicpath://scenario/three-body/chaos` | Chaos twin |

Try one on a booted simulator:

```bash
xcrun simctl openurl booted cosmicpath://scenario/three-body/figure-8
```

## App Store screenshots

`AppStore/capture-screenshots.sh` builds the Debug app and captures repeatable screenshots
(and, with `--artwork`, the header and search-result artwork) on the iPhone 6.3″ and iPad
13″ simulators. See [`AppStore/custom-product-pages.md`](AppStore/custom-product-pages.md)
for usage and the store texts.

---

## Contributing

Issues and pull requests are welcome. Please add or update Swift Testing tests for any
physics or view-model change and make sure the unit suite passes before opening a PR.
