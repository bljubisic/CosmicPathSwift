//
//  BodyView.swift
//  CosmicPathSwift
//
//  Renders a single celestial body (star, planet, moon, or black hole) and
//  owns the size and colour rules shared by the canvas and the legend.
//

import SwiftUI

/// A single rendered body. The caller positions it with `.position(_:)`.
///
/// - Black hole: solid black disc of radius rₛ with a hot gradient rim.
/// - `tint == nil`: the classic yellow → orange → red star gradient (2-body star).
/// - Otherwise: a white-cored gradient in the tint colour (planets, 3-body bodies).
struct BodyView: View {
    let kind: BodyKind
    /// Rendered radius in canvas points (see `starRadius` / `planetRadius` / `moonRadius`).
    let radius: CGFloat
    /// Gradient colour; nil selects the classic star gradient.
    let tint: Color?
    /// Event-horizon radius in canvas points when this body is a black hole.
    var blackHoleRadius: CGFloat?

    var body: some View {
        if let rs = blackHoleRadius {
            blackHole(radius: rs)
        } else {
            gradientBody
        }
    }

    // MARK: - Black Hole

    private func blackHole(radius rs: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: rs * 2, height: rs * 2)

            Circle()
                .stroke(
                    RadialGradient(
                        colors: [.clear, .orange.opacity(0.8), .yellow, .white],
                        center: .center,
                        startRadius: rs * 0.8,
                        endRadius: rs
                    ),
                    lineWidth: 2
                )
                .frame(width: rs * 2, height: rs * 2)
                .shadow(color: .orange.opacity(0.4), radius: 4)
        }
    }

    // MARK: - Gradient Body

    private var gradientBody: some View {
        let colors = tint.map { [.white, $0, $0.opacity(0.8)] } ?? [.yellow, .orange, .red.opacity(0.8)]
        let glow = tint ?? .orange
        return Circle()
            .fill(RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: glow.opacity(0.6), radius: kind == .star ? 8 : 6)
    }

    // MARK: - Palette

    /// 3-body colours indexed by body ID, so three equal stars stay distinguishable.
    static let palette: [Color] = [.orange, .cyan, Color(red: 1.0, green: 0.3, blue: 0.9)]

    static func paletteColor(for id: Int) -> Color {
        palette[((id % palette.count) + palette.count) % palette.count]
    }

    // MARK: - Sizing

    /// Star radius: grows slightly with mass multiplier and shrinks with zoom.
    /// Minimum 6pt so it's always clearly visible.
    static func starRadius(massMultiplier: Double, zoomSizeScale: CGFloat) -> CGFloat {
        let baseRadius: CGFloat = 14
        let massScale = CGFloat(log(massMultiplier + 1)) * 0.5 + 1
        return max(6, baseRadius * massScale * zoomSizeScale)
    }

    /// Planet radius: proportionally smaller than its reference star.
    /// Real ratio is 109:1 but compressed to ~5:1 for visibility.
    /// Heavier planet → denser → slightly smaller. Minimum 3pt.
    static func planetRadius(starRadius: CGFloat, massMultiplier: Double) -> CGFloat {
        let baseRatio: CGFloat = 5.0
        let massScale = 1.0 / (CGFloat(log(massMultiplier + 1)) * 0.3 + 1)
        return max(3, starRadius / baseRatio * massScale)
    }

    /// Moon radius: half a planet's, minimum 2pt.
    static func moonRadius(starRadius: CGFloat, massMultiplier: Double) -> CGFloat {
        max(2, planetRadius(starRadius: starRadius, massMultiplier: massMultiplier) * 0.5)
    }
}
