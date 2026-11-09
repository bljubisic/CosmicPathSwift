//
//  MetricsPanelView.swift
//  CosmicPathSwift
//
//  Displays real-time metrics. 2-body: time dilation, precession, velocity
//  fraction of c, and Lorentz gamma / Schwarzschild radius. 3-body: elapsed
//  time, energy drift, closest approach, peak v/c, and system status.
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

    private var text: MetricsText { MetricsText(config: viewModel.config) }

    var body: some View {
        VStack(spacing: 3) {
            ScaleBadgeView(viewModel: viewModel)
            if viewModel.isThreeBodyMode {
                threeBodyMetrics
            } else {
                twoBodyMetrics
            }
        }
    }

    // MARK: - 3-Body Metrics

    /// Time, ΔE/E (Newtonian, includes the GR term's drift), closest approach,
    /// peak v/c, and Bound / Ejected / Merged status.
    private var threeBodyMetrics: some View {
        let metrics = viewModel.systemMetrics
        return HStack(spacing: 0) {
            metricItem(label: "Time", value: text.elapsedTime(metrics), color: .white)
            Spacer()
            metricItem(
                label: "\u{0394}E/E (GR)",
                value: String(format: "%+.2f%%", metrics.energyDrift * 100),
                color: .yellow
            )
            Spacer()
            metricItem(
                label: "Closest r",
                value: text.closestApproach(metrics),
                color: .cyan
            )
            Spacer()
            metricItem(
                label: "max v/c",
                value: text.velocityFraction(metrics.maxVelocityFractionOfC),
                color: .green
            )
            Spacer()
            metricItem(label: "Status", value: metrics.statusLabel, color: statusColor(metrics))
        }
    }

    private func statusColor(_ metrics: SystemMetrics) -> Color {
        if metrics.collision != nil { return .red }
        if metrics.ejectedBodyID != nil { return .orange }
        return .green
    }

    // MARK: - 2-Body Metrics

    private var twoBodyMetrics: some View {
        let metrics = viewModel.metrics
        let orbits = text.orbits(metrics)
        let lorentz = text.lorentz(metrics)
        return HStack(spacing: 0) {
            // Orbits completed (Visual) or elapsed time with the orbit count (Realistic)
            metricItem(label: orbits.label, value: orbits.value, color: .white)
            Spacer()
            // Gravitational time dilation: τ/t = √(1 - rₛ/r)
            metricItem(
                label: text.timeDilationLabel,
                value: text.timeDilation(metrics),
                color: metrics.timeDilationColor
            )
            Spacer()
            // Accumulated perihelion precession angle (degrees, or ″ / ′ in Realistic)
            metricItem(
                label: text.precessionLabel(metrics),
                value: text.precession(metrics),
                color: .yellow
            )
            Spacer()
            // Orbital velocity as fraction of c (β = v/c)
            metricItem(
                label: "v/c",
                value: text.velocityFraction(metrics.velocityFractionOfC),
                color: .green
            )
            Spacer()
            // Context-dependent fourth metric:
            // Black hole mode → Schwarzschild radius (simulation units, or km in Realistic)
            // Normal mode → Lorentz factor γ = 1/√(1 - v²/c²)
            if viewModel.metrics.isBlackHole {
                let rs = text.schwarzschildRadius(metrics)
                metricItem(label: rs.label, value: rs.value, color: .red)
            } else {
                metricItem(label: lorentz.label, value: lorentz.value, color: .purple)
            }
        }
    }

    /// Renders a single metric as a vertically stacked value + label pair.
    private func metricItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, design: .monospaced).bold())
                .foregroundStyle(color)
                // Realistic values ("1 − 9.9×10⁻⁹") are longer; shrink rather than wrap.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
