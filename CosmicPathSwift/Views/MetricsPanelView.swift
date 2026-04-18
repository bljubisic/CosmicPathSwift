//
//  MetricsPanelView.swift
//  CosmicPathSwift
//
//  Displays real-time relativistic metrics: time dilation,
//  precession, velocity fraction of c, and Lorentz gamma / Schwarzschild radius.
//

import SwiftUI

/// Read-only display of real-time relativistic metrics from the simulation.
///
/// Shows four metrics in a horizontal row:
/// 1. **Time Dilation** (τ/t) — gravitational time dilation factor, color-coded
///    from cyan (weak) to red (extreme) via `timeDilationColor`.
/// 2. **Precession** — accumulated perihelion advance in degrees.
/// 3. **v/c** — orbital speed as a fraction of the speed of light.
/// 4. **Lorentz γ** (normal mode) or **rₛ** (black hole mode) — the fourth
///    slot contextually shows the Lorentz factor or the Schwarzschild radius.
struct MetricsPanelView: View {
    let viewModel: SimulationViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Num of orbits completed (integer)
            metricItem(
                label: "Orbits",
                value: String(format: "%d", viewModel.metrics.orbitsCompleted),
                color: .white
            )
            // Gravitational time dilation: τ/t = √(1 - rₛ/r)
            metricItem(
                label: "Time Dilation",
                value: String(format: "\u{03C4}/t = %.3f", viewModel.metrics.timeDilationFactor),
                color: viewModel.metrics.timeDilationColor
            )
            Spacer()
            // Accumulated perihelion precession angle (degrees)
            metricItem(
                label: "Precession",
                value: String(format: "%.2f\u{00B0}", viewModel.metrics.precessionAngle),
                color: .yellow
            )
            Spacer()
            // Orbital velocity as fraction of c (β = v/c)
            metricItem(
                label: "v/c",
                value: String(format: "%.3f", viewModel.metrics.velocityFractionOfC),
                color: .green
            )
            Spacer()
            // Context-dependent fourth metric:
            // Black hole mode → Schwarzschild radius in simulation pixels
            // Normal mode → Lorentz factor γ = 1/√(1 - v²/c²)
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

    /// Renders a single metric as a vertically stacked value + label pair.
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
