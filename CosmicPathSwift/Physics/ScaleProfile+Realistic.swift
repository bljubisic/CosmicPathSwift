//
//  ScaleProfile+Realistic.swift
//  CosmicPathSwift
//
//  The Realistic planetary scale (issue #21, PR 2): real G, c, masses and
//  distances in astronomical units, solar masses and days.
//
//  In these units G is the square of the Gaussian gravitational constant,
//  k² = 2.9591220828×10⁻⁴ AU³/(M☉·day²), and c = 173.14 AU/day. The Sun's
//  Schwarzschild radius is then 1.97×10⁻⁸ AU (2.95 km): GR is about 1.7
//  million times weaker than in the Visual scale.
//

import Foundation

extension ScaleProfile {

    /// Real constants in AU, M☉ and days.
    static let realisticPlanetary: ScaleProfile = {
        let k = SIConstants.gaussianGravitationalConstant
        let au = SIConstants.astronomicalUnit
        let constants = PhysicalConstants(
            G: k * k,
            c: SIConstants.speedOfLight * SIConstants.secondsPerDay / au
        )
        let earthMass = SIConstants.earthMass / SIConstants.solarMass
        return ScaleProfile(
            constants: constants,
            units: UnitSystem(
                metersPerLength: au,
                kilogramsPerMass: SIConstants.solarMass,
                secondsPerTime: SIConstants.secondsPerDay,
                lengthSymbol: "AU",
                timeSymbol: "days"
            ),
            solarMass: 1,
            earthMass: earthMass,
            au: 1,
            // Black Hole Mode is hidden in Realistic (until PR 3), so this is unused.
            blackHoleBaseMass: 1,
            defaultSoftening: Realistic.softening,
            blackHoleRule: .byObjectType,
            planetRadius: .massPower(
                radiusAtEarthMass: SIConstants.earthRadius / au, earthMass: earthMass,
                exponent: Realistic.planetRadiusExponent, massFloor: earthMass * Realistic.planetMassFloorFraction
            ),
            starRadius: .massPower(
                radiusAtSolarMass: SIConstants.solarRadius / au, solarMass: 1,
                exponent: Realistic.starRadiusExponent
            ),
            softeningRule: .fixed(Realistic.softening),
            perihelionMethod: .eccentricityVector,
            unitsDescription: String(
                format: "AU, M☉, day (G = k², c = %.2f AU/day)", locale: Locale(identifier: "en_US_POSIX"), constants.c
            )
        )
    }()

    /// Tuning values of the Realistic profile.
    enum Realistic {
        /// Fixed softening: 10⁻⁶ AU ≈ 150 km, far below any stellar or planetary radius.
        static let softening: Double = 1e-6
        /// Main-sequence R ∝ M^0.8.
        static let starRadiusExponent: Double = 0.8
        /// Rocky-planet R ∝ M^0.27.
        static let planetRadiusExponent: Double = 0.27
        /// Smallest planet mass in the Roche limit, as a fraction of M⊕
        /// (Visual's 0.1 floor is 0.02 of its 5-unit Earth).
        static let planetMassFloorFraction: Double = 0.02
    }
}
