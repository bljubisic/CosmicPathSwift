//
//  GravityWellScene.swift
//  CosmicPathSwift
//
//  Everything the gravity-well sheet is drawn from (issue #38), in simulation
//  space: centred on the centre of mass and flattened onto the orbital plane
//  (z dropped), since the sheet uses the out-of-plane axis for depth.
//  Built by the view model each frame while a well view is shown; the view
//  projects it through its own camera.
//

import Foundation

// MARK: - PlanePoint

/// A point of the orbital plane, in simulation length units.
struct PlanePoint: Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// `v` relative to `origin`, flattened onto the plane.
    init(_ v: Vector3D, relativeTo origin: Vector3D) {
        self.init(x: v.x - origin.x, y: v.y - origin.y)
    }
}

// MARK: - WellBody

/// One body on the sheet.
struct WellBody: Equatable, Sendable {
    /// Index into the engine's bodies (and `bodyPositions`), for colours and sizes.
    let index: Int
    let id: Int
    let kind: BodyKind
    let position: PlanePoint
}

// MARK: - WellRing

/// A circle drawn on the sheet's surface.
struct WellRing: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case schwarzschild, photonSphere, isco, habitableInner, habitableOuter, roche
    }

    let kind: Kind
    let center: PlanePoint
    let radius: Double
}

// MARK: - GravityWellScene

struct GravityWellScene: Equatable, Sendable {
    let surface: GravityWellSurface
    let bodies: [WellBody]
    /// Trail of every body, index-aligned with `bodies`.
    let trails: [[PlanePoint]]
    let rings: [WellRing]
    /// Distance from the centre the view fits (the auto-zoom extent).
    let viewExtent: Double

    /// The scene for this frame.
    ///
    /// - Parameters:
    ///   - centerOfMass: The point the view is centred on; becomes the origin.
    ///   - habitableZone: The zone to draw, or nil when hidden.
    ///   - trailLimit: Most recent trail points to keep per body.
    static func make(
        bodies: [CelestialBody], config: SimulationConfig, metrics: RelativisticMetrics,
        centerOfMass: Vector3D, viewExtent: Double, habitableZone: HabitableZone?, trailLimit: Int
    ) -> GravityWellScene {
        let isTwoBody = config.mode == .twoBody
        // In 2-body mode an absorbed planet has left the scene.
        let shown = bodies.indices.filter { !(isTwoBody && metrics.isAbsorbed && $0 == 1) }
        let centred = shown.map { index -> CelestialBody in
            var body = bodies[index]
            body.position = body.position - centerOfMass
            return body
        }
        let display = config.advanced.display
        return GravityWellScene(
            surface: .make(bodies: centred, config: config, viewExtent: viewExtent, strength: display.gridWarpStrength),
            bodies: zip(shown, centred).map { index, body in
                WellBody(index: index, id: body.id, kind: body.kind, position: PlanePoint(body.position, relativeTo: .zero))
            },
            trails: shown.map { index in
                bodies[index].trail.suffix(max(trailLimit, 0)).map { PlanePoint($0, relativeTo: centerOfMass) }
            },
            rings: isTwoBody ? twoBodyRings(
                bodies: bodies, config: config, metrics: metrics, centerOfMass: centerOfMass, habitableZone: habitableZone
            ) : [],
            viewExtent: viewExtent
        )
    }

    /// Rings around the central body: rₛ (and the photon sphere and ISCO for a
    /// black hole) when relativistic radii are shown, the habitable zone's
    /// edges, and the Roche limit in the black-hole planet scenario.
    private static func twoBodyRings(
        bodies: [CelestialBody], config: SimulationConfig, metrics: RelativisticMetrics,
        centerOfMass: Vector3D, habitableZone: HabitableZone?
    ) -> [WellRing] {
        guard let central = bodies.first else { return [] }
        let center = PlanePoint(central.position, relativeTo: centerOfMass)
        var radii: [(WellRing.Kind, Double)] = []
        if config.advanced.display.showRelativisticRadii {
            radii.append((.schwarzschild, metrics.schwarzschildRadius))
            if metrics.isBlackHole {
                radii += [(.photonSphere, metrics.photonSphereRadius), (.isco, metrics.iscoRadius)]
            }
        }
        if let zone = habitableZone {
            radii += [(.habitableInner, zone.innerPx), (.habitableOuter, zone.outerPx)]
        }
        if config.isBlackHolePlanet, bodies.count > 1 {
            radii.append((.roche, config.scale.rocheLimit(centralMass: central.mass, planetMass: bodies[1].mass)))
        }
        return radii.filter { $0.1 > 0 }.map { WellRing(kind: $0.0, center: center, radius: $0.1) }
    }
}
