//
//  ScaleProfile.swift
//  CosmicPathSwift
//
//  Everything one physics scale needs, as one value (issue #21).
//
//  The engine is unit-agnostic: it only uses G, c², the softening length and
//  the bodies' masses and positions. A `ScaleProfile` bundles those constants
//  with the slider-unit conversions (M☉, M⊕, AU → simulation units) and the
//  few rules that used to be written in screen pixels (black hole threshold,
//  star surface, Roche radius, merge distance).
//
//  `ScaleProfile.visual` reproduces the original app exactly:
//  G = 500, c = 200, 1 M☉ = 200, 1 M⊕ = 5, 1 AU = 150 px.
//

import Foundation

// MARK: - PhysicalConstants

/// G and c in the profile's simulation units.
struct PhysicalConstants: Equatable, Sendable {
    /// Gravitational constant.
    let G: Double
    /// Speed of light.
    let c: Double

    /// c², used by the GR term and every radius derived from rₛ.
    var cSquared: Double { c * c }

    /// Schwarzschild radius rₛ = 2GM/c² of `mass`.
    func schwarzschildRadius(mass: Double) -> Double {
        2.0 * G * mass / cSquared
    }

    /// The original scaled constants: rₛ = M/40, so 1 M☉ (200) has rₛ = 5 px.
    static let visual = PhysicalConstants(G: 500, c: 200)
}

// MARK: - UnitSystem

/// What one simulation unit of length, mass and time is in SI.
/// Used for display conversion only; the physics never reads it.
struct UnitSystem: Equatable, Sendable {
    let metersPerLength: Double
    let kilogramsPerMass: Double
    let secondsPerTime: Double
    /// Symbol shown next to raw simulation lengths ("px", "AU", "GM/c²").
    let lengthSymbol: String
    /// Name of the simulation time unit ("days"), or empty when it has no
    /// everyday meaning (Visual's time unit).
    var timeSymbol: String = ""
}

// MARK: - Rules

/// When the central body counts as a black hole (2-body, Black Hole Mode on).
enum BlackHoleRule: Equatable, Sendable {
    /// Only when rₛ is at least this many simulation units, so it is visible.
    case minimumRadius(Double)
    /// Always: the body is a black hole because Black Hole Mode says so.
    case byObjectType

    func isBlackHole(schwarzschildRadius rs: Double, isBlackHoleMode: Bool) -> Bool {
        guard isBlackHoleMode else { return false }
        switch self {
        case .minimumRadius(let threshold): return rs >= threshold
        case .byObjectType: return true
        }
    }
}

/// Radius of a planet, used by the Roche limit.
enum PlanetRadiusRule: Equatable, Sendable {
    /// A fixed proxy radius. The Roche limit floors the planet mass at
    /// `massFloor`, so a stripped planet's limit can't grow without bound.
    case fixedProxy(radius: Double, massFloor: Double)
    /// R = R⊕ × (m / M⊕)^exponent, the rocky-planet mass–radius relation.
    /// Masses below `massFloor` use the floor, like `fixedProxy`.
    case massPower(radiusAtEarthMass: Double, earthMass: Double, exponent: Double, massFloor: Double)

    /// Smallest planet mass used in the Roche limit's (2M/m)^⅓.
    var rocheMassFloor: Double {
        switch self {
        case .fixedProxy(_, let massFloor): return massFloor
        case .massPower(_, _, _, let massFloor): return massFloor
        }
    }

    func radius(planetMass: Double) -> Double {
        switch self {
        case .fixedProxy(let radius, _):
            return radius
        case .massPower(let radiusAtEarthMass, let earthMass, let exponent, let massFloor):
            return radiusAtEarthMass * pow(max(planetMass, massFloor) / earthMass, exponent)
        }
    }
}

/// Surface radius of a star, where an orbiting body hits it.
enum StarRadiusRule: Equatable, Sendable {
    /// max(2 rₛ, 2 × softening): grows with mass, never below the softening.
    case schwarzschildOrSoftening
    /// R = R☉ × (M / M☉)^exponent, the main-sequence mass–radius relation.
    case massPower(radiusAtSolarMass: Double, solarMass: Double, exponent: Double)

    func radius(mass: Double, schwarzschildRadius rs: Double, softening: Double) -> Double {
        switch self {
        case .schwarzschildOrSoftening:
            return max(2.0 * rs, softening * 2)
        case .massPower(let radiusAtSolarMass, let solarMass, let exponent):
            return radiusAtSolarMass * pow(max(mass, 0) / solarMass, exponent)
        }
    }

    /// True when the radius is a physical size, so two bodies touch when the
    /// sum of their radii is reached (rather than the larger of the two).
    var isPhysicalSize: Bool {
        switch self {
        case .schwarzschildOrSoftening: return false
        case .massPower: return true
        }
    }
}

/// Where the force-law softening length comes from.
enum SofteningRule: Equatable, Sendable {
    /// The Advanced sheet's Softening picker, never below `minimum`.
    case userChoice(minimum: Double)
    /// A fixed length; the picker is hidden.
    case fixed(Double)

    func length(for settings: EngineSettings) -> Double {
        switch self {
        case .userChoice(let minimum): return max(settings.softening, minimum)
        case .fixed(let length): return length
        }
    }
}

