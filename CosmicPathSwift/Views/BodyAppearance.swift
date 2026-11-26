//
//  BodyAppearance.swift
//  CosmicPathSwift
//
//  How bodies and their trails look, shared by the orbit canvas and the
//  gravity-well sheet (issue #38) so both draw the same star, planet or hole.
//

import SwiftUI

@MainActor
enum BodyAppearance {

    /// A body's own colour: its palette colour in 3-body mode; the star orange
    /// and the planet cyan in 2-body mode. Used for its well's contours.
    static func color(for index: Int, viewModel: SimulationViewModel) -> Color {
        if viewModel.isThreeBodyMode, viewModel.bodyIDs.indices.contains(index) {
            return BodyView.paletteColor(for: viewModel.bodyIDs[index])
        }
        return index == 0 ? .orange : .cyan
    }

    /// Colour of a body's orbit trail.
    static func trailColor(for index: Int, viewModel: SimulationViewModel) -> Color {
        if viewModel.isThreeBodyMode, viewModel.bodyIDs.indices.contains(index) {
            return BodyView.paletteColor(for: viewModel.bodyIDs[index]).opacity(0.5)
        }
        if index == 0 { return .orange.opacity(0.4) }
        return viewModel.metrics.isAbsorbed ? .red.opacity(0.3) : .cyan.opacity(0.5)
    }

    /// Builds the view for one body.
    ///
    /// 2-body: body1 is the classic star (or black hole) and body2 the planet tinted
    /// by time dilation. 3-body: every body uses its ID's palette colour; size
    /// follows its kind and mass relative to the preset's mass unit.
    ///
    /// - Parameter coordinateScale: Points per length unit of the view the body is
    ///   drawn in (sets the black hole's disc).
    static func bodyView(
        for index: Int, viewModel: SimulationViewModel, zoomSizeScale: CGFloat, coordinateScale: Double
    ) -> BodyView {
        let isThreeBody = viewModel.isThreeBodyMode
        let kind = viewModel.bodyKinds.indices.contains(index) ? viewModel.bodyKinds[index] : .star
        let multipliers = viewModel.bodyMassMultipliers
        let multiplier = multipliers.indices.contains(index) ? multipliers[index] : 1
        let referenceStarMultiplier = isThreeBody ? 1 : (multipliers.first ?? 1)
        let referenceStar = BodyView.starRadius(massMultiplier: referenceStarMultiplier, zoomSizeScale: zoomSizeScale)

        let radius: CGFloat
        switch kind {
        case .star:
            radius = BodyView.starRadius(massMultiplier: multiplier, zoomSizeScale: zoomSizeScale)
        case .planet:
            radius = BodyView.planetRadius(starRadius: referenceStar, massMultiplier: multiplier)
        case .moon:
            radius = BodyView.moonRadius(starRadius: referenceStar, massMultiplier: multiplier)
        }

        if isThreeBody {
            let id = viewModel.bodyIDs.indices.contains(index) ? viewModel.bodyIDs[index] : index
            return BodyView(kind: kind, radius: radius, tint: BodyView.paletteColor(for: id))
        }
        if index == 0 {
            let rs = CGFloat(viewModel.metrics.schwarzschildRadius) * CGFloat(coordinateScale)
            return BodyView(kind: kind, radius: radius, tint: nil,
                            blackHoleRadius: viewModel.metrics.isBlackHole ? rs : nil)
        }
        return BodyView(kind: kind, radius: radius, tint: viewModel.metrics.timeDilationColor,
                        isHabitable: viewModel.habitableStatus == .habitable)
    }

    /// Zoom-based size multiplier for celestial bodies.
    /// At the default separation (1 AU), this is 1.0. As the distance increases
    /// and the view zooms out, bodies shrink proportionally (clamped to 40%-100%)
    /// so they don't dominate the canvas at high zoom-out levels. In strong field
    /// the reference is the orbit itself, since 1 AU there is 10⁸ length units.
    static func zoomSizeScale(viewModel: SimulationViewModel, canvasSize: CGSize, coordinateScale: Double) -> CGFloat {
        // coordinateScale is inversely proportional to the viewed extent.
        // Compute the reference scale at the reference separation.
        let referenceExtent = viewModel.config.bodySizeReferenceLength * CelestialConstants.orbitMarginFactor
        let minDim = max(min(canvasSize.width, canvasSize.height), 1) // guard against zero
        let halfCanvas = minDim * 0.40
        let referenceScale = halfCanvas / referenceExtent
        let ratio = CGFloat(coordinateScale) / referenceScale
        return max(0.4, min(1.0, ratio))
    }
}

// MARK: - TrailRenderer

enum TrailRenderer {
    /// Number of opacity steps a trail's fade is drawn in.
    static let fadeBands = 64

    /// Strokes an orbital trail with progressive opacity: older points are more
    /// transparent, newer ones more opaque, showing the direction of motion.
    ///
    /// The fade is drawn in up to `fadeBands` polylines rather than one stroke
    /// per segment, so long trails (up to 3200 points) stay cheap to render.
    static func stroke(_ points: [CGPoint], color: Color, in context: GraphicsContext) {
        let segments = points.count - 1
        guard segments > 0 else { return }
        let bands = min(fadeBands, segments)
        for band in 0..<bands {
            let start = band * segments / bands
            let end = (band + 1) * segments / bands
            var path = Path()
            path.move(to: points[start])
            for i in (start + 1)...end {
                path.addLine(to: points[i])
            }
            let opacity = Double(end) / Double(segments + 1)
            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1.5)
        }
    }
}
