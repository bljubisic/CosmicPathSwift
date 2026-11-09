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
        let timeUnit = viewModel.config.scale.units.timeSymbol
        CaptionedRow("Conservation", caption: driftCaption) {
            DriftChart(title: "ΔE/E", timeUnit: timeUnit, points: points.map { ($0.time, $0.energy) })
            DriftChart(title: "ΔL/L", timeUnit: timeUnit, points: points.map { ($0.time, $0.angularMomentum) })
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
                    valueColumn("a", elements.isBound ? semiMajorAxisText(elements.semiMajorAxis) : "unbound")
                    valueColumn("e", String(format: "%.3f", elements.eccentricity))
                    valueColumn("T", elements.period.map(periodText) ?? "—")
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    /// Period: plain simulation units in Visual, days or years in Realistic.
    private func periodText(_ period: Double) -> String {
        let config = viewModel.config
        guard config.isRealistic else { return String(format: "%.1f", period) }
        return RealUnitsFormatter.duration(period, units: config.scale.units)
    }

    @ViewBuilder
    private var precessionRow: some View {
        // Strong-field precession is degrees per orbit, like Visual's; S2's is arcminutes.
        if viewModel.config.isGalacticCenter {
            galacticCenterPrecessionRow
        } else if viewModel.config.isRealistic && !viewModel.config.isStrongField {
            realisticPrecessionRow
        } else {
            visualPrecessionRow
        }
    }

    private var visualPrecessionRow: some View {
        CaptionedRow(
            "Precession per Orbit",
            caption: visualPrecessionCaption
        ) {
            if let comparison = viewModel.precessionComparison {
                HStack {
                    valueColumn("Measured", angleText(degrees: comparison.measuredPerOrbit))
                    valueColumn("Predicted", angleText(degrees: comparison.predictedPerOrbit))
                    valueColumn("Ratio", String(format: "×%.3f", comparison.ratio))
                }
            } else {
                Text("— (after the first full orbit)").foregroundStyle(.secondary)
            }
        }
    }

    /// Degrees, or arcseconds for the planet around a stellar black hole, whose
    /// precession is tens of arcseconds per orbit.
    private func angleText(degrees: Double) -> String {
        Self.angleText(degrees: degrees, arcseconds: viewModel.config.isBlackHolePlanet)
    }

    static func angleText(degrees: Double, arcseconds: Bool) -> String {
        arcseconds ? RealUnitsFormatter.arcseconds(degrees: degrees) : String(format: "%.2f°", degrees)
    }

    private var visualPrecessionCaption: String {
        if viewModel.config.isBlackHolePlanet {
            return "6πGM/(c²a(1−e²)), GR's weak-field formula, is accurate this far from the hole. At the default accuracy the integrator's own error makes the measurement about 15% low; Yoshida 4 at Accuracy ×¼ is within a few percent."
        }
        if viewModel.config.isStrongField {
            return "6πGM/(c²a(1−e²)) is the weak-field formula. Close to the hole the next-order term, about (18+e²)/4 · GM/(c²p), grows large: widen the orbit to see them converge."
        }
        return "6πGM/(c²a(1−e²)) is the weak-field formula. With the app's strong GR, the next-order term adds about (18+e²)/4 · GM/(c²p): roughly 8% at 1 AU. Widen the orbit to see them converge."
    }

    /// S2 around Sgr A*: arcminutes per orbit, next to GR's prediction.
    private var galacticCenterPrecessionRow: some View {
        CaptionedRow(
            "Precession per Orbit",
            caption: "GR predicts 6πGM/(c²a(1−e²)) ≈ 12′ per 16-year orbit. The GRAVITY collaboration measured S2's precession in 2020 and found it agrees with GR."
        ) {
            if let comparison = viewModel.precessionComparison {
                HStack {
                    valueColumn("Measured", Self.arcminutes(degrees: comparison.measuredPerOrbit))
                    valueColumn("Predicted", Self.arcminutes(degrees: comparison.predictedPerOrbit))
                    valueColumn("Ratio", String(format: "×%.3f", comparison.ratio))
                }
            } else {
                Text("— (after the first full orbit, 16 years)").foregroundStyle(.secondary)
            }
        }
    }

    /// An angle in arcminutes, e.g. "12.2′".
    static func arcminutes(degrees: Double) -> String {
        String(format: "%.1f\u{2032}", degrees * 60)
    }

    /// Realistic: arcseconds per orbit and per century, measured next to GR's prediction.
    private var realisticPrecessionRow: some View {
        CaptionedRow(
            "Precession",
            caption: "GR predicts 6πGM/(c²a(1−e²)): Mercury's 0.1″ per orbit, 43″ per century. Every integrator also precesses the orbit by itself, and at the default accuracy that hides GR (Verlet: degrees per century). Yoshida 4 at Accuracy ×¼ measures it to about 1%."
        ) {
            if let comparison = viewModel.precessionComparison {
                let units = viewModel.config.scale.units
                let period = viewModel.orbitalElements?.period
                HStack {
                    valueColumn("Measured", RealUnitsFormatter.arcseconds(degrees: comparison.measuredPerOrbit) + "/orbit")
                    valueColumn("Predicted", RealUnitsFormatter.arcseconds(degrees: comparison.predictedPerOrbit) + "/orbit")
                    valueColumn("Ratio", String(format: "×%.3g", comparison.ratio))
                }
                HStack {
                    valueColumn("", RealUnitsFormatter.perCentury(
                        degreesPerOrbit: comparison.measuredPerOrbit, period: period, units: units))
                    valueColumn("", RealUnitsFormatter.perCentury(
                        degreesPerOrbit: comparison.predictedPerOrbit, period: period, units: units))
                    Spacer().frame(maxWidth: .infinity)
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

    /// Semi-major axis in AU ("1.002 AU"), or in rₛ in strong field ("8.00 rₛ").
    private func semiMajorAxisText(_ length: Double) -> String {
        let config = viewModel.config
        guard !config.isStrongField else { return config.distanceLabel(simulationLength: length) }
        return String(format: "%.3f AU", length / config.scale.au)
    }
}

// MARK: - DriftChart

/// Small line chart of one drift quantity against simulated time. Tap or drag
/// to read the value at a time; otherwise the latest value is shown.
private struct DriftChart: View {
    let title: String
    /// Unit of the time axis ("days"), or empty for Visual's simulation units.
    let timeUnit: String
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
                    Text(String(format: "%.3g  at t = %.1f", readout.value, readout.time) + timeSuffix)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            chart
        }
    }

    private var timeSuffix: String { timeUnit.isEmpty ? "" : " " + timeUnit }

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
        .chartXAxisLabel(timeUnit.isEmpty ? "t" : "t (\(timeUnit))", alignment: .trailing)
        .frame(height: 90)
        .accessibilityLabel("\(title) against time")
    }
}
