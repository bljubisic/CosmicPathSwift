//
//  GravityWellView.swift
//  CosmicPathSwift
//
//  The gravity-well sheet (issue #38): spacetime drawn as a rubber sheet
//  seen at an angle, pulled down under each body. Projects the view model's
//  `GravityWellScene` through its own camera (`GravityWellMesh`) and draws
//  it in one `Canvas`, with the bodies on top at the bottom of their wells.
//
//  Drag rotates (azimuth shared with the orbit view, elevation the sheet's
//  own); pinch zooms the sheet.
//

import SwiftUI

struct GravityWellView: View {
    let viewModel: SimulationViewModel
    @Binding var canvasSize: CGSize
    /// True when this view is the only canvas (3D), so it sets the simulation up
    /// and reports its size. In Split the orbit canvas does that.
    var drivesSimulation = true
    var overlayInsets = EdgeInsets()
    var showsFormulas = true
    var showsEventBanner = true
    var showsOverlays = true

    @State private var previousDragTranslation: CGSize = .zero
    /// Zoom when the current pinch began; nil between pinches.
    @State private var pinchBase: Double?

    /// Radians of camera rotation per point of drag, as in the orbit view.
    private let cameraDragSensitivity: Double = 0.005

    private var display: DisplaySettings { viewModel.config.advanced.display }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.95)

                if let scene = viewModel.gravityWellScene {
                    let transformer = makeTransformer(scene: scene, size: geometry.size)
                    let mesh = GravityWellMesh.make(scene: scene, transformer: transformer)
                    Group {
                        sheet(mesh: mesh, scene: scene)
                        bodies(mesh: mesh, scene: scene, transformer: transformer, size: geometry.size)
                    }
                    .offset(y: verticalShift(scene: scene, transformer: transformer))
                }

                if showsOverlays {
                    CanvasOverlaysView(viewModel: viewModel, insets: overlayInsets,
                                       showsFormulas: showsFormulas, showsEventBanner: showsEventBanner)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .modifier(LifecycleIfDriving(
                isDriving: drivesSimulation, viewModel: viewModel, canvasSize: $canvasSize, size: geometry.size
            ))
            .gesture(rotateGesture)
            .simultaneousGesture(pinchGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gravity wells: spacetime drawn as a sheet pulled down under each body")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Camera

    /// Orthographic camera on the CoM-centred scene, zoomed by the pinch.
    private func makeTransformer(scene: GravityWellScene, size: CGSize) -> CoordinateTransformer {
        CoordinateTransformer(
            canvasSize: size,
            simulationSeparation: scene.viewExtent / viewModel.wellCamera.zoom,
            azimuth: viewModel.cameraAzimuth,
            elevation: viewModel.wellCameraElevation
        )
    }

    /// Moves the drawing up by half the deepest well's on-screen drop, so the
    /// sheet and its wells sit centred rather than the flat sheet alone.
    private func verticalShift(scene: GravityWellScene, transformer: CoordinateTransformer) -> CGFloat {
        let deepest = scene.bodies.map { scene.surface.depth(x: $0.position.x, y: $0.position.y) }.max() ?? 0
        return -CGFloat(0.5 * sin(transformer.elevation) * deepest * transformer.scale)
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let deltaX = Double(value.translation.width - previousDragTranslation.width)
                let deltaY = Double(value.translation.height - previousDragTranslation.height)
                previousDragTranslation = value.translation
                viewModel.rotateWellCamera(
                    deltaAzimuth: deltaX * cameraDragSensitivity,
                    deltaElevation: deltaY * cameraDragSensitivity
                )
            }
            .onEnded { _ in previousDragTranslation = .zero }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? viewModel.wellCamera.zoom
                pinchBase = base
                viewModel.wellCamera.pinch(scale: value.magnification, from: base)
            }
            .onEnded { _ in pinchBase = nil }
    }

    // MARK: - Sheet

    /// Grid, contours, rings, horizon and trails, back to front.
    private func sheet(mesh: GravityWellMesh, scene: GravityWellScene) -> some View {
        Canvas { context, _ in
            if display.showSpacetimeGrid {
                for line in mesh.gridLines {
                    context.stroke(Self.polyline(line), with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                }
            }
            for contour in mesh.contours {
                let color = BodyAppearance.color(for: scene.bodies[contour.bodyIndex].index, viewModel: viewModel)
                context.stroke(Self.polyline(contour.points), with: .color(color.opacity(0.45)), lineWidth: 1)
            }
            for ring in mesh.rings {
                let style = Self.style(for: ring.kind)
                context.stroke(Self.polyline(ring.points), with: .color(style.color), style: style.stroke)
            }
            if let horizon = mesh.horizon {
                let outline = Self.polyline(horizon)
                context.fill(outline, with: .color(.black))
                context.stroke(outline, with: .color(.red.opacity(0.6)), lineWidth: 1.5)
            }
            for (position, trail) in mesh.trails.enumerated() {
                let color = BodyAppearance.trailColor(for: scene.bodies[position].index, viewModel: viewModel)
                TrailRenderer.stroke(trail, color: color, in: context)
            }
        }
    }

    // MARK: - Bodies

    /// Every body at the bottom of its well, far to near.
    private func bodies(
        mesh: GravityWellMesh, scene: GravityWellScene, transformer: CoordinateTransformer, size: CGSize
    ) -> some View {
        let sizeScale = BodyAppearance.zoomSizeScale(viewModel: viewModel, canvasSize: size, coordinateScale: transformer.scale)
        return ForEach(mesh.renderOrder, id: \.self) { position in
            BodyAppearance.bodyView(
                for: scene.bodies[position].index, viewModel: viewModel,
                zoomSizeScale: sizeScale, coordinateScale: transformer.scale
            )
            .position(mesh.bodyPoints[position])
        }
    }

    // MARK: - Drawing helpers

    private static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// Ring colours follow the orbit view: red horizon, orange photon sphere,
    /// yellow ISCO, green habitable zone, purple Roche limit.
    private static func style(for kind: WellRing.Kind) -> (color: Color, stroke: StrokeStyle) {
        let dashed = StrokeStyle(lineWidth: 1, dash: [4, 4])
        switch kind {
        case .schwarzschild: return (.red.opacity(0.6), StrokeStyle(lineWidth: 1.5))
        case .photonSphere: return (.orange.opacity(0.5), dashed)
        case .isco: return (.yellow.opacity(0.4), dashed)
        case .habitableInner, .habitableOuter: return (.green.opacity(0.5), StrokeStyle(lineWidth: 1))
        case .roche: return (.purple.opacity(0.6), dashed)
        }
    }
}

// MARK: - Lifecycle

/// Applies `simulationCanvasLifecycle` only when the view drives the simulation.
private struct LifecycleIfDriving: ViewModifier {
    let isDriving: Bool
    let viewModel: SimulationViewModel
    @Binding var canvasSize: CGSize
    let size: CGSize

    func body(content: Content) -> some View {
        if isDriving {
            content.simulationCanvasLifecycle(viewModel: viewModel, canvasSize: $canvasSize, size: size)
        } else {
            content
        }
    }
}
