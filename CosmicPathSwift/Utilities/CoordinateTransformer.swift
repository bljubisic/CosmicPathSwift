//
//  CoordinateTransformer.swift
//  CosmicPathSwift
//
//  Projects 3D simulation-space coordinates to 2D canvas coordinates using
//  an orthographic camera parameterised by azimuth and elevation angles.
//
//  ## Coordinate Systems
//
//  **Simulation space** (3D, origin at center-of-mass):
//    • x-axis: initial radial direction (body2 starts here)
//    • y-axis: initial tangential direction (orbital velocity at zero inclination)
//    • z-axis: out of the default orbital plane (non-zero for inclined orbits)
//
//  **Camera space** (after rotation, still 3D):
//    • Produced by applying azimuth rotation then elevation tilt.
//    • The camera's screenX and screenY axes map directly to canvas.
//
//  **Canvas space** (2D, origin at top-left):
//    • Produced by scaling camera-space (screenX, screenY) and translating
//      by the canvas center point.
//
//  ## Projection Math
//
//  The projection is orthographic (no perspective divide). It is parameterised
//  by two camera angles:
//
//    φ (azimuth):   rotation around the z-axis (vertical axis of the orbital plane).
//                   Drag left/right rotates the scene horizontally.
//
//    θ (elevation): tilt above the orbital plane.
//                   At θ=0° the full orbit is visible (top-down view, the orbit
//                   projects to its true shape). At θ=90° the orbit is edge-on
//                   (a horizontal line for flat orbits).
//
//  Step 1 — Azimuth rotation around z:
//      x' = cos(φ)·x + sin(φ)·y
//      y' = -sin(φ)·x + cos(φ)·y
//
//  Step 2 — Elevation blend:
//      screenX = x'
//      screenY = cos(θ)·y' + sin(θ)·z
//
//  Step 3 — Scale and translate to canvas:
//      canvasX = centerX + screenX × scale
//      canvasY = centerY + screenY × scale
//

import Foundation
import CoreGraphics

struct CoordinateTransformer {

    /// Canvas center point (top-left origin). The simulation origin maps here.
    let canvasCenter: CGPoint

    /// Pixels per simulation unit. Computed so the initial separation fits in
    /// 40% of the smallest canvas dimension, leaving margin for orbital excursions.
    let scale: Double

    /// Camera azimuth in radians — rotation of the view around the z-axis.
    /// Dragging left/right increments this angle.
    let azimuth: Double

    /// Camera elevation in radians — tilt above the orbital plane.
    /// At 0° the orbit is fully visible (top-down). At π/2 it is edge-on.
    /// Dragging up/down adjusts this angle, clamped to [-π/2, π/2].
    let elevation: Double

    /// The simulation-space point that maps to the canvas center.
    /// Set to the instantaneous centre of mass each frame so the view
    /// stays centred on the two-body system regardless of CoM drift.
    let centerOffset: Vector3D

    // MARK: - Initialiser

    /// Creates a transformer for the given canvas size and camera orientation.
    ///
    /// The scale factor is chosen so that a point at distance `simulationSeparation`
    /// from `centerOffset` maps to 40% of the canvas half-dimension. This keeps the
    /// initial orbit comfortably inside the canvas with margin for eccentricity.
    ///
    /// - Parameters:
    ///   - canvasSize: The current canvas size in screen points.
    ///   - simulationSeparation: The extent (from `centerOffset`) to fit in 40% of the canvas.
    ///     Defaults to `baseAU` (the 1 AU reference distance).
    ///   - azimuth: Camera azimuth in radians. Default is 0 (no horizontal rotation).
    ///   - elevation: Camera elevation in radians. Default is π/6 (30°), giving a
    ///     pleasing 3D perspective on the default flat orbit.
    ///   - centerOffset: Simulation-space point that maps to the canvas center.
    ///     Pass the instantaneous CoM to keep the view centred on the system.
    init(
        canvasSize: CGSize,
        simulationSeparation: Double = CelestialConstants.baseAU,
        azimuth: Double = 0,
        elevation: Double = .pi / 6,
        centerOffset: Vector3D = .zero
    ) {
        self.canvasCenter = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )
        self.azimuth = azimuth
        self.elevation = elevation
        self.centerOffset = centerOffset

        // Fit the given separation into 40% of the smaller canvas dimension.
        // Using the minimum of width/height ensures the orbit stays within
        // the canvas regardless of portrait/landscape orientation.
        let availableHalfWidth  = canvasSize.width  * 0.40
        let availableHalfHeight = canvasSize.height * 0.40
        let available = min(availableHalfWidth, availableHalfHeight)
        self.scale = simulationSeparation > 0 ? available / simulationSeparation : 1.0
    }

    // MARK: - Projection

    /// Projects a 3D simulation-space position to a 2D canvas point.
    ///
    /// The projection is orthographic (parallel projection — no perspective foreshortening).
    /// This is appropriate for an orbital simulation where distance to the camera does
    /// not need to distort the apparent size of objects.
    ///
    /// See the file header for the full derivation of the two-step rotation.
    func simulationToCanvas(_ v: Vector3D) -> CGPoint {
        // Shift so the centre of mass (or any chosen focus point) maps to canvas centre.
        let u = v - centerOffset

        // Step 1: Rotate by azimuth φ around the z-axis.
        let x1 =  cos(azimuth) * u.x + sin(azimuth) * u.y
        let y1 = -sin(azimuth) * u.x + cos(azimuth) * u.y

        // Step 2: Apply elevation θ.
        let screenX = x1
        let screenY = cos(elevation) * y1 + sin(elevation) * u.z

        // Step 3: Scale and translate to canvas coordinates (origin at top-left).
        return CGPoint(
            x: canvasCenter.x + screenX * scale,
            y: canvasCenter.y + screenY * scale
        )
    }

    /// Batch-converts an array of 3D simulation-space trail positions to canvas points.
    func transformTrail(_ trail: [Vector3D]) -> [CGPoint] {
        trail.map { simulationToCanvas($0) }
    }

    /// Computes the depth of a 3D point along the camera's viewing axis.
    ///
    /// Positive depth means the point is farther from the viewer (into the screen).
    /// Negative depth means it is closer. Used to sort bodies back-to-front so
    /// the nearer body is drawn on top (correct occlusion without a depth buffer).
    ///
    /// ## Derivation
    ///
    /// The camera forward direction (pointing into the screen) in simulation
    /// space is the cross product of the screenX and screenY basis vectors:
    ///
    ///     forward = (sin(φ)·sin(θ),  -cos(φ)·sin(θ),  cos(θ))
    ///
    /// Depth is the dot product of the point with this vector:
    ///
    ///     depth = v · forward
    ///           = -sin(θ)·y' + cos(θ)·z
    ///
    /// where y' = -sin(φ)·x + cos(φ)·y is the y component after azimuth rotation.
    func depthOf(_ v: Vector3D) -> Double {
        let u = v - centerOffset
        let y1 = -sin(azimuth) * u.x + cos(azimuth) * u.y
        return -sin(elevation) * y1 + cos(elevation) * u.z
    }
}
