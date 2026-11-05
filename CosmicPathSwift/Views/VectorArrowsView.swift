//
//  VectorArrowsView.swift
//  CosmicPathSwift
//
//  Draws the velocity / acceleration arrows projected by the ViewModel
//  (see `VectorOverlay` for how they are scaled).
//

import SwiftUI

/// A set of arrows in one colour, each a shaft plus a two-line head.
struct VectorArrowsView: View {
    let arrows: [CanvasArrow]
    let color: Color

    /// Arrows shorter than this (points) are skipped: they'd be hidden by the body.
    private static let minimumLength: CGFloat = 2
    private static let headLength: CGFloat = 7
    /// Half-angle between the shaft and each side of the arrowhead.
    private static let headHalfAngle: CGFloat = .pi / 7
    private static let lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for arrow in arrows {
                Self.addArrow(arrow, to: &path)
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    private static func addArrow(_ arrow: CanvasArrow, to path: inout Path) {
        let dx = arrow.head.x - arrow.tail.x
        let dy = arrow.head.y - arrow.tail.y
        let length = hypot(dx, dy)
        guard length >= minimumLength else { return }

        path.move(to: arrow.tail)
        path.addLine(to: arrow.head)

        // The head shrinks on short arrows so it never overshoots the tail.
        let head = min(headLength, length * 0.5)
        let angle = atan2(dy, dx)
        for side in [-1.0, 1.0] {
            let wingAngle = angle + .pi + side * headHalfAngle
            path.move(to: arrow.head)
            path.addLine(to: CGPoint(
                x: arrow.head.x + head * cos(wingAngle),
                y: arrow.head.y + head * sin(wingAngle)
            ))
        }
    }
}
