//
//  HabitableZoneProjection.swift
//  CosmicPathSwift
//
//  Projects the 2-body habitable zone to canvas space and works out where the
//  planet sits relative to it. Pure, so the ring geometry is unit-testable;
//  `SimulationViewModel` copies the result into its observable properties.
//

import CoreGraphics
import Foundation

/// Canvas-space habitable-zone rings plus the planet's status inside the zone.
struct HabitableZoneProjection: Equatable {
    /// Number of vertices in each projected ring.
    static let ringSamples = 96

    /// The zone counts as off-screen beyond this multiple of the zoom extent.
    static let offScreenFactor = 1.5

    /// Polygon of the zone's inner (hot) edge, in the planet's orbital plane.
    let innerRing: [CGPoint]
    /// Polygon of the zone's outer (cold) edge.
    let outerRing: [CGPoint]
    /// Planet's position relative to the zone; nil once absorbed.
    let status: HabitableStatus?
    /// Planet's equilibrium temperature in kelvin; nil once absorbed.
    let equilibriumTemperature: Double?
    /// True when even the inner edge lies well beyond the current view.
    let isOffScreen: Bool

    /// Nothing to draw (no zone shown).
    static let empty = HabitableZoneProjection(
        innerRing: [], outerRing: [], status: nil, equilibriumTemperature: nil, isOffScreen: false
    )

    /// Projects `zone` around `star` in the orbital plane of `planet`.
    ///
    /// - Parameters:
    ///   - maxExtent: Current zoom extent in simulation units (for the off-screen flag).
    ///   - isAbsorbed: When true the planet is gone, so no status or temperature.
    ///   - albedo: Planet's Bond albedo for the equilibrium temperature.
    static func project(
        zone: HabitableZone,
        star: CelestialBody,
        planet: CelestialBody,
        transformer: CoordinateTransformer,
        maxExtent: Double,
        isAbsorbed: Bool,
        albedo: Double = HabitableZonePhysics.bondAlbedo
    ) -> HabitableZoneProjection {
        let normal = orbitalNormal(star: star, planet: planet)
        let ring = { (radius: Double) in
            HabitableZonePhysics.ringPoints(
                center: star.position, normal: normal, radius: radius, samples: ringSamples
            ).map(transformer.simulationToCanvas)
        }
        let distanceAU = (planet.position - star.position).magnitude / CelestialConstants.baseAU
        return HabitableZoneProjection(
            innerRing: ring(zone.innerPx),
            outerRing: ring(zone.outerPx),
            status: isAbsorbed ? nil : zone.status(atDistanceAU: distanceAU),
            equilibriumTemperature: isAbsorbed ? nil : HabitableZonePhysics.equilibriumTemperature(
                luminosity: zone.luminosity, distanceAU: distanceAU, albedo: albedo
            ),
            isOffScreen: zone.innerPx > maxExtent * offScreenFactor
        )
    }

    /// Unit normal of the planet's orbital plane, (r₂ − r₁) × (v₂ − v₁).
    /// Conserved under the central GR force, so the band follows any inclination.
    /// Falls back to ẑ when degenerate (e.g. after absorption).
    static func orbitalNormal(star: CelestialBody, planet: CelestialBody) -> Vector3D {
        let angularMomentum = (planet.position - star.position).cross(planet.velocity - star.velocity)
        guard angularMomentum.magnitude > 1e-9 else { return Vector3D(x: 0, y: 0, z: 1) }
        return angularMomentum.normalized
    }
}
