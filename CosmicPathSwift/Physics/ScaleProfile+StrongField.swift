//
//  ScaleProfile+StrongField.swift
//  CosmicPathSwift
//
//  The Realistic strong-field scale (issue #21, PR 3): a probe orbiting a
//  stellar black hole, in geometric units (G = c = 1).
//
//  The unit of length is GM☉/c² = 1476.6 m, of mass 1 M☉ and of time
//  GM☉/c³ = 4.9255 µs. A black hole of M solar masses then has rₛ = 2M,
//  its photon sphere at 3M and its ISCO at 6M, so a 10 M☉ hole and an orbit
//  at 8 rₛ (r = 160) are well-conditioned numbers. The mass goes into the
//  bodies, not the units, so one profile covers every black hole mass.
//
//  The force law is unchanged. Its effective potential is Schwarzschild's,
//  so the horizon, photon sphere and ISCO radii are exact; its circular
//  periods near the hole are shorter than GR's (29% at the ISCO).
//
//  `realisticStrongFieldPlanet` (PR 5) is the same scale with a real rocky
//  planet instead of the point-mass probe, so tides can tear it apart.
//

import Foundation

extension ScaleProfile {

    /// Real constants in GM☉/c², M☉ and GM☉/c³ (G = c = 1), with a point-mass probe.
    static let realisticStrongField = strongField(
        // The orbiter is a compact probe: no Roche limit, no tidal stripping.
        planetRadius: .pointMass,
        unitsDescription: "GM☉/c², M☉, GM☉/c³ (G = c = 1)"
    )

    /// The same units with a rocky planet (R ∝ M^0.27, like the planetary
    /// scale), so the Roche limit and tidal stripping apply. An Earth-mass
    /// planet is torn apart about 40,600 rₛ from a 10 M☉ black hole.
    static let realisticStrongFieldPlanet = strongField(
        planetRadius: .massPower(
            radiusAtEarthMass: SIConstants.earthRadius / SIConstants.solarGravitationalLength,
            earthMass: SIConstants.earthMass / SIConstants.solarMass,
            exponent: Realistic.planetRadiusExponent,
            massFloor: SIConstants.earthMass / SIConstants.solarMass * Realistic.planetMassFloorFraction
        ),
        unitsDescription: "GM☉/c², M☉, GM☉/c³ (G = c = 1), rocky planet"
    )

    private static func strongField(planetRadius: PlanetRadiusRule, unitsDescription: String) -> ScaleProfile {
        let lengthUnit = SIConstants.solarGravitationalLength
        return ScaleProfile(
            constants: PhysicalConstants(G: 1, c: 1),
            units: UnitSystem(
                metersPerLength: lengthUnit,
                kilogramsPerMass: SIConstants.solarMass,
                secondsPerTime: SIConstants.solarGravitationalTime,
                lengthSymbol: "GM☉/c²"
            ),
            solarMass: 1,
            earthMass: SIConstants.earthMass / SIConstants.solarMass,
            au: SIConstants.astronomicalUnit / lengthUnit,
            // `SimulationConfig.simulationMass1` uses the BH Mass slider (in M☉) directly.
            blackHoleBaseMass: 1,
            defaultSoftening: StrongField.softening,
            blackHoleRule: .byObjectType,
            planetRadius: planetRadius,
            // Unused: Black Hole Mode is always on here, so there is no star surface.
            starRadius: .schwarzschildOrSoftening,
            softeningRule: .fixed(StrongField.softening),
            perihelionMethod: .eccentricityVector,
            unitsDescription: unitsDescription
        )
    }

    /// Tuning values and slider ranges of the strong-field profile.
    enum StrongField {
        /// Fixed softening: 10⁻³ GM☉/c² ≈ 1.5 m, far below any horizon (rₛ ≥ 6 here).
        static let softening: Double = 1e-3
        /// BH Mass slider range, in M☉.
        static let blackHoleMassRange: ClosedRange<Double> = 3...100
        /// Distance slider range, in rₛ.
        static let distanceRangeRs: ClosedRange<Double> = 2...30
        /// Default black hole mass, in M☉.
        static let defaultBlackHoleMass: Double = 10
        /// Default orbit radius, in rₛ: stable, with a strongly precessing rosette.
        static let defaultDistanceRs: Double = 8
        /// Planet scenario's Distance slider range, in rₛ. The Roche limit of an
        /// Earth-mass planet is ≈ 90,000 rₛ at 3 M☉ and ≈ 8,800 rₛ at 100 M☉,
        /// so both sides of it are reachable for every black hole mass.
        static let planetDistanceRangeRs: ClosedRange<Double> = 1_000...300_000
        /// Default planet orbit, in rₛ: about 1.5× the Roche limit of an Earth-mass
        /// planet around the default 10 M☉, so it survives (a 3.6-hour orbit).
        static let defaultPlanetDistanceRs: Double = 60_000
    }
}
