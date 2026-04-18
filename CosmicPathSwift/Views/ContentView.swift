//
//  ContentView.swift
//  CosmicPathSwift
//
//  Root layout view composing the simulation canvas, metrics panel,
//  and control panel into a single screen.
//

import SwiftUI

/// Root view that composes the simulation canvas, metrics panel, and control panel.
///
/// Uses `GeometryReader` to detect orientation and switch between portrait and
/// landscape layouts. In portrait, the full control panel (sliders + toggles) is
/// shown below the canvas when paused. In landscape, parameter sliders are hidden
/// to maximize canvas area — only play/pause/reset buttons are shown.
///
/// ## Layout States
///
/// - **Portrait, paused**: Title bar + canvas + metrics + full controls (sliders visible)
/// - **Portrait, running**: Full-screen canvas + floating mass legend, metrics, and pause button
/// - **Landscape, paused**: Full-screen canvas + bottom overlay with metrics + minimal controls
/// - **Landscape, running**: Full-screen canvas + floating mass legend, metrics, and pause button
struct ContentView: View {
    @State private var viewModel = SimulationViewModel()
    /// Tracks the current canvas size for passing to the ViewModel on setup/reset.
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Portrait Layout

    /// Portrait layout switches between a full-control editing state (paused) and
    /// a full-screen immersive view (running) with floating overlays.
    private var portraitLayout: some View {
        ZStack {
            if viewModel.isRunning {
                // Running: full-screen canvas with floating pause button and metrics
                SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        massLegend
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    MetricsPanelView(viewModel: viewModel)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    pauseButton
                        .padding(.bottom, 16)
                }
            } else {
                // Paused/stopped: full controls visible
                VStack(spacing: 0) {
                    titleBar

                    SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 8)

                    MetricsPanelView(viewModel: viewModel)
                        .padding(.horizontal)
                        .padding(.top, 6)

                    ControlPanelView(viewModel: viewModel, canvasSize: canvasSize, showParameterControls: true)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Landscape Layout

    /// Landscape layout always shows full-screen canvas. Parameter sliders are hidden
    /// (`showParameterControls: false`) to maximize visual space. Only play/pause/reset
    /// buttons appear in the bottom overlay when paused.
    private var landscapeLayout: some View {
        ZStack(alignment: .bottom) {
            SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                .ignoresSafeArea()

            if viewModel.isRunning {
                // Running: floating pause button and metrics overlay
                VStack {
                    Spacer()
                    HStack {
                        massLegend
                        Spacer()
                        MetricsPanelView(viewModel: viewModel)
                    }
                    .padding(.horizontal)

                    pauseButton
                        .padding(.bottom, 8)
                }
            } else {
                // Paused/stopped: bottom overlay with metrics and controls
                VStack(spacing: 0) {
                    HStack {
                        massLegend
                        Spacer()
                        MetricsPanelView(viewModel: viewModel)
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    ControlPanelView(viewModel: viewModel, canvasSize: canvasSize, showParameterControls: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .background(Color.black.opacity(0.5))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Pause Button

    private var pauseButton: some View {
        Button {
            viewModel.pause()
        } label: {
            Label("Pause", systemImage: "pause.fill")
                .frame(minWidth: 100)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cosmic Path")
                    .font(.title2.bold())
                Text(viewModel.metrics.isBlackHole ? "Black Hole" : "General Relativity")
                    .font(.caption)
                    .foregroundStyle(
                        viewModel.metrics.isBlackHole
                            ? .red.opacity(0.7)
                            : .white.opacity(0.5)
                    )
            }
            Spacer()
            massLegend
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Mass Legend

    /// Color-coded legend showing the current mass label for each celestial body.
    /// Star/BH is orange/red, planet is cyan — matching the rendered body colors.
    private var massLegend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.metrics.isBlackHole ? Color.red : Color.orange)
                    .frame(width: 10, height: 10)
                Text(viewModel.config.mass1Label)
                    .font(.caption)
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                Text(viewModel.config.mass2Label)
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
}
