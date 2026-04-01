//
//  SimulationCanvasView.swift
//  CosmicPathSwift
//
//  Canvas rendering: warped spacetime grid, orbital trails, celestial bodies
//  (star or black hole), Schwarzschild ring, formula overlay, and absorption state.
//

import SwiftUI

struct SimulationCanvasView: View {
    let viewModel: SimulationViewModel
    @Binding var canvasSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.95)

                spacetimeGrid(size: geometry.size)

                if viewModel.metrics.isBlackHole {
                    BlackHoleEffectsView(viewModel: viewModel)
                }

                schwarzschildRing

                // Orbital trails
                trailPath(points: viewModel.body1Trail, color: .orange.opacity(0.4))
                if !viewModel.metrics.isAbsorbed {
                    trailPath(points: viewModel.body2Trail, color: .cyan.opacity(0.5))
                } else {
                    trailPath(points: viewModel.body2Trail, color: .red.opacity(0.3))
                }

                // Gravitational force line
                if !viewModel.metrics.isAbsorbed {
                    Path { path in
                        path.move(to: viewModel.body1Position)
                        path.addLine(to: viewModel.body2Position)
                    }
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }

                body1View
                if !viewModel.metrics.isAbsorbed {
                    body2View
                }

                formulaOverlay

                if viewModel.metrics.isAbsorbed {
                    absorptionOverlay
                }
            }
            .onAppear {
                canvasSize = geometry.size
                viewModel.setup(canvasSize: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
                viewModel.resizeCanvas(newSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Body 1 (Star or Black Hole)

    @ViewBuilder
    private var body1View: some View {
        if viewModel.metrics.isBlackHole {
            let rs = CGFloat(viewModel.metrics.schwarzschildRadius) * CGFloat(viewModel.coordinateScale)
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
            .position(viewModel.body1Position)
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow, .orange, .red.opacity(0.8)],
                        center: .center,
                        startRadius: 0,
                        endRadius: starRadius
                    )
                )
                .frame(
                    width: starRadius * 2,
                    height: starRadius * 2
                )
                .shadow(color: .orange.opacity(0.6), radius: 8)
                .position(viewModel.body1Position)
        }
    }

    // MARK: - Body 2

    private var body2View: some View {
        let color = viewModel.metrics.timeDilationColor
        return Circle()
            .fill(
                RadialGradient(
                    colors: [.white, color, color.opacity(0.8)],
                    center: .center,
                    startRadius: 0,
                    endRadius: planetRadius
                )
            )
            .frame(
                width: planetRadius * 2,
                height: planetRadius * 2
            )
            .shadow(color: color.opacity(0.6), radius: 6)
            .position(viewModel.body2Position)
    }

    // MARK: - Schwarzschild Ring

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

    // MARK: - Absorption Overlay

    private var absorptionOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("Event Horizon Crossed")
                        .font(.headline.bold())
                        .foregroundStyle(.red)
                    Text("Object absorbed by black hole")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
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

    private func spacetimeGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let step: CGFloat = 50
            let body1Center = viewModel.body1Position
            let warpStrength = CGFloat(viewModel.config.simulationMass1) * CGFloat(viewModel.coordinateScale) * 0.04
            let color = Color.white.opacity(0.06)

            var xPos: CGFloat = 0
            while xPos <= canvasSize.width {
                var path = Path()
                var y: CGFloat = 0
                var first = true
                while y <= canvasSize.height {
                    let warped = warpPoint(
                        CGPoint(x: xPos, y: y),
                        toward: body1Center,
                        strength: warpStrength
                    )
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
                    let warped = warpPoint(
                        CGPoint(x: x, y: yPos),
                        toward: body1Center,
                        strength: warpStrength
                    )
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

    // MARK: - Trail Path

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

    private var formulaOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("G\u{03BC}\u{03BD} + \u{039B}g\u{03BC}\u{03BD} = (8\u{03C0}G/c\u{2074})T\u{03BC}\u{03BD}")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    if viewModel.metrics.isBlackHole {
                        Text("r\u{209B} = 2GM/c\u{00B2}  r\u{209A}\u{2095} = 1.5r\u{209B}")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.3))
                    } else {
                        Text("a = -GM/r\u{00B2} + L\u{00B2}/r\u{00B3} - 3GML\u{00B2}/c\u{00B2}r\u{2074}")
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

    /// Star radius: grows slightly with mass multiplier.
    /// Minimum 8pt so it's always clearly visible.
    private var starRadius: CGFloat {
        let baseRadius: CGFloat = 14
        let massScale = CGFloat(log(viewModel.config.mass1Multiplier + 1)) * 0.5 + 1
        return max(8, baseRadius * massScale)
    }

    /// Planet radius: proportionally smaller than the star.
    /// Real ratio is 109:1 but compressed to ~5:1 for visibility.
    /// Heavier planet → denser → slightly smaller. Minimum 3pt.
    private var planetRadius: CGFloat {
        let baseRatio: CGFloat = 5.0
        let baseRadius = starRadius / baseRatio
        let massScale = 1.0 / (CGFloat(log(viewModel.config.mass2Multiplier + 1)) * 0.3 + 1)
        return max(3, baseRadius * massScale)
    }

    private func warpPoint(_ point: CGPoint, toward center: CGPoint, strength: CGFloat) -> CGPoint {
        let dx = center.x - point.x
        let dy = center.y - point.y
        let dist = max(sqrt(dx * dx + dy * dy), 1)
        let warp = strength / dist
        return CGPoint(
            x: point.x + dx * warp,
            y: point.y + dy * warp
        )
    }
}
