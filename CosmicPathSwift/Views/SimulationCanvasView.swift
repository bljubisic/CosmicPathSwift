//
//  SimulationCanvasView.swift
//  CosmicPathSwift
//
//  Canvas rendering: warped spacetime grid, orbital trails, celestial bodies
//  (stars, planets, moons, or a black hole), Schwarzschild rings, formula
//  overlay, and absorption / merge / ejection overlays.
//
//  ## Camera Control (3D)
//
//  The view captures drag gestures to rotate the orthographic 3D camera:
//    • Horizontal drag → azimuth  (scene rotates left / right)
//    • Vertical drag   → elevation (scene tilts up / down, clamped ±90°)
//
//  On each drag change the view computes the translation delta relative to
//  the previous event and forwards it to `viewModel.rotateCamera(_:_:)`,
//  which rebuilds the `CoordinateTransformer` and re-projects all positions.
//  `previousDragTranslation` (@State) stores the last event's translation so
//  each `.onChanged` can compute a delta; it is reset to `.zero` in `.onEnded`.
//

import SwiftUI

/// Main rendering surface for the gravitational simulation.
///
/// Composes multiple visual layers in a ZStack (back to front):
/// 1. Dark background
/// 2. Warped spacetime grid (purely visual — does not affect physics)
/// 3. Black hole effects (2-body only: lensing glow, accretion disk, ISCO/photon rings)
/// 4. Schwarzschild radius ring(s)
/// 5. Orbital trails (fade-in from old to new positions)
/// 6. Gravitational force lines connecting every pair of bodies
/// 7. Bleed particles (2-body tidal stripping)
/// 8. Bodies, drawn far-to-near (`renderOrder`) for correct occlusion
/// 9. Formula overlay (field equation / acceleration formula)
/// 10. Event overlay (absorption, merge, or ejection)
///
/// ## Canvas Sizing
///
/// Uses `GeometryReader` to report its size to the parent via `canvasSize` binding.
/// On appear, calls `viewModel.setup(canvasSize:)` to initialize the simulation.
/// On resize, calls `viewModel.resizeCanvas(_:)` to update the coordinate transformer.
struct SimulationCanvasView: View {
    let viewModel: SimulationViewModel
    @Binding var canvasSize: CGSize

    /// Tracks the cumulative drag translation from the previous gesture event so
    /// we can compute per-event deltas. Reset to `.zero` in `.onEnded` so each
    /// new drag starts from a clean baseline.
    ///
    /// Note: `@GestureState` + `.updating` cannot be used here because both
    /// callbacks fire in the same event cycle — `.updating` writes the current
    /// translation to backing store before `.onChanged` reads it, making the
    /// computed delta always zero and producing no camera movement.
    @State private var previousDragTranslation: CGSize = .zero

    /// Radians of camera rotation per screen point of drag distance.
    /// 0.005 gives one full 360° turn in ~1257 points of horizontal drag.
    private let cameraDragSensitivity: Double = 0.005

    /// Grid pull (points) toward the heaviest body in 3-body mode; lighter bodies
    /// pull proportionally less. 3-body masses are too small for the 2-body
    /// formula (mass × scale × 0.04) to produce a visible warp.
    private let threeBodyWarpStrength: CGFloat = 8

