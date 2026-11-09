//
//  MetricsText.swift
//  CosmicPathSwift
//
//  Value strings for `MetricsPanelView`. Visual keeps its original fixed
//  decimals; Realistic (issue #21, PR 2) shows real units and the tiny GR
//  effects as deviations in scientific notation. S2 around Sgr A* (issue #28)
//  adds arcminutes and millions of km.
//

import Foundation

/// Display strings for one frame of metrics.
struct MetricsText {
    let config: SimulationConfig

    private var units: UnitSystem { config.scale.units }
    private var isRealistic: Bool { config.isRealistic }

    // MARK: - 2-Body

    /// τ/t for a stationary clock at the planet's distance. Visual shows
    /// "τ/t = 0.983"; Realistic puts "τ/t" in the label so the longer
    /// deviations ("1 − 3.5×10⁻⁴") fit.
    func timeDilation(_ metrics: RelativisticMetrics) -> String {
        guard isRealistic else { return String(format: "\u{03C4}/t = %.3f", metrics.timeDilationFactor) }
        let separation = max(metrics.separation, .leastNonzeroMagnitude)
        let deficit = RealUnitsFormatter.oneMinusSqrtOneMinus(metrics.schwarzschildRadius / separation)
        // Near a black hole the dilation is large enough for plain decimals.
        if deficit >= Self.plainDilationDeficit {
            return String(format: "%.3f", 1 - deficit)
        }
        return RealUnitsFormatter.deviation(fromOne: 1 - deficit)
    }

    /// Label under the time dilation: names τ/t in Realistic, whose value omits it.
    var timeDilationLabel: String {
        isRealistic ? "Time Dilation \u{03C4}/t" : "Time Dilation"
    }

    /// Accumulated perihelion advance: degrees in Visual; in Realistic,
    /// arcseconds below a minute of arc (planets), arcminutes up to a degree
    /// (S2: 12.2′ per orbit), then degrees (near a stellar black hole).
    func precession(_ metrics: RelativisticMetrics) -> String {
        let angle = metrics.precessionAngle
        guard isRealistic, abs(angle) < Self.degreeDisplayThreshold else {
            return String(format: "%.2f\u{00B0}", angle)
        }
        guard abs(angle) < Self.arcminuteDisplayThreshold else {
            return RealUnitsFormatter.arcminutes(degrees: angle)
        }
        return RealUnitsFormatter.arcseconds(degrees: angle)
    }

    /// Schwarzschild radius slot: simulation units in Visual, km in Realistic.
    func schwarzschildRadius(_ metrics: RelativisticMetrics) -> (label: String, value: String) {
        guard isRealistic else {
            return ("r\u{209B} (\(units.lengthSymbol))", String(format: "%.1f", metrics.schwarzschildRadius))
        }
        return ("r\u{209B}", RealUnitsFormatter.schwarzschildRadius(metrics.schwarzschildRadius, units: units))
    }

    /// Precession at or above this many degrees is shown in degrees in Realistic.
    static let degreeDisplayThreshold: Double = 1
    /// Precession at or above this many degrees (one arcminute) is shown in
    /// arcminutes in Realistic, so arcseconds never reach scientific notation.
    static let arcminuteDisplayThreshold: Double = 1.0 / 60
    /// τ/t deficits at or above this are shown as plain decimals ("0.935").
    static let plainDilationDeficit: Double = 1e-3

    /// "Precession", plus "(too small to see)" in Realistic when it is.
    func precessionLabel(_ metrics: RelativisticMetrics) -> String {
        guard isRealistic, metrics.orbitsCompleted > 0 else { return "Precession" }
        let perOrbit = metrics.precessionAngle / Double(metrics.orbitsCompleted)
        return RealUnitsFormatter.isTooSmallToSee(precessionDegreesPerOrbit: perOrbit)
            ? "Precession (too small to see)" : "Precession"
    }

    func velocityFraction(_ beta: Double) -> String {
        isRealistic ? RealUnitsFormatter.scientific(beta) : String(format: "%.3f", beta)
    }

    /// Lorentz factor: γ in Visual, γ − 1 in Realistic.
    func lorentz(_ metrics: RelativisticMetrics) -> (label: String, value: String) {
        guard isRealistic else { return ("Lorentz \u{03B3}", String(format: "%.4f", metrics.lorentzGamma)) }
        let excess = RealUnitsFormatter.gammaMinusOne(beta: metrics.velocityFractionOfC)
        return ("\u{03B3} \u{2212} 1", RealUnitsFormatter.scientific(excess))
    }

    /// First 2-body slot: the orbit count (Visual) or the elapsed time (Realistic).
    func orbits(_ metrics: RelativisticMetrics) -> (label: String, value: String) {
        let count = String(format: "%d", metrics.orbitsCompleted)
        guard isRealistic else { return ("Orbits", count) }
        return ("\(count) orbits", RealUnitsFormatter.duration(metrics.elapsedTime, units: units))
    }

    // MARK: - 3-Body

    func elapsedTime(_ metrics: SystemMetrics) -> String {
        isRealistic
            ? RealUnitsFormatter.duration(metrics.elapsedTime, units: units)
            : String(format: "%.0f", metrics.elapsedTime)
    }

    func closestApproach(_ metrics: SystemMetrics) -> String {
        guard metrics.closestApproach.isFinite else { return "—" }
        return isRealistic
            ? RealUnitsFormatter.length(metrics.closestApproach, units: units)
            : String(format: "%.1f", metrics.closestApproach)
    }
}
