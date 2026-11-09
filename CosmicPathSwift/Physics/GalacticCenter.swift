//
//  GalacticCenter.swift
//  CosmicPathSwift
//
//  The star S2 orbiting Sagittarius A*, the Milky Way's central black hole
//  (issue #21, PR 4). A second scenario of the Realistic strong-field setup.
//
//  S2 is the best-measured relativistic orbit around a black hole: its
//  Schwarzschild precession, 6πGM/(c²a(1−e²)) ≈ 12′ per 16-year orbit, was
//  measured by the GRAVITY collaboration in 2020 and agrees with GR.
//
//  The scenario reuses `ScaleProfile.realisticStrongField` (G = c = 1, length
//  GM☉/c²): the black hole's mass goes into the bodies, so only the masses,
//  the orbit and the time rates differ from the stellar black hole.
//

import Foundation

/// Observed values for S2 around Sagittarius A*.
enum GalacticCenter {
    /// Mass of Sagittarius A*, in M☉.
    static let blackHoleMass: Double = 4.30e6
    /// Mass of S2, in M☉. Estimates range from about 10 to 15; at 3×10⁻⁶ of the
    /// black hole's mass it has no visible effect on the orbit.
    static let starMass: Double = 14
    /// Semi-major axis of S2's orbit, in AU.
    static let semiMajorAxisAU: Double = 1031
    /// Eccentricity of S2's orbit.
    static let eccentricity: Double = 0.884

    /// GR's precession per orbit, 6πGM/(c²a(1−e²)), in radians (≈ 12.2′).
    static var predictedPrecessionPerOrbit: Double {
        let profile = ScaleProfile.realisticStrongField
        let gm = profile.constants.G * (blackHoleMass + starMass) * profile.solarMass
        let a = semiMajorAxisAU * profile.au
        return 6 * .pi * gm / (profile.constants.cSquared * a * (1 - eccentricity * eccentricity))
    }
}
