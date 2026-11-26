//
//  CanvasOverlaysView.swift
//  CosmicPathSwift
//
//  Text drawn over the simulation (formulas, badges, event banner) and the
//  canvas lifecycle, shared by the orbit canvas and the gravity-well sheet
//  (issue #38).
//

import SwiftUI

/// Formula text, badges and the event banner, inset by `insets`
/// (the drawing underneath is not inset).
struct CanvasOverlaysView: View {
    let viewModel: SimulationViewModel
    var insets = EdgeInsets()
    var showsFormulas = true
    var showsEventBanner = true

    var body: some View {
        Group {
            if showsFormulas {
                formulaOverlay
            }

            if viewModel.isThreeBodyMode {
                ChaosTwinBadge(viewModel: viewModel)
            } else {
                HabitableZoneBadge(viewModel: viewModel)
            }

            if showsEventBanner {
                eventOverlay
            }
        }
        .padding(insets)
    }

    /// The governing equations (`FormulaOverlayView`) in the top-left corner.
    private var formulaOverlay: some View {
        VStack(alignment: .leading) {
            HStack {
                FormulaOverlayView(viewModel: viewModel)
                    .padding(8)
                Spacer()
            }
            Spacer()
        }
    }

    /// Absorption (2-body) or merge / ejection (3-body) banner (`EventBannerView`),
    /// centred at the bottom of the canvas.
    private var eventOverlay: some View {
        VStack {
            Spacer()
            EventBannerView(viewModel: viewModel)
                .padding(.bottom, 20)
        }
    }
}

// MARK: - Canvas lifecycle

extension View {
    /// Reports the canvas size and sets the simulation up on first appearance.
    ///
    /// Only the very first appearance creates an engine. In portrait mode, SwiftUI
    /// creates separate canvas instances for the running and paused branches, so
    /// `.onAppear` fires again when the user pauses; calling `setup()` there would
    /// reset the simulation, so later appearances only resize.
    func simulationCanvasLifecycle(
        viewModel: SimulationViewModel, canvasSize: Binding<CGSize>, size: CGSize
    ) -> some View {
        onAppear {
            canvasSize.wrappedValue = size
            if viewModel.isSetup {
                viewModel.resizeCanvas(size)
            } else {
                viewModel.setup(canvasSize: size)
            }
        }
        .onChange(of: size) { _, newSize in
            canvasSize.wrappedValue = newSize
            viewModel.resizeCanvas(newSize)
        }
    }
}
