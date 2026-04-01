//
//  ContentView.swift
//  CosmicPathSwift
//
//  Root layout view composing the simulation canvas, metrics panel,
//  and control panel into a single screen.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = SimulationViewModel()
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
