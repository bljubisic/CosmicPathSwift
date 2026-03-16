//
//  MetricsPanelView.swift
//  CosmicPathSwift
//
//  Displays real-time relativistic metrics: time dilation,
//  precession, velocity fraction of c, and Lorentz gamma / Schwarzschild radius.
//

import SwiftUI

struct MetricsPanelView: View {
    let viewModel: SimulationViewModel

    var body: some View {
        HStack(spacing: 0) {
            metricItem(
                label: "Time Dilation",
                value: String(format: "\u{03C4}/t = %.3f", viewModel.metrics.timeDilationFactor),
                color: viewModel.metrics.timeDilationColor
            )
            Spacer()
            metricItem(
                label: "Precession",
                value: String(format: "%.2f\u{00B0}", viewModel.metrics.precessionAngle),
                color: .yellow
            )
            Spacer()
            metricItem(
                label: "v/c",
                value: String(format: "%.3f", viewModel.metrics.velocityFractionOfC),
                color: .green
            )
            Spacer()
            if viewModel.metrics.isBlackHole {
                metricItem(
                    label: "r\u{209B} (px)",
                    value: String(format: "%.1f", viewModel.metrics.schwarzschildRadius),
                    color: .red
                )
            } else {
                metricItem(
                    label: "Lorentz \u{03B3}",
                    value: String(format: "%.4f", viewModel.metrics.lorentzGamma),
                    color: .purple
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metricItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, design: .monospaced).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
