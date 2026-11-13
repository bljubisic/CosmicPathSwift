//
//  ArtworkExportTests.swift
//  CosmicPathSwiftTests
//
//  Issue #33: App Store header and search results images. Sizes follow App
//  Store Connect's creative asset specifications; the safe areas were measured
//  from Apple's templates.
//

import Testing
import Foundation
@testable import CosmicPathSwift

struct ArtworkAssetTests {

    @Test func headerIs21by9At3840() {
        #expect(ArtworkAsset.header.pixelSize == CGSize(width: 3840, height: 1646))
    }

    @Test func searchResultsIs3by2AtMaximum() {
        #expect(ArtworkAsset.searchResults.pixelSize == CGSize(width: 3840, height: 2560))
    }

    /// Rendering at `pointSize` × `renderScale` must give the exact pixel size.
    @Test(arguments: ArtworkAsset.allCases)
    func pointSizeTimesScaleIsPixelSize(asset: ArtworkAsset) {
        #expect(asset.pointSize.width * asset.renderScale == asset.pixelSize.width)
        #expect(asset.pointSize.height * asset.renderScale == asset.pixelSize.height)
    }

    /// Apple's safe areas are centred; the fit relies on that.
    @Test(arguments: ArtworkAsset.allCases)
    func safeAreaIsCentredInsideTheImage(asset: ArtworkAsset) {
        let bounds = CGRect(origin: .zero, size: asset.pixelSize)
        #expect(bounds.contains(asset.safeArea))
        #expect(abs(asset.safeArea.midX - bounds.midX) <= 1)
        #expect(abs(asset.safeArea.midY - bounds.midY) <= 1)
    }
}

@MainActor
struct ArtworkFitTests {

    private func makeViewModel(_ scenario: AppScenario) -> SimulationViewModel {
        let vm = SimulationViewModel { MockSimulationEngine(bodies: $0.bodies) }
        vm.config = scenario.config
        vm.setup(canvasSize: CGSize(width: 440, height: 956))
        return vm
    }

    /// After fitting, every body lies inside the safe area (in points).
    @Test(arguments: ArtworkAsset.allCases)
    func bodiesFitInsideSafeArea(asset: ArtworkAsset) {
        for scenario in [AppScenario.figureEight, .blackHoleVisual, .lagrange] {
            let vm = makeViewModel(scenario)
            vm.resizeCanvas(asset.pointSize)
            vm.setViewportScale(ArtworkExport.fittingScale(vm, asset: asset))
            let safe = asset.safeArea.applying(CGAffineTransform(scaleX: 1 / asset.renderScale, y: 1 / asset.renderScale))
            for position in vm.bodyPositions {
                #expect(safe.insetBy(dx: -0.5, dy: -0.5).contains(position), "\(scenario) \(asset): \(position) outside \(safe)")
            }
        }
    }

    @Test func fittingScaleStaysInRange() {
        let vm = makeViewModel(.figureEight)
        for asset in ArtworkAsset.allCases {
            vm.resizeCanvas(asset.pointSize)
            #expect(ArtworkExport.viewportScaleRange.contains(ArtworkExport.fittingScale(vm, asset: asset)))
        }
    }

    /// Zooming out by 2 halves every body's offset from the canvas centre.
    @Test func viewportScaleZoomsAboutTheCentre() {
        let vm = makeViewModel(.figureEight)
        let size = CGSize(width: 800, height: 400)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        vm.resizeCanvas(size)
        let before = vm.bodyPositions
        vm.setViewportScale(2)
        for (old, new) in zip(before, vm.bodyPositions) {
            #expect(abs((new.x - center.x) * 2 - (old.x - center.x)) < 1e-6)
            #expect(abs((new.y - center.y) * 2 - (old.y - center.y)) < 1e-6)
        }
        vm.setViewportScale(1)
        #expect(vm.bodyPositions == before)
    }
}
