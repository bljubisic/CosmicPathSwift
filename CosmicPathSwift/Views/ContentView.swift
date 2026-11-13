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
    /// Whether the Advanced sheet is open.
    @State private var isShowingAdvanced = false
    /// Whether the "What am I looking at?" sheet is open (issue #34).
    @State private var isShowingInfo = false
    /// Opt-in that reveals the Advanced button (toggled in `ControlPanelView`).
    @AppStorage(AdvancedSettings.optInStorageKey) private var isAdvancedEnabled = false
    /// Scenario from a deep link that arrived before the canvas had a size (cold launch).
    @State private var pendingScenario: SimulationConfig?

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if isLandscape {
                    landscapeLayout(safeArea: geometry.safeAreaInsets)
                } else {
                    portraitLayout(safeArea: geometry.safeAreaInsets)
                }
            }
        }
        .preferredColorScheme(.dark)
        // Share sheet: includes Save Video, AirDrop, Messages, Mail, and all installed apps.
        // Shown when recorder.stop() sets pendingRecording; dismissing clears it, and
        // the recorder deletes the temp file regardless of outcome.
        .sheet(item: Bindable(viewModel.recorder).pendingRecording) { recording in
            VideoShareSheet(url: recording.url)
        }
        .sheet(isPresented: $isShowingAdvanced) {
            AdvancedControlsView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingInfo) {
            InfoSheetView(viewModel: viewModel)
        }
        // Deep links (`cosmicpath://scenario/<group>/<name>`, issue #33). Unknown links
        // just open the app. Until the canvas has a size, the scenario waits.
        .onOpenURL { url in
            guard let scenario = AppScenario(url: url) else { return }
            if canvasSize == .zero {
                pendingScenario = scenario.config
            } else {
                viewModel.open(scenario, canvasSize: canvasSize)
            }
        }
        .onChange(of: canvasSize) { oldSize, newSize in
            guard oldSize == .zero, newSize != .zero,
                  let config = pendingScenario ?? launchScenario else { return }
            let isFromLink = pendingScenario != nil
            pendingScenario = nil
            viewModel.run(config, canvasSize: newSize)
            #if DEBUG
            if !isFromLink {
                freezeScreenshotScene()
                // `-openInfo YES` also opens the info sheet, for screenshots of it.
                if UserDefaults.standard.bool(forKey: "openInfo") { isShowingInfo = true }
            }
            #endif
        }
    }

    /// Debug only: the App Store screenshot scene named by `-screenshotScene <name>`.
    private var launchScenario: SimulationConfig? {
        #if DEBUG
        ScreenshotScene.fromLaunchArguments?.config
        #else
        nil
        #endif
    }

    #if DEBUG
    /// Freezes the launch-argument screenshot scene at its capture moment and,
    /// with `-artworkExport YES`, renders the App Store header and search images.
    private func freezeScreenshotScene() {
        guard let scene = ScreenshotScene.fromLaunchArguments,
              !ScreenshotScene.isRecordingFromLaunchArguments else { return }
        Task {
            await scene.freeze(viewModel)
            if ArtworkExport.isRequested {
                ArtworkExport.export(viewModel, name: scene.rawValue, canvasSize: canvasSize)
            }
        }
    }
    #endif

    // MARK: - Portrait Layout

    /// Portrait layout switches between a full-control editing state (paused) and
    /// a full-screen immersive view (running) with floating overlays.
    ///
    /// While running, the canvas draws under the status bar, so it gets the
    /// safe-area insets for its own overlays, and the formula text moves under
    /// the mass legend, which would otherwise share the top-left corner (#25).
    /// The event banner sits directly above the metrics, so the floating
    /// controls can't cover it (#26).
    private func portraitLayout(safeArea: EdgeInsets) -> some View {
        ZStack {
            if viewModel.isRunning {
                // Running: full-screen canvas with floating pause button and metrics
                SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize,
                                     overlayInsets: safeArea, showsFormulas: false, showsEventBanner: false)
                    .ignoresSafeArea()

                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            massLegend
                            FormulaOverlayView(viewModel: viewModel)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    EventBannerView(viewModel: viewModel)
                        .padding(.bottom, 8)

                    MetricsPanelView(viewModel: viewModel)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    HStack(spacing: 16) {
                        pauseButton
                        recordButton
                        floatingInfoButton
                        floatingAdvancedButton
                    }
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

                    ControlPanelView(viewModel: viewModel, canvasSize: canvasSize, showParameterControls: true,
                                     onShowAdvanced: { isShowingAdvanced = true },
                                     onShowInfo: { isShowingInfo = true })
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
    ///
    /// The canvas draws edge to edge, so it gets the safe-area insets to keep its
    /// overlays clear of the Dynamic Island and the corners (#25). The bottom of
    /// the screen belongs to the controls in both states, so the event banner sits
    /// directly above them (#26).
    private func landscapeLayout(safeArea: EdgeInsets) -> some View {
        ZStack(alignment: .bottom) {
            SimulationCanvasView(viewModel: viewModel, canvasSize: $canvasSize,
                                 overlayInsets: safeArea, showsEventBanner: false)
                .ignoresSafeArea()

            if viewModel.isRunning {
                // Running: floating pause button and metrics overlay
                VStack {
                    Spacer()
                    EventBannerView(viewModel: viewModel)
                    HStack {
                        massLegend
                        Spacer()
                        MetricsPanelView(viewModel: viewModel)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        pauseButton
                        recordButton
                        floatingInfoButton
                        floatingAdvancedButton
                    }
                    .padding(.bottom, 8)
                }
            } else {
                // Paused/stopped: bottom overlay with metrics and controls, event banner above it
                VStack(spacing: 8) {
                    EventBannerView(viewModel: viewModel)

                    VStack(spacing: 0) {
                        HStack {
                            massLegend
                            Spacer()
                            MetricsPanelView(viewModel: viewModel)
                        }
                        .padding(.horizontal)
                        .padding(.top, 6)

                        ControlPanelView(viewModel: viewModel, canvasSize: canvasSize, showParameterControls: false,
                                         onShowAdvanced: { isShowingAdvanced = true },
                                         onShowInfo: { isShowingInfo = true })
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .background(Color.black.opacity(0.5))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Record Button

    /// Floating record/stop button shown alongside the pause button while the simulation runs.
    ///
    /// Tapping starts or stops a ReplayKit screen recording. A pulsing red icon indicates
    /// an active recording. When stopped, `pendingRecording` triggers the save/share sheet.
    private var recordButton: some View {
        Button {
            if viewModel.recorder.isRecording {
                viewModel.recorder.stop()
            } else {
                viewModel.recorder.start()
            }
        } label: {
            Image(systemName: viewModel.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.title2)
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: viewModel.recorder.isRecording)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Button

    /// Floating "What am I looking at?" button next to Pause/Record while running (issue #34).
    private var floatingInfoButton: some View {
        Button {
            isShowingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title2)
                .foregroundStyle(.teal)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What am I looking at?")
    }

    // MARK: - Advanced Button

    /// Floating Advanced button shown next to Pause/Record while running, once the
    /// user has opted in. Lets display options be changed without pausing.
    @ViewBuilder
    private var floatingAdvancedButton: some View {
        if isAdvancedEnabled {
            Button {
                isShowingAdvanced = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced")
        }
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
                Text("Simple Orbit Simulator")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        showsBlackHole
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

    /// Black hole styling only applies in 2-body mode.
    private var showsBlackHole: Bool {
        !viewModel.isThreeBodyMode && viewModel.metrics.isBlackHole
    }

    private var subtitle: String {
        if viewModel.isThreeBodyMode { return "Three-Body Problem" }
        return viewModel.metrics.isBlackHole ? "Black Hole" : "General Relativity"
    }

    // MARK: - Mass Legend

    /// Color-coded legend showing the current mass label for each celestial body,
    /// matching the rendered body colours: star/BH orange/red and planet cyan in
    /// 2-body mode, the per-ID palette in 3-body mode.
    ///
    /// Entries sit side by side when they fit, otherwise one per line, so a
    /// label never wraps (three Realistic labels like "C 0.0123 M⊕" don't fit
    /// next to the title on a phone).
    private var massLegend: some View {
        let labels = viewModel.bodyLabels
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { legendEntries(labels) }
            VStack(alignment: .leading, spacing: 2) { legendEntries(labels) }
        }
        .foregroundStyle(.white)
    }

    private func legendEntries(_ labels: [String]) -> some View {
        ForEach(labels.indices, id: \.self) { index in
            HStack(spacing: 4) {
                Circle()
                    .fill(legendColor(for: index))
                    .frame(width: 10, height: 10)
                Text(labels[index])
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private func legendColor(for index: Int) -> Color {
        if viewModel.isThreeBodyMode {
            let ids = viewModel.bodyIDs
            return BodyView.paletteColor(for: ids.indices.contains(index) ? ids[index] : index)
        }
        if index == 0 { return viewModel.metrics.isBlackHole ? .red : .orange }
        return .cyan
    }
}

#Preview {
    ContentView()
}

// MARK: - Video Share Sheet

/// UIViewControllerRepresentable wrapper for `UIActivityViewController`.
///
/// Presents the system share sheet for a recorded video file, allowing the user
/// to share via AirDrop, Messages, Mail, or any installed app, and includes
/// the standard "Save to Photos" activity. The sheet dismisses itself when the
/// user taps Cancel or completes an activity.
private struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
