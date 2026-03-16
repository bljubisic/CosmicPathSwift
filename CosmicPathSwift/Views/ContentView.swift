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
        VStack(spacing: 0) {
            titleBar

            SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

            MetricsPanelView(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.top, 6)

            ControlPanelView(viewModel: viewModel, canvasSize: canvasSize)
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
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
                Text("M\u{2081} = \(Int(viewModel.config.mass1))")
                    .font(.caption)
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                Text("M\u{2082} = \(Int(viewModel.config.mass2))")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
}
