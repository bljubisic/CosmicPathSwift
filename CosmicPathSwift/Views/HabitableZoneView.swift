//
//  HabitableZoneView.swift
//  CosmicPathSwift
//
//  Habitable-zone rendering for 2-body mode: a translucent green band between
//  the zone's inner and outer edges, drawn in the planet's orbital plane, plus
//  a status badge showing whether the planet is too hot, habitable, or too cold.
//

import SwiftUI

/// The habitable-zone band around body1.
///
/// Both rings are already projected to canvas space by the ViewModel, so the
/// band tilts with the camera and the orbital inclination and lines up with the
/// orbit trail. The annulus is filled with the even-odd rule. In black hole
/// mode, an inner edge inside the ISCO is drawn in orange to mark the part of
/// the zone where no stable orbit exists.
struct HabitableZoneView: View {
    let viewModel: SimulationViewModel

    private static let bandColor = Color.green
    private static let edgeStyle = StrokeStyle(lineWidth: 1, dash: [5, 4])

    var body: some View {
        let inner = Self.polygon(viewModel.habitableZoneInnerRing)
        let outer = Self.polygon(viewModel.habitableZoneOuterRing)
        let innerEdgeColor: Color = viewModel.isHabitableZoneInsideISCO ? .orange : Self.bandColor

        Canvas { context, _ in
            var band = outer
            band.addPath(inner)
            context.fill(band, with: .color(Self.bandColor.opacity(0.12)), style: FillStyle(eoFill: true))
            context.stroke(outer, with: .color(Self.bandColor.opacity(0.5)), style: Self.edgeStyle)
            context.stroke(inner, with: .color(innerEdgeColor.opacity(0.6)), style: Self.edgeStyle)
        }
        .allowsHitTesting(false)
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// Top-right badge describing the planet's position relative to the habitable
/// zone, e.g. "Habitable · 255 K" and "HZ 0.95–1.37 AU".
struct HabitableZoneBadge: View {
    let viewModel: SimulationViewModel

    var body: some View {
        if let zone = viewModel.habitableZone {
            VStack {
                HStack {
                    Spacer()
                    badge(zone: zone)
                }
                Spacer()
            }
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    private func badge(zone: HabitableZone) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let status = viewModel.habitableStatus {
                Text(statusText(status))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color(for: status))
            }
            Text(rangeText(zone))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.green.opacity(0.6))
            if viewModel.isHabitableZoneInsideISCO {
                Text("inside ISCO")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusText(_ status: HabitableStatus) -> String {
        guard let temperature = viewModel.planetEquilibriumTemperature, temperature.isFinite else {
            return status.label
        }
        return "\(status.label) · \(Int(temperature.rounded())) K"
    }

    private func rangeText(_ zone: HabitableZone) -> String {
        let range = "HZ \(Self.formatAU(zone.innerAU))–\(Self.formatAU(zone.outerAU)) AU"
        return viewModel.isHabitableZoneOffScreen ? range + " (off-screen)" : range
    }

    private static func formatAU(_ value: Double) -> String {
        value < 10 ? String(format: "%.2f", value) : String(format: "%.0f", value)
    }

    private func color(for status: HabitableStatus) -> Color {
        switch status {
        case .tooHot: return .orange
        case .habitable: return .green
        case .tooCold: return .cyan
        }
    }
}
