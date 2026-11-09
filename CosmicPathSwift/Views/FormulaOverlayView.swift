//
//  FormulaOverlayView.swift
//  CosmicPathSwift
//
//  The governing equations, shown as a faint watermark. Drawn by
//  `SimulationCanvasView` in its top-left corner, or by `ContentView` under the
//  mass legend while running in portrait, where the canvas reaches under the
//  status bar (issue #25).
//

import SwiftUI

/// The Einstein field equation plus the formula that matches the current scenario:
/// - 3-body mode: the pairwise-summed GR-corrected acceleration
/// - 2-body black hole mode: the Schwarzschild radius and photon sphere formulas
/// - 2-body normal mode: the Schwarzschild geodesic acceleration formula
///
/// The view has no padding or position of its own; the caller places it.
struct FormulaOverlayView: View {
    let viewModel: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("G\u{03BC}\u{03BD} + \u{039B}g\u{03BC}\u{03BD} = (8\u{03C0}G/c\u{2074})T\u{03BC}\u{03BD}")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
            if viewModel.isThreeBodyMode {
                Text("aᵢ = Σⱼ (−Gmⱼ/rᵢⱼ² − 3GmⱼLᵢⱼ²/c²rᵢⱼ⁴) r̂ᵢⱼ")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.18))
            } else if viewModel.metrics.isBlackHole {
                Text("r\u{209B} = 2GM/c\u{00B2}  r\u{209A}\u{2095} = 1.5r\u{209B}")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.3))
                if viewModel.config.isStrongField {
                    // Rings and horizon are at true scale; the disk is decoration.
                    Text("accretion disk illustrative")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.25))
                }
            } else {
                Text("a = -GM/r\u{00B2} - 3GML\u{00B2}/c\u{00B2}r\u{2074}")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.18))
            }
        }
        .allowsHitTesting(false)   // a watermark: drags pass through to the camera gesture
    }
}
