//
//  SimulationConfig+StrongField.swift
//  CosmicPathSwift
//
//  Helpers for the Realistic strong-field setup (issue #21, PR 3): Realistic
//  scale, 2-body mode and Black Hole Mode on. The physics then runs in
//  geometric units (`ScaleProfile.realisticStrongField`), the BH Mass slider is
//  in real M☉ and the Distance slider in Schwarzschild radii.
//
//  Three scenarios (`StrongFieldScenario`): a point-mass probe a few rₛ out
//  (strong-field GR), a rocky planet thousands of rₛ out (tides), and S2
//  around Sagittarius A* (`GalacticCenter`), with fixed observed values.
//

import Foundation

extension SimulationConfig {

    /// True in the Realistic strong-field setup: Realistic, 2-body, Black Hole Mode on.
    var isStrongField: Bool {
        isRealistic && mode == .twoBody && isBlackHoleMode
    }

    /// True when the strong-field setup shows S2 around Sagittarius A*.
    var isGalacticCenter: Bool {
        isStrongField && strongFieldScenario == .sagittariusAStar
    }

    /// True when the strong-field setup shows a rocky planet around a stellar black hole.
    var isBlackHolePlanet: Bool {
        isStrongField && strongFieldScenario == .blackHolePlanet
    }

    /// Mass of the strong-field black hole in M☉: the BH Mass slider, or Sgr A*.
    var strongFieldBlackHoleSolarMasses: Double {
        strongFieldScenario == .sagittariusAStar ? GalacticCenter.blackHoleMass : strongFieldBlackHoleMass
    }

    /// rₛ = 2GM/c² of the strong-field black hole, in GM☉/c² (= 2M with G = c = 1).
    var strongFieldSchwarzschildRadius: Double {
        ScaleProfile.realisticStrongField.constants.schwarzschildRadius(
            mass: strongFieldBlackHoleSolarMasses * ScaleProfile.realisticStrongField.solarMass
        )
    }

    /// Which family of Realistic time rates applies to this setup.
    var rateRegime: RateRegime {
        if isGalacticCenter { return .galacticCenter }
        if isBlackHolePlanet { return .blackHolePlanet }
        return isStrongField ? .stellarBlackHole : .planetary
    }

    /// Eccentricity of the 2-body starting orbit: S2's observed value, or the
    /// Advanced sheet's Eccentricity slider.
    var orbitEccentricity: Double {
        isGalacticCenter ? GalacticCenter.eccentricity : advanced.initial.eccentricity
    }

    /// Length the canvas sizes bodies against: the default orbit's 1 AU, or the
    /// orbit itself in strong field, where 1 AU is 10⁸ length units.
    var bodySizeReferenceLength: Double {
        isStrongField ? simulationSeparation : scale.au
    }

    /// Restores the strong-field sliders to their defaults (Black Hole Mode
    /// switched on in Realistic), the way Visual resets its own sliders.
    mutating func resetStrongFieldParameters() {
        let defaults = SimulationConfig()
        strongFieldBlackHoleMass = defaults.strongFieldBlackHoleMass
        strongFieldDistanceRs = defaults.strongFieldDistanceRs
        strongFieldPlanetDistanceRs = defaults.strongFieldPlanetDistanceRs
    }

    /// Roche limit of the planet in the Planet scenario, in rₛ: inside it,
    /// tides strip the planet. Barely depends on the planet's mass, because a
    /// heavier rocky planet is also larger (R ∝ M^0.27 against the limit's M^-⅓).
    var blackHolePlanetRocheLimitRs: Double {
        let profile = ScaleProfile.realisticStrongFieldPlanet
        let blackHole = strongFieldBlackHoleMass * profile.solarMass
        let planet = profile.earthMass * mass2Multiplier
        return profile.rocheLimit(centralMass: blackHole, planetMass: planet) / strongFieldSchwarzschildRadius
    }

    // MARK: - Labels

    /// BH Mass text, e.g. "10 M☉", or "4.3 million M☉" for Sgr A*.
    var strongFieldMassLabel: String {
        if strongFieldScenario == .sagittariusAStar {
            return String(format: "%.1f million M\u{2609}", GalacticCenter.blackHoleMass / 1e6)
        }
        return String(format: strongFieldBlackHoleMass < 10 ? "%.1f M\u{2609}" : "%.0f M\u{2609}", strongFieldBlackHoleMass)
    }

    /// Distance slider text, e.g. "8.0 rₛ".
    var strongFieldDistanceLabel: String {
        String(format: strongFieldDistanceRs < 10 ? "%.1f r\u{209B}" : "%.0f r\u{209B}", strongFieldDistanceRs)
    }

    /// Planet Distance slider text, e.g. "60,000 rₛ".
    var strongFieldPlanetDistanceLabel: String {
        Self.groupedInteger(strongFieldPlanetDistanceRs) + " r\u{209B}"
    }

    /// A whole number with comma thousands separators ("40,625"), independent of locale.
    static func groupedInteger(_ value: Double) -> String {
        let digits = String(Int(value.rounded()))
        var grouped = ""
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return String(grouped.reversed())
    }

    /// A simulation length in the units the user set it in: "2.50 rₛ" near a
    /// stellar black hole, "0.39 AU" otherwise (including S2, whose orbit is
    /// thousands of rₛ across and quoted in AU).
    func distanceLabel(simulationLength length: Double) -> String {
        if isStrongField && !isGalacticCenter {
            let radii = length / strongFieldSchwarzschildRadius
            // Planet orbits are thousands of rₛ: decimals would only add noise.
            return radii < 1_000 ? String(format: "%.2f r\u{209B}", radii) : Self.groupedInteger(radii) + " r\u{209B}"
        }
        return String(format: "%.2f AU", length / scale.au)
    }
}
