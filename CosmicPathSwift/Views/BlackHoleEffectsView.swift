//
//  BlackHoleEffectsView.swift
//  CosmicPathSwift
//
//  Visual effects specific to black hole mode: gravitational lensing glow,
//  accretion disk, photon sphere ring, and ISCO ring.
//

import SwiftUI

struct BlackHoleEffectsView: View {
    let viewModel: SimulationViewModel

    private var rs: CGFloat {
        CGFloat(viewModel.metrics.schwarzschildRadius) * CGFloat(viewModel.coordinateScale)
    }

    var body: some View {
        ZStack {
            lensingGlow
            accretionDisk
            iscoRing
            photonSphereRing
        }
    }

    // MARK: - Gravitational Lensing Glow

    private var lensingGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .clear,
                        .clear,
                        .orange.opacity(0.05),
                        .yellow.opacity(0.08),
                        .orange.opacity(0.04),
                        .clear
                    ],
                    center: .center,
                    startRadius: rs,
                    endRadius: rs * 5
                )
            )
            .frame(width: rs * 10, height: rs * 10)
            .position(viewModel.body1Position)
    }

    // MARK: - Accretion Disk

    private var accretionDisk: some View {
        Canvas { context, _ in
            let center = viewModel.body1Position
            let innerRadius = rs * 1.5
            let outerRadius = rs * 4.0
            let ringCount = 12

            for i in 0..<ringCount {
                let t = Double(i) / Double(ringCount)
                let radius = innerRadius + (outerRadius - innerRadius) * t
                let opacity = (1.0 - t) * 0.25

                let color: Color = t < 0.3
                    ? .yellow.opacity(opacity)
                    : (t < 0.6 ? .orange.opacity(opacity) : .red.opacity(opacity * 0.5))

                var ring = Path()
                ring.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius * 0.3,
                    width: radius * 2,
                    height: radius * 0.6
                ))
                context.stroke(ring, with: .color(color), lineWidth: 1.5)
            }
        }
    }

    // MARK: - ISCO Ring

    private var iscoRing: some View {
        Circle()
            .stroke(
                Color.yellow.opacity(0.15),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
            )
            .frame(
                width: CGFloat(viewModel.metrics.iscoRadius) * CGFloat(viewModel.coordinateScale) * 2,
                height: CGFloat(viewModel.metrics.iscoRadius) * CGFloat(viewModel.coordinateScale) * 2
            )
            .position(viewModel.body1Position)
    }

    // MARK: - Photon Sphere Ring

    private var photonSphereRing: some View {
        Circle()
            .stroke(
                Color.orange.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            .frame(
                width: CGFloat(viewModel.metrics.photonSphereRadius) * CGFloat(viewModel.coordinateScale) * 2,
                height: CGFloat(viewModel.metrics.photonSphereRadius) * CGFloat(viewModel.coordinateScale) * 2
            )
            .position(viewModel.body1Position)
    }
}
