//
//  ArtworkExport.swift
//  CosmicPathSwift
//
//  Debug-only App Store creative assets (issue #33): the product page header
//  (21:9, 3840 × 1646) and the search results image (3:2, 3840 × 2560).
//  Launch with `-screenshotScene <name> -artworkExport YES`. Once the scene
//  freezes at its capture moment, the canvas is re-projected at each asset's
//  size and rendered offscreen, with no overlays and no app chrome, to
//  Documents/artwork/<scene>-<asset>.png. `AppStore/capture-screenshots.sh
//  --artwork` copies them out. Not compiled into Release builds.
//
//  Each image is zoomed so the scene's trails and bodies fill about 90% of
//  Apple's art safe area (measured from Apple's templates; the only part shown
//  on every device), while the spacetime grid fills the crop margins.
//

#if DEBUG
import SwiftUI
import UIKit
import os

/// An App Store creative asset size.
enum ArtworkAsset: String, CaseIterable {
    /// Product page header, 21:9.
    case header
    /// Search results image, 3:2 (the maximum size).
    case searchResults

    /// Final size in pixels (App Store Connect's creative asset specifications).
    var pixelSize: CGSize {
        switch self {
        case .header: return CGSize(width: 3840, height: 1646)
        case .searchResults: return CGSize(width: 3840, height: 2560)
        }
    }

    /// Art safe area in pixels, measured from Apple's Photoshop templates
    /// (creative_assets-product_page_header_template / search_results_template).
    var safeArea: CGRect {
        switch self {
        case .header: return CGRect(x: 1097, y: 493, width: 1646, height: 661)
        case .searchResults: return CGRect(x: 836, y: 765, width: 2168, height: 1030)
        }
    }

    /// Render scale: points × scale = pixels, chosen so lines and glows keep
    /// their in-app weight where the asset is shown. On iPhone the header is
    /// cropped to about its safe area across the screen (≈ 4 px per point); a
    /// search result card spans the whole 3:2 image across the screen (≈ 10).
    var renderScale: CGFloat {
        switch self {
        case .header: return 4
        case .searchResults: return 8
        }
    }

    /// Share of the safe area the scene fills.
    static let safeAreaFill: CGFloat = 0.9

    /// Canvas size in points.
    var pointSize: CGSize {
        CGSize(width: pixelSize.width / renderScale, height: pixelSize.height / renderScale)
    }
}

enum ArtworkExport {
    private static let logger = Logger(subsystem: "CosmicPathSwift", category: "ArtworkExport")

    /// Whether `-artworkExport YES` was passed.
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "artworkExport")
    }

    /// Folder the PNGs are written to (the app's Documents/artwork).
    static var outputDirectory: URL {
        URL.documentsDirectory.appending(path: "artwork", directoryHint: .isDirectory)
    }

    /// Renders every asset for the frozen `viewModel`, then restores `canvasSize`.
    @MainActor
    static func export(_ viewModel: SimulationViewModel, name: String, canvasSize: CGSize) {
        // Simulation only: no centre-of-mass marker, no habitable zone.
        viewModel.config.advanced.display.showCenterOfMass = false
        viewModel.setHabitableZoneVisible(false)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            for asset in ArtworkAsset.allCases {
                try render(viewModel, asset: asset, to: outputDirectory.appending(path: "\(name)-\(asset.rawValue).png"))
            }
        } catch {
            logger.error("Artwork export for \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        viewModel.setViewportScale(1)
        viewModel.resizeCanvas(canvasSize)
    }

    /// Re-projects the simulation at `asset`'s size and writes an opaque PNG.
    @MainActor
    private static func render(_ viewModel: SimulationViewModel, asset: ArtworkAsset, to url: URL) throws {
        let size = asset.pointSize
        viewModel.setViewportScale(1)
        viewModel.resizeCanvas(size)
        viewModel.setViewportScale(fittingScale(viewModel, asset: asset))
        let content = ZStack {
            // The canvas background is 95% black; App Store assets can't have alpha.
            Color.black
            SimulationCanvasView(viewModel: viewModel, canvasSize: .constant(size), showsOverlays: false)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = asset.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw ArtworkExportError.renderFailed(asset)
        }
        try data.write(to: url, options: .atomic)
        logger.info("Wrote \(url.lastPathComponent, privacy: .public)")
    }
}

extension ArtworkExport {
    /// Zoom bounds, so a tiny trail (a plunge) or a far-flung body can't
    /// blow the scene up or shrink it to a dot.
    static let viewportScaleRange: ClosedRange<Double> = 0.4...4

    /// Viewport scale that fits the projected trails and bodies into the safe area.
    /// The projection is linear about the canvas centre, so scaling by `s` divides
    /// every offset from the centre by `s`.
    @MainActor
    static func fittingScale(_ viewModel: SimulationViewModel, asset: ArtworkAsset) -> Double {
        let points = viewModel.bodyTrails.flatMap { $0 } + viewModel.bodyPositions
        guard !points.isEmpty else { return 1 }
        let center = CGPoint(x: asset.pointSize.width / 2, y: asset.pointSize.height / 2)
        let maxDX = points.map { abs($0.x - center.x) }.max() ?? 0
        let maxDY = points.map { abs($0.y - center.y) }.max() ?? 0
        let halfSafeWidth = asset.safeArea.width / asset.renderScale / 2 * ArtworkAsset.safeAreaFill
        let halfSafeHeight = asset.safeArea.height / asset.renderScale / 2 * ArtworkAsset.safeAreaFill
        let scale = max(maxDX / halfSafeWidth, maxDY / halfSafeHeight)
        return min(max(Double(scale), viewportScaleRange.lowerBound), viewportScaleRange.upperBound)
    }
}

enum ArtworkExportError: LocalizedError {
    case renderFailed(ArtworkAsset)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let asset): return "Could not render the \(asset.rawValue) image."
        }
    }
}
#endif
