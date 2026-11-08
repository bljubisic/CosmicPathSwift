//
//  SimulationConfig+StrongField.swift
//  CosmicPathSwift
//
//  Helpers for the Realistic strong-field setup (issue #21, PR 3): Realistic
//  scale, 2-body mode and Black Hole Mode on. The physics then runs in
//  geometric units (`ScaleProfile.realisticStrongField`), the BH Mass slider is
//  in real M☉ and the Distance slider in Schwarzschild radii.
//

import Foundation

extension SimulationConfig {

    /// True in the Realistic strong-field setup: Realistic, 2-body, Black Hole Mode on.
    var isStrongField: Bool {
        isRealistic && mode == .twoBody && isBlackHoleMode
    }

    /// rₛ = 2GM/c² of the strong-field black hole, in GM☉/c² (= 2M with G = c = 1).
    var strongFieldSchwarzschildRadius: Double {
        ScaleProfile.realisticStrongField.constants.schwarzschildRadius(
            mass: strongFieldBlackHoleMass * ScaleProfile.realisticStrongField.solarMass
        )
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
    }

    // MARK: - Labels

    /// BH Mass slider text, e.g. "10 M☉".
    var strongFieldMassLabel: String {
        String(format: strongFieldBlackHoleMass < 10 ? "%.1f M\u{2609}" : "%.0f M\u{2609}", strongFieldBlackHoleMass)
    }

    /// Distance slider text, e.g. "8.0 rₛ".
    var strongFieldDistanceLabel: String {
        String(format: strongFieldDistanceRs < 10 ? "%.1f r\u{209B}" : "%.0f r\u{209B}", strongFieldDistanceRs)
    }

    /// A simulation length in the units the user set it in: "2.50 rₛ" in
    /// strong field, "0.39 AU" otherwise.
    func distanceLabel(simulationLength length: Double) -> String {
        if isStrongField {
            return String(format: "%.2f r\u{209B}", length / strongFieldSchwarzschildRadius)
        }
        return String(format: "%.2f AU", length / scale.au)
    }
}
