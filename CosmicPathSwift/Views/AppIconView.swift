//
//  AppIconView.swift
//  CosmicPathSwift
//
//  SwiftUI-rendered app icon design for export.
//  Renders an orange star, cyan planet with orbital trail,
//  and warped spacetime grid on a dark background.
//

import SwiftUI

/// Self-contained SwiftUI Canvas that renders the app icon artwork.
///
/// The icon depicts the simulation's key visual elements: a radial-gradient star,
/// a cyan planet with a fading orbital trail, and a background warped spacetime grid.
/// All dimensions are proportional to `size`, so the icon scales cleanly from
/// small thumbnails to large previews.
///
/// This view is used only for icon design/export and is not part of the runtime UI.
struct AppIconView: View {
    /// The width and height of the square icon canvas.
    let size: CGFloat

    /// Star position, offset slightly left and up from center for visual balance.
    private var center: CGPoint {
        CGPoint(x: size * 0.42, y: size * 0.48)
    }

    private var starRadius: CGFloat { size * 0.12 }
    private var planetRadius: CGFloat { size * 0.035 }
    private var orbitRadius: CGFloat { size * 0.30 }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width

            // Background gradient
            let bgRect = CGRect(origin: .zero, size: canvasSize)
            let bgGradient = Gradient(colors: [
                Color(red: 0.02, green: 0.02, blue: 0.08),
                Color(red: 0.0, green: 0.0, blue: 0.03),
                Color(red: 0.02, green: 0.01, blue: 0.06)
            ])
            context.fill(
                Path(roundedRect: bgRect, cornerRadius: s * 0.22),
                with: .linearGradient(bgGradient, startPoint: .zero, endPoint: CGPoint(x: s, y: s))
            )

            // Warped spacetime grid
            drawSpacetimeGrid(context: context, size: s)

            // Orbital trail (elliptical arc)
            drawOrbitalTrail(context: context, size: s)

            // Star glow
            let glowCenter = center
            let glowRadius = starRadius * 4
            let glowGradient = Gradient(colors: [
                .orange.opacity(0.3),
                .orange.opacity(0.1),
                .orange.opacity(0.02),
                .clear
            ])
            let glowRect = CGRect(
                x: glowCenter.x - glowRadius,
                y: glowCenter.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(glowGradient, center: glowCenter, startRadius: 0, endRadius: glowRadius)
            )

            // Star body
            let starGradient = Gradient(colors: [.white, .yellow, .orange, Color(red: 0.9, green: 0.3, blue: 0.1)])
            let starRect = CGRect(
                x: center.x - starRadius,
                y: center.y - starRadius,
                width: starRadius * 2,
                height: starRadius * 2
            )
            context.fill(
                Path(ellipseIn: starRect),
                with: .radialGradient(starGradient, center: center, startRadius: 0, endRadius: starRadius)
            )

            // Planet position (upper right of orbit)
            let planetAngle: Double = -0.6
            let planetCenter = CGPoint(
                x: center.x + orbitRadius * cos(planetAngle),
                y: center.y + orbitRadius * sin(planetAngle) * 0.85
            )

            // Planet glow
            let pGlowRadius = planetRadius * 3.5
            let pGlowGradient = Gradient(colors: [
                .cyan.opacity(0.4),
                .cyan.opacity(0.1),
                .clear
            ])
            let pGlowRect = CGRect(
                x: planetCenter.x - pGlowRadius,
                y: planetCenter.y - pGlowRadius,
                width: pGlowRadius * 2,
                height: pGlowRadius * 2
            )
            context.fill(
                Path(ellipseIn: pGlowRect),
                with: .radialGradient(pGlowGradient, center: planetCenter, startRadius: 0, endRadius: pGlowRadius)
            )

