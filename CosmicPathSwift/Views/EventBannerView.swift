//
//  EventBannerView.swift
//  CosmicPathSwift
//
//  The banner announcing that something ended the orbit: the planet was
//  absorbed (2-body), or bodies merged or one was ejected (3-body).
//
//  Drawn by `SimulationCanvasView` at the bottom of the canvas when the canvas
//  sits inside the layout (paused portrait), and by `ContentView` directly above
//  the metrics when the canvas fills the screen, so the floating controls can
//  never cover it (issue #26).
//

import SwiftUI

/// The event card itself, or nothing when no event happened.
/// The view has no position of its own; the caller places it.
struct EventBannerView: View {
    let viewModel: SimulationViewModel

    var body: some View {
        if viewModel.isThreeBodyMode {
            let metrics = viewModel.systemMetrics
            if let collision = metrics.collision {
                card(
                    title: "Collision",
                    details: ["\(letter(collision.0)) + \(letter(collision.1)) merged"]
                        + (metrics.ejectedBodyID.map { ["Body \(letter($0)) ejected"] } ?? []),
                    color: .red
                )
            } else if let ejected = metrics.ejectedBodyID {
                card(title: "Ejection", details: ["Body \(letter(ejected)) ejected"], color: .orange)
            }
        } else if viewModel.metrics.isAbsorbed {
            let isBlackHole = viewModel.metrics.isBlackHole
            card(
                title: isBlackHole ? "Event Horizon Crossed" : "Collision",
                details: [isBlackHole ? "Object absorbed by black hole" : "Planet collided with the star"],
                color: .red
            )
        }
    }

    private func letter(_ id: Int) -> String {
        SystemMetrics.letter(for: id)
    }

    private func card(title: String, details: [String], color: Color) -> some View {
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
    }
}
