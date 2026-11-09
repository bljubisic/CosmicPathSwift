//
//  InitialConditions+SunEarthMoon.swift
//  CosmicPathSwift
//
//  The Sun–Planet–Moon preset in the Realistic scale (issue #21, PR 2): the
//  real Sun, Earth and Moon. Visual keeps its compressed, lighter triple
//  (`InitialConditions.SunPlanetMoon`).
//

import Foundation

extension InitialConditions {

    /// Sun, Earth and Moon on circular orbits, in a scale's units.
    enum SunEarthMoon {
        /// Moon mass in Earth masses.
        static let moonMassInEarthMasses: Double = 0.0123
        /// Mean Earth–Moon distance, 384,400 km, in AU.
        static let moonDistanceAU: Double = 0.0025695

        /// Sun at the origin, Earth at 1 AU on +x, Moon beyond Earth on +x.
        /// Both orbits use the GR-corrected circular speed (`SunPlanetMoon.circularSpeed`)
        /// and are prograde. `threeBody` moves the result to the CoM frame.
        static func bodies(scale: ScaleProfile) -> [CelestialBody] {
            let sunMass = scale.solarMass
            let earthMass = scale.earthMass
            let moonMass = earthMass * moonMassInEarthMasses
            let orbitRadius = scale.au
            let moonDistance = moonDistanceAU * scale.au

            let earthSpeed = SunPlanetMoon.circularSpeed(
                mass: sunMass + earthMass + moonMass, radius: orbitRadius, constants: scale.constants
            )
            let moonSpeed = SunPlanetMoon.circularSpeed(
                mass: earthMass + moonMass, radius: moonDistance, constants: scale.constants
            )

            return [
                CelestialBody(id: 0, kind: .star, mass: sunMass, position: .zero, velocity: .zero),
                CelestialBody(id: 1, kind: .planet, mass: earthMass,
                              position: Vector3D(x: orbitRadius, y: 0, z: 0),
                              velocity: Vector3D(x: 0, y: earthSpeed, z: 0)),
                CelestialBody(id: 2, kind: .moon, mass: moonMass,
                              position: Vector3D(x: orbitRadius + moonDistance, y: 0, z: 0),
                              velocity: Vector3D(x: 0, y: earthSpeed + moonSpeed, z: 0))
            ]
        }
    }
}