            // Planet body
            let planetGradient = Gradient(colors: [.white, .cyan, Color(red: 0.0, green: 0.6, blue: 0.8)])
            let planetRect = CGRect(
                x: planetCenter.x - planetRadius,
                y: planetCenter.y - planetRadius,
                width: planetRadius * 2,
                height: planetRadius * 2
            )
            context.fill(
                Path(ellipseIn: planetRect),
                with: .radialGradient(planetGradient, center: planetCenter, startRadius: 0, endRadius: planetRadius)
            )
        }
        .frame(width: size, height: size)
    }

    // MARK: - Spacetime Grid

    /// Draws the background spacetime grid with gravitational warping toward the star.
    /// Uses the same warp-toward-center technique as `SimulationCanvasView`.
    private func drawSpacetimeGrid(context: GraphicsContext, size: CGFloat) {
        let gridSpacing = size / 10
        let warpStrength: CGFloat = size * 0.08
        let gridColor = Color.white.opacity(0.06)

        // Vertical lines
        var x: CGFloat = gridSpacing
        while x < size {
            var path = Path()
            var first = true
            var y: CGFloat = 0
            while y <= size {
                let warped = warpGridPoint(CGPoint(x: x, y: y), strength: warpStrength)
                if first {
                    path.move(to: warped)
                    first = false
                } else {
                    path.addLine(to: warped)
                }
                y += size / 40
            }
            context.stroke(path, with: .color(gridColor), lineWidth: 0.8)
            x += gridSpacing
        }

        // Horizontal lines
        var yPos: CGFloat = gridSpacing
        while yPos < size {
            var path = Path()
            var first = true
            var xPos: CGFloat = 0
            while xPos <= size {
                let warped = warpGridPoint(CGPoint(x: xPos, y: yPos), strength: warpStrength)
                if first {
                    path.move(to: warped)
                    first = false
                } else {
                    path.addLine(to: warped)
                }
                xPos += size / 40
            }
            context.stroke(path, with: .color(gridColor), lineWidth: 0.8)
            yPos += gridSpacing
        }
    }

    /// Displaces a point toward the star center with inverse-distance falloff.
    private func warpGridPoint(_ point: CGPoint, strength: CGFloat) -> CGPoint {
        let dx = center.x - point.x
        let dy = center.y - point.y
        let dist = max(sqrt(dx * dx + dy * dy), 1)
        let warp = strength / dist
        return CGPoint(
            x: point.x + dx * warp,
            y: point.y + dy * warp
        )
    }

    // MARK: - Orbital Trail

    /// Draws a fading elliptical arc representing the planet's orbital trail.
    /// The trail starts bright near the planet and fades to transparent at the tail,
    /// spanning ~300° of the ellipse. The 0.85 vertical multiplier on the y-coordinate
    /// gives the orbit a slight tilt for a 3D perspective effect.
    private func drawOrbitalTrail(context: GraphicsContext, size: CGFloat) {
        let segments = 80
        let startAngle: Double = -0.6
        let arcLength: Double = 5.2

        for i in 1..<segments {
            let t0 = Double(i - 1) / Double(segments)
            let t1 = Double(i) / Double(segments)
            let angle0 = startAngle - arcLength * t0
            let angle1 = startAngle - arcLength * t1

            let p0 = CGPoint(
                x: center.x + orbitRadius * cos(angle0),
                y: center.y + orbitRadius * sin(angle0) * 0.85
            )
            let p1 = CGPoint(
                x: center.x + orbitRadius * cos(angle1),
                y: center.y + orbitRadius * sin(angle1) * 0.85
            )

            // Fade trail from bright (near planet) to transparent
            let opacity = (1.0 - t1) * 0.7
            var segment = Path()
            segment.move(to: p0)
            segment.addLine(to: p1)
            context.stroke(
                segment,
                with: .color(.cyan.opacity(opacity)),
                lineWidth: size * 0.004
            )
        }
    }
}

#Preview {
    AppIconView(size: 300)
        .background(Color.black)
}
