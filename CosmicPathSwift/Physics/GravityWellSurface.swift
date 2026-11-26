//
//  GravityWellSurface.swift
//  CosmicPathSwift
//
//  Depth of the gravity-well sheet (issue #38): spacetime drawn as a rubber
//  sheet pulled down under each body. Purely illustrative, like the 2D grid
//  warp: a picture of the potential, not a true embedding of spacetime.
//
//  Two profiles:
//  - `newtonian` (Visual, planetary Realistic, 3-body): softened point-mass
//    wells, weighted by log(mass) so a light body's well stays visible next
//    to a heavy one, then soft-capped with tanh so the deepest well has no
//    flat bottom.
//  - `flamm` (strong field): Flamm's paraboloid z = 2√(rₛ(r − rₛ)) around
//    the black hole, the same geometry as `SchwarzschildGridWarp`.
//
//  Depth is in simulation length units and positive downward (into the well).
//  Bodies are flattened onto the orbital plane: only x and y are used.
//

import Foundation

// MARK: - WellSource

/// One body pulling the sheet down, flattened onto the orbital plane.
struct WellSource: Equatable, Sendable {
    let x: Double
    let y: Double
    let mass: Double
}

// MARK: - GravityWellProfile

/// The shape of the wells.
enum GravityWellProfile: Equatable, Sendable {
    /// Softened, log-weighted, soft-capped Newtonian wells.
    /// - wellWidth: softening ε of each well's 1/√(r² + ε²) profile.
    /// - depthScale: depth of a weight-1 well's bottom before the cap.
    /// - cap: depth the tanh soft cap approaches but never reaches.
    case newtonian(wellWidth: Double, depthScale: Double, cap: Double)
    /// Flamm's paraboloid around the first source, flat from `rimRadius` out.
    case flamm(schwarzschildRadius: Double, rimRadius: Double)
}

// MARK: - GravityWellSurface

/// Depth of the sheet at any point of the orbital plane.
struct GravityWellSurface: Equatable, Sendable {
    let sources: [WellSource]
    let profile: GravityWellProfile
    /// Depth exaggeration (the Grid Warp setting): 0 flat, 1 default.
    let strength: Double

    /// Log weight of each source, index-aligned with `sources`.
    private let weights: [Double]

    /// Lightest weight a body with mass gets, so tiny planets still dent the sheet.
    static let minimumWeight = 0.15
    /// Well width as a fraction of the view extent (the softening is usually far smaller).
    static let wellWidthFraction = 0.12
    /// Depth of a weight-1 well before the cap, as a fraction of the view extent.
    static let depthFraction = 0.5
    /// Soft-cap depth as a fraction of the view extent.
    static let capFraction = 0.7
    /// Radius where the Flamm funnel meets the flat sheet, as a fraction of the view extent.
    static let rimFraction = 1.6

    init(sources: [WellSource], profile: GravityWellProfile, strength: Double) {
        self.sources = sources
        self.profile = profile
        self.strength = strength
        self.weights = Self.logWeights(masses: sources.map(\.mass))
    }

    // MARK: Depth

    /// Depth of the sheet at (x, y), positive downward.
    func depth(x: Double, y: Double) -> Double {
        guard strength > 0, !sources.isEmpty else { return 0 }
        switch profile {
        case let .newtonian(wellWidth, depthScale, cap):
            return newtonianDepth(x: x, y: y, wellWidth: wellWidth, depthScale: depthScale, cap: cap)
        case let .flamm(rs, rim):
            let hole = sources[0]
            return strength * Self.flammDepth(r: hypot(x - hole.x, y - hole.y), rs: rs, rim: rim)
        }
    }

    /// Depth at the bottom of the Flamm throat; nil for Newtonian wells.
    var horizonDepth: Double? {
        guard case let .flamm(rs, rim) = profile else { return nil }
        return strength * Self.flammDepth(r: 0, rs: rs, rim: rim)
    }

    /// Log weight of source `index`: 1 for the heaviest, at least `minimumWeight`
    /// for any body with mass, 0 for a massless one.
    func weight(of index: Int) -> Double {
        weights[index]
    }

    /// Σ wᵢ · ε/√(r² + ε²), scaled, then soft-capped: cap · tanh(d / cap).
    private func newtonianDepth(x: Double, y: Double, wellWidth: Double, depthScale: Double, cap: Double) -> Double {
        guard wellWidth > 0, cap > 0 else { return 0 }
        var raw = 0.0
        for (source, weight) in zip(sources, weights) where weight > 0 {
            let r = hypot(x - source.x, y - source.y)
            raw += weight * wellWidth / (r * r + wellWidth * wellWidth).squareRoot()
        }
        return cap * tanh(strength * depthScale * raw / cap)
    }

    /// z(rim) − z(r) with z = 2√(rₛ(r − rₛ)); deepest inside the horizon, 0 past the rim.
    private static func flammDepth(r: Double, rs: Double, rim: Double) -> Double {
        guard rs > 0, rim > rs else { return 0 }
        let height = { (radius: Double) in 2 * (rs * (radius - rs)).squareRoot() }
        let clamped = min(max(r, rs), rim)
        return height(rim) - height(clamped)
    }

    /// log1p(m / m_min) / log1p(m_max / m_min), floored at `minimumWeight`.
    private static func logWeights(masses: [Double]) -> [Double] {
        let positive = masses.filter { $0 > 0 }
        guard let lightest = positive.min(), let heaviest = positive.max() else {
            return masses.map { _ in 0 }
        }
        guard heaviest > lightest else { return masses.map { $0 > 0 ? 1 : 0 } }
        let range = log1p(heaviest / lightest)
        return masses.map { mass in
            guard mass > 0 else { return 0 }
            return max(minimumWeight, log1p(mass / lightest) / range)
        }
    }
}

// MARK: - Factory

extension GravityWellSurface {

    /// The sheet for `bodies` under `config`, sized to the current view extent.
    ///
    /// Strong field (Realistic 2-body Black Hole Mode) gets Flamm's paraboloid
    /// around body 0; everything else gets Newtonian wells whose width is at
    /// least `wellWidthFraction` of the view, so they read as funnels, not needles.
    static func make(
        bodies: [CelestialBody], config: SimulationConfig, viewExtent: Double, strength: Double
    ) -> GravityWellSurface {
        let sources = bodies.map { WellSource(x: $0.position.x, y: $0.position.y, mass: $0.mass) }
        return GravityWellSurface(
            sources: sources,
            profile: profile(bodies: bodies, config: config, viewExtent: viewExtent),
            strength: strength
        )
    }

    private static func profile(
        bodies: [CelestialBody], config: SimulationConfig, viewExtent: Double
    ) -> GravityWellProfile {
        if config.isStrongField, let hole = bodies.first {
            let rs = config.scale.constants.schwarzschildRadius(mass: hole.mass)
            return .flamm(schwarzschildRadius: rs, rimRadius: max(rimFraction * viewExtent, 2 * rs))
        }
        let softening = InitialConditions.softening(config: config)
        return .newtonian(
            wellWidth: max(softening, wellWidthFraction * viewExtent),
            depthScale: depthFraction * viewExtent,
            cap: capFraction * viewExtent
        )
    }
}
