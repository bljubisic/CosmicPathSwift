//
//  SimulationViewModel+GravityWell.swift
//  CosmicPathSwift
//
//  Camera control for the gravity-well sheet (issue #38).
//

import Foundation

extension SimulationViewModel {

    /// Rotates the sheet's camera by drag deltas. The azimuth is shared with the
    /// orbit view, so both panels of Split turn together; the elevation is the
    /// sheet's own and stays inside `WellCamera.elevationRange`.
    func rotateWellCamera(deltaAzimuth: Double, deltaElevation: Double) {
        wellCameraElevation = WellCamera.clamped(wellCameraElevation + deltaElevation)
        rotateCamera(deltaAzimuth: deltaAzimuth, deltaElevation: 0)
    }
}
