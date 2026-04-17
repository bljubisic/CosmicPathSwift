//
//  BlackHoleEffectsView.swift
//  CosmicPathSwift
//
//  Visual effects specific to black hole mode: gravitational lensing glow,
//  accretion disk, photon sphere ring, and ISCO ring.
//

import SwiftUI

/// Visual effects rendered around body1 when it is classified as a black hole.
///
/// These effects are purely cosmetic — they do not affect the physics simulation.
/// Layers (back to front):
/// 1. **Lensing glow**: A faint radial gradient extending to 5×rₛ, simulating
///    the light-bending halo seen around real black holes.
/// 2. **Accretion disk**: Concentric ellipses (viewed at an angle) ranging from
///    1.5×rₛ (photon sphere) to 4×rₛ. Inner rings are brighter and bluer (hotter),
///    outer rings are dimmer and redder (cooler).
/// 3. **ISCO ring**: A faint dashed circle at 3×rₛ (6GM/c²), marking the
///    innermost stable circular orbit.
/// 4. **Photon sphere ring**: A dashed circle at 1.5×rₛ (3GM/c²), marking where
///    photons orbit unstably.
struct BlackHoleEffectsView: View {
    let viewModel: SimulationViewModel

    /// Schwarzschild radius converted from simulation units to canvas pixels.
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

    /// Faint radial glow centered on the black hole, simulating gravitational lensing
    /// of background light. Extends from rₛ to 5×rₛ with decreasing opacity.
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

    /// Draws concentric ellipses representing a tilted accretion disk.
    /// The ellipses have a 0.3 height-to-width ratio to simulate a disk viewed
    /// at ~70° inclination. 12 rings span from 1.5×rₛ to 4×rₛ, transitioning
    /// from yellow (hot inner edge) through orange to red (cooler outer edge).
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

    /// Dashed yellow circle at the ISCO radius (3×rₛ = 6GM/c²).
    /// Orbits inside this radius are unstable — any perturbation causes a plunge.
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

    /// Dashed orange circle at the photon sphere radius (1.5×rₛ = 3GM/c²).
    /// Photons can orbit here in unstable circular paths; inside this radius,
    /// even light spirals inward.
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
