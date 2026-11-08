//
//  ScaleBadgeView.swift
//  CosmicPathSwift
//
//  One small line above the metrics saying which physics scale is active
//  (issue #21, PR 2), so Visual's magnified GR is never mistaken for reality.
//

import SwiftUI

/// "Visual · GR magnified ≈ 1.7 million×", "Realistic · 1 s = 1 month · sizes not to scale"
/// or, in strong field, "Realistic · 10 M☉ black hole · 1 s = 10 ms · sizes not to scale".
struct ScaleBadgeView: View {
    let viewModel: SimulationViewModel

    var body: some View {
        Text(Self.text(config: viewModel.config, achievedRate: viewModel.achievedRealTimeRate))
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.6)   // the strong-field text is longer; stay on one line
            .accessibilityLabel("Physics scale")
            .accessibilityValue(Self.text(config: viewModel.config, achievedRate: viewModel.achievedRealTimeRate))
    }

    /// The badge text for `config`. `achievedRate` (simulated s per real s) is
    /// shown instead of the chosen rate while the CPU limits the speed.
    static func text(config: SimulationConfig, achievedRate: Double?) -> String {
        switch config.advanced.scale {
        case .visual:
            let factor = ScaleComparison.grMagnification(config: config)
            return "Visual · GR magnified ≈ \(RealUnitsFormatter.magnification(factor))"
        case .realistic:
            let blackHole = config.isStrongField ? "\(config.strongFieldMassLabel) black hole · " : ""
            return "Realistic · \(blackHole)\(rateText(config: config, achievedRate: achievedRate)) · sizes not to scale"
        }
    }

    private static func rateText(config: SimulationConfig, achievedRate: Double?) -> String {
        guard let achievedRate else {
            return config.advanced.time.activeRate(strongField: config.isStrongField).label
        }
        return "1 s = " + RealUnitsFormatter.duration(achievedRate / config.scale.units.secondsPerTime,
                                                      units: config.scale.units) + " (CPU-limited)"
    }
}
