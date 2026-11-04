//
//  HabitableZone.swift
//  CosmicPathSwift
//
//  Habitable-zone model for the central body in 2-body mode: luminosity of a
//  star (mass–luminosity relation) or an accreting black hole (fraction of the
//  Eddington limit), the conservative habitable-zone bounds, and the planet's
//  equilibrium temperature.
//
//  All physical quantities are expressed in the units shown on the sliders
//  (M☉, AU, L☉) rather than the compressed simulation constants, so the zone
//  stays consistent with what the user sees. Convert to simulation pixels with
//  `CelestialConstants.baseAU`.
//

import Foundation

// MARK: - HabitableStatus

/// Where the planet sits relative to the habitable zone.
enum HabitableStatus: Equatable, Sendable {
    case tooHot
    case habitable
    case tooCold

    var label: String {
        switch self {
        case .tooHot: return "Too hot"
        case .habitable: return "Habitable"
        case .tooCold: return "Too cold"
        }
    }
}

// MARK: - HabitableZone

/// Habitable-zone bounds for a central body of a given luminosity.
struct HabitableZone: Equatable, Sendable {
    /// Luminosity of the central body in L☉.
    let luminosity: Double
    /// Inner (hot) edge in AU.
    let innerAU: Double
    /// Outer (cold) edge in AU.
    let outerAU: Double

    init(luminosity: Double) {
        self.luminosity = luminosity
        self.innerAU = HabitableZonePhysics.distanceAU(luminosity: luminosity, flux: HabitableZonePhysics.innerFlux)
        self.outerAU = HabitableZonePhysics.distanceAU(luminosity: luminosity, flux: HabitableZonePhysics.outerFlux)
    }

    /// Inner edge in simulation pixels.
    var innerPx: Double { innerAU * CelestialConstants.baseAU }

    /// Outer edge in simulation pixels.
    var outerPx: Double { outerAU * CelestialConstants.baseAU }

    /// Classifies a planet at `distanceAU` from the central body.
    func status(atDistanceAU distanceAU: Double) -> HabitableStatus {
        if distanceAU < innerAU { return .tooHot }
        if distanceAU > outerAU { return .tooCold }
        return .habitable
    }

    /// Zone for body1 as configured: a main-sequence star, or an accreting
    /// black hole when `isBlackHoleMode` is on.
    static func forCentralBody(of config: SimulationConfig) -> HabitableZone {
        let mass = config.mass1Multiplier
        let luminosity = config.isBlackHoleMode
            ? HabitableZonePhysics.blackHoleLuminosity(solarMasses: mass, eddingtonFraction: config.accretionEddingtonFraction)
            : HabitableZonePhysics.starLuminosity(solarMasses: mass)
        return HabitableZone(luminosity: luminosity)
    }
}

// MARK: - HabitableZonePhysics

/// Pure functions behind the habitable-zone model.
enum HabitableZonePhysics {

    /// Stellar flux (in units of Earth's insolation) at the inner edge —
    /// runaway greenhouse limit (Kasting 1993 / Kopparapu 2013, conservative).
    static let innerFlux: Double = 1.1

    /// Stellar flux at the outer edge — maximum greenhouse limit.
    static let outerFlux: Double = 0.53

    /// Eddington luminosity per solar mass, in L☉ (≈ 1.26×10³¹ W / 3.83×10²⁶ W).
    static let eddingtonLuminosityPerSolarMass: Double = 3.2e4

    /// Bond albedo used for the equilibrium temperature (Earth-like).
    static let bondAlbedo: Double = 0.3

    /// Equilibrium temperature of a zero-albedo body at 1 AU from the Sun (K).
    static let blackBodyTemperatureAt1AU: Double = 278.6

    /// Coefficient of the 2–55 M☉ branch. The textbook value is 1.4; using
    /// 16 / 2^3.5 ≈ 1.414 makes the relation continuous (and monotonic) at 2 M☉.
    private static let intermediateMassCoefficient: Double = 16 / pow(2, 3.5)

    /// Main-sequence luminosity in L☉ from the piecewise mass–luminosity relation.
    static func starLuminosity(solarMasses mass: Double) -> Double {
        switch mass {
        case ..<0.43: return 0.23 * pow(mass, 2.3)
        case ..<2: return pow(mass, 4)
        case ..<55: return intermediateMassCoefficient * pow(mass, 3.5)
        default: return 32000 * mass
        }
    }

    /// Accretion-disk luminosity in L☉: a fraction of the Eddington limit.
    static func blackHoleLuminosity(solarMasses mass: Double, eddingtonFraction: Double) -> Double {
        eddingtonFraction * eddingtonLuminosityPerSolarMass * mass
    }

    /// Distance (AU) at which a body of `luminosity` delivers `flux` (Earth units).
    static func distanceAU(luminosity: Double, flux: Double) -> Double {
        sqrt(max(luminosity, 0) / flux)
    }

    /// Planetary equilibrium temperature (K): T = 278.6 · (1 − A)^¼ · L^¼ / √d.
    static func equilibriumTemperature(luminosity: Double, distanceAU: Double) -> Double {
        guard distanceAU > 0 else { return .infinity }
        return blackBodyTemperatureAt1AU * pow(1 - bondAlbedo, 0.25) * pow(max(luminosity, 0), 0.25) / sqrt(distanceAU)
    }

    /// Points on a circle of `radius` around `center`, in the plane perpendicular
    /// to `normal`. A degenerate (zero) normal falls back to ẑ.
    static func ringPoints(center: Vector3D, normal: Vector3D, radius: Double, samples: Int) -> [Vector3D] {
        let (e1, e2) = planeBasis(normal: normal)
        return (0..<max(samples, 0)).map { index in
            let angle = 2 * .pi * Double(index) / Double(samples)
            return center + radius * (cos(angle) * e1 + sin(angle) * e2)
        }
    }

    /// Orthonormal basis (e₁, e₂) spanning the plane perpendicular to `normal`.
    private static func planeBasis(normal: Vector3D) -> (Vector3D, Vector3D) {
        let unitZ = Vector3D(x: 0, y: 0, z: 1)
        let n = normal.magnitude > 0 ? normal.normalized : unitZ
        // n × x̂ is degenerate when n ∥ x̂; fall back to n × ŷ.
        var e1 = n.cross(Vector3D(x: 1, y: 0, z: 0))
        if e1.magnitude < 1e-6 {
            e1 = n.cross(Vector3D(x: 0, y: 1, z: 0))
        }
        e1 = e1.normalized
        return (e1, n.cross(e1))
    }
}
