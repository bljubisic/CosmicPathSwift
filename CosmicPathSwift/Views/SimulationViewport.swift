//
//  SimulationViewport.swift
//  CosmicPathSwift
//
//  The canvas area in the chosen view mode (issue #38): the orbit canvas,
//  the gravity-well sheet, or both (Split). Switching is render-only.
//

import SwiftUI

struct SimulationViewport: View {
    let viewModel: SimulationViewModel
    @Binding var canvasSize: CGSize
    var overlayInsets = EdgeInsets()
    var showsFormulas = true
    var showsEventBanner = true

    /// Share of Split's height (portrait) the orbit view takes; the sheet gets the rest.
    private static let splitOrbitFraction: CGFloat = 0.4

    var body: some View {
        switch viewModel.config.advanced.display.viewMode {
        case .twoD:
            SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize, overlayInsets: overlayInsets,
                                 showsFormulas: showsFormulas, showsEventBanner: showsEventBanner)
        case .threeD:
            GravityWellView(viewModel: viewModel, canvasSize: $canvasSize, overlayInsets: overlayInsets,
                            showsFormulas: showsFormulas, showsEventBanner: showsEventBanner)
        case .split:
            split
        }
    }

    /// Orbit view on top and the sheet below in portrait (like the reel),
    /// side by side in landscape. The orbit view drives the simulation and
    /// keeps the overlays; the sheet only draws.
    private var split: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize,
                                     overlayInsets: orbitInsets(isLandscape: isLandscape),
                                     // A half-width panel has no room for formulas beside the badges.
                                     showsFormulas: showsFormulas && !isLandscape, showsEventBanner: showsEventBanner)
                    .frame(
                        width: isLandscape ? geometry.size.width / 2 : nil,
                        height: isLandscape ? nil : geometry.size.height * Self.splitOrbitFraction
                    )
                GravityWellView(viewModel: viewModel, canvasSize: $canvasSize,
                                drivesSimulation: false, showsOverlays: false)
                    .overlay(alignment: isLandscape ? .leading : .top) {
                        Rectangle().fill(.white.opacity(0.15))
                            .frame(width: isLandscape ? 1 : nil, height: isLandscape ? nil : 1)
                    }
            }
        }
    }

    /// The orbit panel's share of the safe-area insets: none on the side the sheet takes.
    private func orbitInsets(isLandscape: Bool) -> EdgeInsets {
        var insets = overlayInsets
        if isLandscape { insets.trailing = 0 } else { insets.bottom = 0 }
        return insets
    }
}
