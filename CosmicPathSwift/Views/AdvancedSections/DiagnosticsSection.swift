//
//  DiagnosticsSection.swift
//  CosmicPathSwift
//
//  "Diagnostics" section of the Advanced sheet (issue #20, PR 6): energy and
//  angular-momentum drift charts, the 2-body orbital elements, measured vs
//  predicted precession, and the CSV export of the recorded run.
//

import Charts
import SwiftUI

struct DiagnosticsSection: View {
    let viewModel: SimulationViewModel

    var body: some View {
        Section {
            driftCharts
            if !viewModel.isThreeBodyMode {
                orbitalElementsRow
                precessionRow
            }
            exportRow
        } header: {
            Text("Diagnostics")
        }
    }

    // MARK: - Drift

    @ViewBuilder
    private var driftCharts: some View {
        let points = DriftChart.points(from: viewModel.diagnostics.samples)
        CaptionedRow("Conservation", caption: driftCaption) {
            DriftChart(title: "ΔE/E", points: points.map { ($0.time, $0.energy) })
            DriftChart(title: "ΔL/L", points: points.map { ($0.time, $0.angularMomentum) })
        }
    }

    private var driftCaption: String {
        if viewModel.isThreeBodyMode {
            return "ΔE/E is the Newtonian energy, so it also drifts because of the GR term. Total angular momentum is exactly conserved, so ΔL/L is pure integrator error. Merges are excluded from both."
        }
        return "Energy and angular momentum of the relative orbit are exactly conserved by the force law, so any drift is integrator error. Compare integrators here."
    }

    // MARK: - Orbit

    private var orbitalElementsRow: some View {
        CaptionedRow(
            "Orbital Elements",
            caption: "Osculating Newtonian elements of the current state; GR makes them wobble slightly around each orbit."
        ) {
            if let elements = viewModel.orbitalElements {
                HStack {
                    valueColumn("a", elements.isBound ? Self.au(elements.semiMajorAxis) : "unbound")
                    valueColumn("e", String(format: "%.3f", elements.eccentricity))
                    valueColumn("T", elements.period.map { String(format: "%.1f", $0) } ?? "—")
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private var precessionRow: some View {
        CaptionedRow(
            "Precession per Orbit",
            caption: "6πGM/(c²a(1−e²)) is the weak-field formula. With the app's strong GR, the next-order term adds about (18+e²)/4 · GM/(c²p): roughly 8% at 1 AU. Widen the orbit to see them converge."
        ) {
            if let comparison = viewModel.precessionComparison {
                HStack {
                    valueColumn("Measured", String(format: "%.2f°", comparison.measuredPerOrbit))
                    valueColumn("Predicted", String(format: "%.2f°", comparison.predictedPerOrbit))
                    valueColumn("Ratio", String(format: "×%.3f", comparison.ratio))
                }
            } else {
                Text("— (after the first full orbit)").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Export

    private var exportRow: some View {
        let samples = viewModel.diagnostics.samples
        return CaptionedRow("Export", caption: "Positions, velocities and drift for the recorded run.") {
            ShareLink(
                item: DiagnosticsExport(samples: samples, config: viewModel.config),
                preview: SharePreview("Run data (CSV)")
            ) {
                Label("Export CSV (\(samples.count) samples)", systemImage: "square.and.arrow.up")
            }
            .disabled(samples.isEmpty)
        }
    }

    // MARK: - Helpers

    private func valueColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Semi-major axis in AU, e.g. "1.002 AU".
    private static func au(_ pixels: Double) -> String {
        String(format: "%.3f AU", pixels / CelestialConstants.baseAU)
    }
}

// MARK: - DriftChart

/// Small line chart of one drift quantity against simulated time. Tap or drag
/// to read the value at a time; otherwise the latest value is shown.
private struct DriftChart: View {
    let title: String
    let points: [(time: Double, value: Double)]

    @State private var selectedTime: Double?

    /// Most points drawn per chart, so it stays cheap to redraw every frame.
    static let maxPoints = 200

    /// Time and both drifts, thinned to at most `maxPoints` evenly spaced samples.
    static func points(from samples: [DiagnosticsSample]) -> [(time: Double, energy: Double, angularMomentum: Double)] {
        let step = max(1, Int((Double(samples.count) / Double(maxPoints)).rounded(.up)))
        return Swift.stride(from: 0, to: samples.count, by: step).map { index in
            let sample = samples[index]
            return (sample.time, sample.energyDrift, sample.angularMomentumDrift)
        }
    }

    private var readout: (time: Double, value: Double)? {
        guard let selectedTime else { return points.last }
        return points.min { abs($0.time - selectedTime) < abs($1.time - selectedTime) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                if let readout {
                    Text(String(format: "%.3g  at t = %.1f", readout.value, readout.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points.indices, id: \.self) { index in
                LineMark(x: .value("Time", points[index].time), y: .value(title, points[index].value))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.tint)
            }
            if let selectedTime {
                RuleMark(x: .value("Selected", selectedTime))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.notation(.scientific).precision(.significantDigits(2)))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
            }
        }
        .frame(height: 90)
        .accessibilityLabel("\(title) against time")
    }
}
