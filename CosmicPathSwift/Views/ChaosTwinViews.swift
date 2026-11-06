//
//  ChaosTwinViews.swift
//  CosmicPathSwift
//
//  Rendering for the 3-body chaos experiment (issue #20, PR 4): the
//  unperturbed twin drawn as a faint ghost, and a badge showing how far the
//  two runs have drifted apart.
//

import SwiftUI

/// The unperturbed twin: dashed trails and hollow circles in each body's
/// palette colour, faint enough to sit behind the main run.
struct ChaosTwinGhostView: View {
    let viewModel: SimulationViewModel

    private static let trailOpacity = 0.35
    private static let bodyOpacity = 0.6
    private static let bodyRadius: CGFloat = 5

    var body: some View {
        Canvas { context, _ in
            for (index, trail) in viewModel.ghostTrails.enumerated() where trail.count > 1 {
                var path = Path()
                path.addLines(trail)
                context.stroke(path, with: .color(color(at: index).opacity(Self.trailOpacity)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            for (index, position) in viewModel.ghostPositions.enumerated() {
                let radius = Self.bodyRadius
                let rect = CGRect(x: position.x - radius, y: position.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color(at: index).opacity(Self.bodyOpacity)),
                               lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(at index: Int) -> Color {
        let ids = viewModel.ghostIDs
        return BodyView.paletteColor(for: ids.indices.contains(index) ? ids[index] : index)
    }
}

/// Top-right badge: "Twin Δ = 3.2×10⁻⁵ L", plus "Diverged at t = 412" once
/// the runs are more than `ChaosTwin.divergenceThreshold` length units apart.
struct ChaosTwinBadge: View {
    let viewModel: SimulationViewModel

    var body: some View {
        if let divergence = viewModel.twinDivergence {
            VStack {
                HStack {
                    Spacer()
                    badge(divergence: divergence)
                }
                Spacer()
            }
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    private func badge(divergence: Double) -> some View {
        let divergedTime = viewModel.twinDivergenceTime
        return VStack(alignment: .trailing, spacing: 2) {
            Text("Twin \u{0394} = \(Self.scientific(divergence)) L")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(divergedTime == nil ? .white : .orange)
            if let divergedTime {
                Text(String(format: "Diverged at t = %.0f", divergedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// "3.2×10⁻⁵" for small values, plain decimals from 0.01 up.
    static func scientific(_ value: Double) -> String {
        guard value > 0, value.isFinite else { return "0" }
        if value >= 0.01 { return String(format: "%.2f", value) }
        let exponent = Int(floor(log10(value)))
        let mantissa = value / pow(10, Double(exponent))
        return String(format: "%.1f", mantissa) + "×10" + exponent.superscript
    }
}

extension Int {
    /// The number in Unicode superscript digits, e.g. -5 → "⁻⁵" (for "10⁻⁵").
    var superscript: String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"
        ]
        return String(String(self).compactMap { digits[$0] })
    }
}