/// How the 2-body precession tracker measures the periapsis direction.
enum PerihelionMethod: Equatable, Sendable {
    /// atan2 of the planet's position at the sampled separation minimum.
    /// Quantised by the step (≈ 0.2° at 1,800 steps per orbit), which is fine
    /// when GR precession is degrees per orbit.
    case sampledPosition
    /// Direction of the eccentricity vector at that sample. It changes smoothly,
    /// so it resolves the 0.1″ per orbit of real GR.
    case eccentricityVector
}

// MARK: - ScaleProfile

/// Constants, unit conversions and size rules of one physics scale.
struct ScaleProfile: Equatable, Sendable {
    let constants: PhysicalConstants
    let units: UnitSystem

    /// Simulation mass of 1 M☉ (the star slider's unit).
    let solarMass: Double
    /// Simulation mass of 1 M⊕ (the planet slider's unit).
    let earthMass: Double
    /// Simulation length of 1 AU (the distance slider's unit).
    let au: Double
    /// Simulation mass of a 1× black hole in Black Hole Mode.
    let blackHoleBaseMass: Double
    /// Softening length used when the Advanced sheet doesn't override it.
    let defaultSoftening: Double

    let blackHoleRule: BlackHoleRule
    let planetRadius: PlanetRadiusRule
    let starRadius: StarRadiusRule
    let softeningRule: SofteningRule
    let perihelionMethod: PerihelionMethod

    /// Short description of the units, for the diagnostics CSV header.
    let unitsDescription: String

    // MARK: Derived rules

    /// Softening length the engine uses with `settings` in this scale.
    func softening(for settings: EngineSettings) -> Double {
        softeningRule.length(for: settings)
    }

    /// Radius at which an orbiting body hits a star of `mass`.
    func starSurfaceRadius(mass: Double, softening: Double) -> Double {
        starRadius.radius(mass: mass, schwarzschildRadius: constants.schwarzschildRadius(mass: mass),
                          softening: softening)
    }

    /// Roche limit r = R_planet × (2 M₁ / M₂)^⅓, inside which tides strip the planet.
    func rocheLimit(centralMass: Double, planetMass: Double) -> Double {
        planetRadius.radius(planetMass: planetMass)
            * pow(2.0 * centralMass / max(planetMass, planetRadius.rocheMassFloor), 1.0 / 3.0)
    }

    /// Distance at which two 3-body stars merge. Visual: the larger of their
    /// surface radii. Physical radii: their sum, i.e. the stars touch.
    func collisionDistance(massA: Double, massB: Double, softening: Double) -> Double {
        let radiusA = starSurfaceRadius(mass: massA, softening: softening)
        let radiusB = starSurfaceRadius(mass: massB, softening: softening)
        return starRadius.isPhysicalSize ? radiusA + radiusB : max(radiusA, radiusB)
    }

    // MARK: Profiles

    /// The original scale: GR effects magnified so they show at screen size.
    static let visual: ScaleProfile = {
        let solarMass = 200.0
        let au = 150.0
        let constants = PhysicalConstants.visual
        return ScaleProfile(
            constants: constants,
            units: UnitSystem(
                metersPerLength: SIConstants.astronomicalUnit / au,
                kilogramsPerMass: SIConstants.solarMass / solarMass,
                secondsPerTime: SIConstants.julianYear / keplerPeriod(au: au, solarMass: solarMass, G: constants.G),
                lengthSymbol: "px"
            ),
            solarMass: solarMass,
            earthMass: 5,
            au: au,
            blackHoleBaseMass: 5000,
            defaultSoftening: 5,
            blackHoleRule: .minimumRadius(8),
            planetRadius: .fixedProxy(radius: 10, massFloor: 0.1),
            starRadius: .schwarzschildOrSoftening,
            softeningRule: .userChoice(minimum: EngineSettings.minimumSoftening),
            perihelionMethod: .sampledPosition,
            unitsDescription: "simulation (G = 500, c = 200, 1 AU = 150 px)"
        )
    }()

    /// Period 2π√(a³/GM) of a 1 AU orbit around 1 M☉ in a profile's units.
    /// Visual maps it to one year, so its time unit has a real meaning.
    private static func keplerPeriod(au: Double, solarMass: Double, G: Double) -> Double {
        2 * .pi * sqrt(au * au * au / (G * solarMass))
    }
}

// MARK: - SIConstants

/// Reference SI values used to convert simulation units for display.
enum SIConstants {
    static let solarMass: Double = 1.98847e30
    static let earthMass: Double = 5.9722e24
    static let astronomicalUnit: Double = 1.495978707e11
    static let julianYear: Double = 365.25 * 86_400
    static let gravitationalConstant: Double = 6.67430e-11
    static let speedOfLight: Double = 299_792_458
    static let secondsPerDay: Double = 86_400
    /// Days in a Julian century, the unit of published precession rates.
    static let daysPerJulianCentury: Double = 36_525
    /// Gaussian gravitational constant k, in AU^1.5 / (M☉^0.5 · day).
    static let gaussianGravitationalConstant: Double = 0.01720209895
    static let solarRadius: Double = 6.957e8
    static let earthRadius: Double = 6.3781e6
    static let kilometer: Double = 1_000
}