    private var isThreeBody: Bool { viewModel.isThreeBodyMode }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.95)

                spacetimeGrid(size: geometry.size)

                if !isThreeBody && viewModel.metrics.isBlackHole {
                    BlackHoleEffectsView(viewModel: viewModel)
                }

                if isThreeBody {
                    threeBodySchwarzschildRings
                } else {
                    schwarzschildRing
                }

                ForEach(viewModel.bodyTrails.indices, id: \.self) { index in
                    trailPath(points: viewModel.bodyTrails[index], color: trailColor(for: index))
                }

                forceLines

                bleedParticles

                ForEach(viewModel.renderOrder, id: \.self) { index in
                    if isVisible(index) {
                        bodyView(for: index)
                            .position(viewModel.bodyPositions[index])
                    }
                }

                formulaOverlay

                eventOverlay
            }
            .onAppear {
                canvasSize = geometry.size
                // Only create a new engine on the very first appearance.
                // In portrait mode, SwiftUI creates separate SimulationCanvasView
                // instances for the running and paused branches, so .onAppear fires
                // again when the user pauses. Calling setup() there would reset the
                // simulation unexpectedly — resizeCanvas() is sufficient to adapt
                // the existing engine to the new canvas dimensions.
                if viewModel.isSetup {
                    viewModel.resizeCanvas(geometry.size)
                } else {
                    viewModel.setup(canvasSize: geometry.size)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
                viewModel.resizeCanvas(newSize)
            }
            // Camera rotation gesture: drag horizontally to change azimuth,
            // vertically to change elevation. Elevation is clamped in rotateCamera().
            //
            // The delta is computed relative to the previous event's translation
            // so small incremental drags produce smooth, proportional rotation.
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let deltaX = Double(value.translation.width  - previousDragTranslation.width)
                        let deltaY = Double(value.translation.height - previousDragTranslation.height)
                        previousDragTranslation = value.translation
                        viewModel.rotateCamera(
                            deltaAzimuth:   deltaX * cameraDragSensitivity,
                            deltaElevation: deltaY * cameraDragSensitivity
                        )
                    }
                    .onEnded { _ in
                        previousDragTranslation = .zero
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Visibility & Colours

    /// False for indices out of range and for the absorbed planet in 2-body mode.
    private func isVisible(_ index: Int) -> Bool {
        guard viewModel.bodyPositions.indices.contains(index) else { return false }
        return isThreeBody || index == 0 || !viewModel.metrics.isAbsorbed
    }

    private func trailColor(for index: Int) -> Color {
        if isThreeBody, viewModel.bodyIDs.indices.contains(index) {
            return BodyView.paletteColor(for: viewModel.bodyIDs[index]).opacity(0.5)
        }
        if index == 0 { return .orange.opacity(0.4) }
        return viewModel.metrics.isAbsorbed ? .red.opacity(0.3) : .cyan.opacity(0.5)
    }

    // MARK: - Bodies

    /// Builds the view for one body.
    ///
    /// 2-body: body1 is the classic star (or black hole) and body2 the planet tinted
    /// by time dilation. 3-body: every body uses its ID's palette colour; size
    /// follows its kind and mass relative to the preset's mass unit.
    private func bodyView(for index: Int) -> BodyView {
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
            let rs = CGFloat(viewModel.metrics.schwarzschildRadius) * CGFloat(viewModel.coordinateScale)
            return BodyView(kind: kind, radius: radius, tint: nil,
                            blackHoleRadius: viewModel.metrics.isBlackHole ? rs : nil)
        }
        return BodyView(kind: kind, radius: radius, tint: viewModel.metrics.timeDilationColor)
    }

    // MARK: - Force Lines

    /// Faint line between every pair of visible bodies.
    private var forceLines: some View {
        let visible = viewModel.bodyPositions.indices.filter(isVisible)
        let positions = viewModel.bodyPositions
        return Path { path in
            for i in visible {
                for j in visible where j > i {
                    path.move(to: positions[i])
                    path.addLine(to: positions[j])
                }
            }
        }
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    }

    // MARK: - Bleed Particles

    /// Tidal-stripped material spiraling toward the central body (2-body only).
    /// Rendered with a Canvas for performance (up to 300 small dots per frame).
    /// Color transitions from cyan (freshly emitted) to orange (older, heated).
    private var bleedParticles: some View {
        Canvas { context, _ in
            for particle in viewModel.bleedParticleData {
                let t = 1.0 - particle.opacity  // 0 = fresh, 1 = old
                let color = Color(
                    red:   min(1.0, t * 2.0),
                    green: max(0.0, 1.0 - t),
                    blue:  max(0.0, 1.0 - t * 2.0)
                ).opacity(particle.opacity * 0.85)
                let size: CGFloat = 3
                let rect = CGRect(
                    x: particle.position.x - size / 2,
                    y: particle.position.y - size / 2,
                    width: size, height: size
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }

    // MARK: - Schwarzschild Rings

    /// Draws the event horizon boundary circle around body1 (2-body mode).
    /// In normal mode: dashed, semi-transparent red ring (rₛ is small, decorative).
    /// In black hole mode: solid red ring matching the visible black disc edge.
    private var schwarzschildRing: some View {
        let isBlackHole = viewModel.metrics.isBlackHole
        let rs = CGFloat(viewModel.metrics.schwarzschildRadius) * CGFloat(viewModel.coordinateScale)
        return Circle()
            .stroke(
                isBlackHole ? Color.red.opacity(0.6) : Color.red.opacity(0.3),
                style: StrokeStyle(
                    lineWidth: isBlackHole ? 1.5 : 1,
                    dash: isBlackHole ? [] : [4, 4]
                )
            )
            .frame(width: rs * 2, height: rs * 2)
            .position(viewModel.body1Position)
    }

    /// Small dashed rₛ = 2Gm/c² ring around every body (3-body mode).
    /// Rings below half a point are skipped since they would not be visible.
    private var threeBodySchwarzschildRings: some View {
        let positions = viewModel.bodyPositions
        let masses = viewModel.bodyMasses
        let scale = CGFloat(viewModel.coordinateScale)
        return Canvas { context, _ in
            for index in positions.indices where masses.indices.contains(index) {
                let rs = CGFloat(2 * GravitySimulationEngine.G * masses[index] / GravitySimulationEngine.cSquared) * scale
                guard rs >= 0.5 else { continue }
                let rect = CGRect(x: positions[index].x - rs, y: positions[index].y - rs, width: rs * 2, height: rs * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.red.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    // MARK: - Event Overlay

    /// Absorption (2-body) or merge / ejection (3-body) banner, if anything happened.
    @ViewBuilder
    private var eventOverlay: some View {
        if isThreeBody {
            let metrics = viewModel.systemMetrics
            if let collision = metrics.collision {
                eventBanner(
                    title: "Collision",
                    details: ["\(letter(collision.0)) + \(letter(collision.1)) merged"]
                        + (metrics.ejectedBodyID.map { ["Body \(letter($0)) ejected"] } ?? []),
                    color: .red
                )
            } else if let ejected = metrics.ejectedBodyID {
                eventBanner(title: "Ejection", details: ["Body \(letter(ejected)) ejected"], color: .orange)
            }
        } else if viewModel.metrics.isAbsorbed {
            let isBlackHole = viewModel.metrics.isBlackHole
            eventBanner(
                title: isBlackHole ? "Event Horizon Crossed" : "Collision",
                details: [isBlackHole ? "Object absorbed by black hole" : "Planet collided with the star"],
                color: .red
            )
        }
    }

    private func letter(_ id: Int) -> String {
        SystemMetrics.letter(for: id)
    }

    private func eventBanner(title: String, details: [String], color: Color) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(color)
                    ForEach(details, id: \.self) { detail in
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Spacetime Grid

    /// Draws a grid of vertical and horizontal lines warped toward the bodies to
    /// visualize spacetime curvature. This is a purely cosmetic effect — the actual
    /// physics uses the Schwarzschild-corrected force law, not grid deformation.
    ///
    /// Lines are drawn at 50pt intervals and subdivided into 5pt segments. Each segment
    /// vertex is displaced toward every source returned by `warpSources`.
    private func spacetimeGrid(size: CGSize) -> some View {
        let sources = warpSources
        return Canvas { context, canvasSize in
            let step: CGFloat = 50
            let color = Color.white.opacity(0.06)

            var xPos: CGFloat = 0
            while xPos <= canvasSize.width {
                var path = Path()
                var y: CGFloat = 0
                var first = true
                while y <= canvasSize.height {
                    let warped = warpPoint(CGPoint(x: xPos, y: y), sources: sources)
                    if first {
                        path.move(to: warped)
                        first = false
                    } else {
                        path.addLine(to: warped)
                    }
                    y += 5
                }
                context.stroke(path, with: .color(color), lineWidth: 0.5)
                xPos += step
            }

            var yPos: CGFloat = 0
            while yPos <= canvasSize.height {
                var path = Path()
                var x: CGFloat = 0
                var first = true
                while x <= canvasSize.width {
                    let warped = warpPoint(CGPoint(x: x, y: yPos), sources: sources)
                    if first {
                        path.move(to: warped)
                        first = false
                    } else {
                        path.addLine(to: warped)
                    }
                    x += 5
                }
                context.stroke(path, with: .color(color), lineWidth: 0.5)
                yPos += step
            }
        }
    }

    /// Points the grid is pulled toward, with their pull strength in points.
    ///
    /// 2-body: a single source at body1 with strength mass × zoom × 0.04 (the
    /// planet's pull is negligible). 3-body: one source per body, mass-weighted
    /// relative to the heaviest body.
    private var warpSources: [(center: CGPoint, strength: CGFloat)] {
        guard isThreeBody else {
            let strength = CGFloat(viewModel.config.simulationMass1) * CGFloat(viewModel.coordinateScale) * 0.04
            return [(viewModel.body1Position, strength)]
        }
        let masses = viewModel.bodyMasses
        let heaviest = max(masses.max() ?? 1, .leastNonzeroMagnitude)
        return zip(viewModel.bodyPositions, masses).map { position, mass in
            (position, threeBodyWarpStrength * zoomSizeScale * CGFloat(mass / heaviest))
        }
    }

    // MARK: - Trail Path

    /// Renders an orbital trail as a series of line segments with progressive opacity.
    /// Older trail points are more transparent, newer points are more opaque, creating
    /// a fade-in effect that shows the direction of motion.
    private func trailPath(points: [CGPoint], color: Color) -> some View {
        Canvas { context, _ in
            guard points.count > 1 else { return }
            let totalPoints = points.count
            for i in 1..<totalPoints {
                let opacity = Double(i) / Double(totalPoints)
                var segment = Path()
                segment.move(to: points[i - 1])
                segment.addLine(to: points[i])
                context.stroke(
                    segment,
                    with: .color(color.opacity(opacity)),
                    lineWidth: 1.5
                )
            }
        }
    }


    // MARK: - Formula Overlay

    /// Displays the governing equations in the top-left corner as a subtle watermark.
    /// Shows the Einstein field equation (Gμν + Λgμν = 8πG/c⁴ Tμν) and either:
    /// - 3-body mode: the pairwise-summed GR-corrected acceleration
    /// - 2-body black hole mode: the Schwarzschild radius and photon sphere formulas
    /// - 2-body normal mode: the Schwarzschild geodesic acceleration formula
    private var formulaOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("G\u{03BC}\u{03BD} + \u{039B}g\u{03BC}\u{03BD} = (8\u{03C0}G/c\u{2074})T\u{03BC}\u{03BD}")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    if isThreeBody {
                        Text("aᵢ = Σⱼ (−Gmⱼ/rᵢⱼ² − 3GmⱼLᵢⱼ²/c²rᵢⱼ⁴) r̂ᵢⱼ")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.18))
                    } else if viewModel.metrics.isBlackHole {
                        Text("r\u{209B} = 2GM/c\u{00B2}  r\u{209A}\u{2095} = 1.5r\u{209B}")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.3))
                    } else {
                        Text("a = -GM/r\u{00B2} - 3GML\u{00B2}/c\u{00B2}r\u{2074}")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.18))
                    }
                }
                .padding(8)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    /// Zoom-based size multiplier for celestial bodies.
    /// At the default separation (1 AU), this is 1.0. As the distance increases
    /// and the view zooms out, bodies shrink proportionally (clamped to 40%-100%)
    /// so they don't dominate the canvas at high zoom-out levels.
    private var zoomSizeScale: CGFloat {
        // coordinateScale is inversely proportional to the viewed extent.
        // Compute the reference scale at default 1 AU separation.
        let referenceExtent = CelestialConstants.baseAU * CelestialConstants.orbitMarginFactor
        let minDim = max(min(canvasSize.width, canvasSize.height), 1) // guard against zero
        let halfCanvas = minDim * 0.40
        let referenceScale = halfCanvas / referenceExtent
        let ratio = CGFloat(viewModel.coordinateScale) / referenceScale
        return max(0.4, min(1.0, ratio))
    }


    /// Displaces a grid point toward every warp source to simulate gravitational
    /// curvature. Each source pulls by `strength` points along the line to it
    /// (less within 1 pt), creating a funnel-like distortion around each body.
    private func warpPoint(_ point: CGPoint, sources: [(center: CGPoint, strength: CGFloat)]) -> CGPoint {
        var displaced = point
        for source in sources {
            let dx = source.center.x - point.x
            let dy = source.center.y - point.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let warp = source.strength / dist
            displaced.x += dx * warp
            displaced.y += dy * warp
        }
        return displaced
    }
}
