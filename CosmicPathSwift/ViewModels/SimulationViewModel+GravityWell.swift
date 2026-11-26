//
//  SimulationViewModel+GravityWell.swift
//  CosmicPathSwift
//
//  Camera control for the gravity-well sheet (issue #38).
//

import Foundation

extension SimulationViewModel {

    /// Elevation of the sheet's camera, within `WellCamera.elevationRange`.
    var wellCameraElevation: Double { wellCamera.elevation }

    /// Rotates the sheet's camera by drag deltas. The azimuth is shared with the
    /// orbit view, so both panels of Split turn together; the elevation is the
    /// sheet's own and stays inside `WellCamera.elevationRange`.
    func rotateWellCamera(deltaAzimuth: Double, deltaElevation: Double) {
        wellCamera.elevation = WellCamera.clamped(wellCamera.elevation + deltaElevation)
        rotateCamera(deltaAzimuth: deltaAzimuth, deltaElevation: 0)
    }
}
