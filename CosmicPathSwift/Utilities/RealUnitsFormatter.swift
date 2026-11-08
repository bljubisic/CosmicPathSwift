//
//  RealUnitsFormatter.swift
//  CosmicPathSwift
//
//  Display strings for the Realistic scale (issue #21, PR 2). Pure functions:
//  simulation values go in with the scale's `UnitSystem`, text comes out.
//
//  Real GR effects are tiny (τ/t = 1 − 10⁻⁸, 0.1″ of precession per orbit),
//  so they are shown as deviations and in scientific notation rather than as
//  the fixed decimals the Visual scale uses.
//

import Foundation

enum RealUnitsFormatter {

    // MARK: - Thresholds

    /// Lengths below this many AU are shown in kilometres.
    static let kilometreThresholdAU: Double = 0.01
    /// Precession below this many degrees per orbit can't be seen in the trail.
    static let visiblePrecessionDegreesPerOrbit: Double = 0.1
    /// Rings smaller than this many points on screen can't be seen.
    static let visibleScreenLengthPoints: Double = 0.5

    private static let secondsPerMinute: Double = 60
    private static let secondsPerHour: Double = 3_600
    private static let arcsecondsPerDegree: Double = 3_600
    /// Values in [0.01, 1000) are shown as plain decimals by `scientific`.
    private static let plainRange: Range<Double> = 0.01..<1_000

    // MARK: - Time, length, speed

    /// Simulated time as "42 s", "3.5 min", "6.0 h", "27.3 days", "1.25 years" or "300 years".
    static func duration(_ time: Double, units: UnitSystem) -> String {
        let seconds = abs(time * units.secondsPerTime)
        let day = SIConstants.secondsPerDay
        let year = SIConstants.julianYear
        switch seconds {
        case ..<secondsPerMinute: return String(format: "%.0f s", seconds)
        case ..<secondsPerHour: return String(format: "%.1f min", seconds / secondsPerMinute)
        case ..<day: return String(format: "%.1f h", seconds / secondsPerHour)
        case ..<year: return String(format: "%.1f days", seconds / day)
        case ..<(100 * year): return String(format: "%.2f years", seconds / year)
        default: return String(format: "%.0f years", seconds / year)
        }
    }

    /// Simulation length as "0.387 AU", or "384400 km" / "2.95 km" below 0.01 AU.
    static func length(_ length: Double, units: UnitSystem) -> String {
        let meters = length * units.metersPerLength
        let au = meters / SIConstants.astronomicalUnit
        guard au < kilometreThresholdAU else { return String(format: "%.3f AU", au) }
        return kilometres(meters)
    }

    /// Simulation speed in km/s, e.g. "29.8 km/s".
    static func speed(_ speed: Double, units: UnitSystem) -> String {
        let metersPerSecond = speed * units.metersPerLength / units.secondsPerTime
        return String(format: "%.1f km/s", metersPerSecond / SIConstants.kilometer)
    }

    /// Schwarzschild radius in km, e.g. "2.95 km".
    static func schwarzschildRadius(_ rs: Double, units: UnitSystem) -> String {
        kilometres(rs * units.metersPerLength)
    }

    private static func kilometres(_ meters: Double) -> String {
        let km = meters / SIConstants.kilometer
        return km >= 100 ? String(format: "%.0f km", km) : String(format: "%.3g km", km)
    }

    // MARK: - Precession

    /// Degrees as arcseconds, e.g. "0.104″".
    static func arcseconds(degrees: Double) -> String {
        String(format: "%.3g″", degrees * arcsecondsPerDegree)
    }

    /// Precession per Julian century in arcseconds, from the advance per orbit
    /// and the orbital period (simulation time). Nil without a valid period.
    static func arcsecondsPerCentury(degreesPerOrbit: Double, period: Double, units: UnitSystem) -> Double? {
        let periodSeconds = period * units.secondsPerTime
        guard periodSeconds > 0, periodSeconds.isFinite else { return nil }
        let centurySeconds = SIConstants.daysPerJulianCentury * SIConstants.secondsPerDay
        return degreesPerOrbit * arcsecondsPerDegree * centurySeconds / periodSeconds
    }

    /// "43.0″/century", or "—" without a valid period.
    static func perCentury(degreesPerOrbit: Double, period: Double?, units: UnitSystem) -> String {
        guard let period,
              let value = arcsecondsPerCentury(degreesPerOrbit: degreesPerOrbit, period: period, units: units) else {
            return "—"
        }
        return String(format: "%.1f″/century", value)
    }

    // MARK: - Mass

    /// Bodies lighter than this (about one Jupiter mass) are labelled in Earth masses.
    static let earthMassLabelThreshold = 1e-3

    /// Compact mass label in real units: stars in solar masses ("3 M☉"),
    /// planets and moons in Earth masses ("1 M⊕", "0.0123 M⊕"), so a legend
    /// never shows something like "3e-06".
    static func mass(_ mass: Double, scale: ScaleProfile) -> String {
        let solarMasses = mass / scale.solarMass
        if solarMasses >= earthMassLabelThreshold {
            return scientific(solarMasses) + " M\u{2609}"
        }
        return scientific(mass / scale.earthMass) + " M\u{2295}"
    }

    // MARK: - Small numbers

    /// "9.9×10⁻⁹" for very small or large magnitudes, plain "%.3g" in [0.01, 1000).
    static func scientific(_ value: Double) -> String {
        guard value != 0, value.isFinite else { return value.isFinite ? "0" : "—" }
        let sign = value < 0 ? "−" : ""
        let magnitude = abs(value)
        if plainRange.contains(magnitude) { return sign + String(format: "%.3g", magnitude) }
        var exponent = Int(floor(log10(magnitude)))
        var mantissa = magnitude / pow(10, Double(exponent))
        if mantissa >= 9.95 {   // "%.1f" would print 10.0
            mantissa /= 10
            exponent += 1
        }
        return sign + String(format: "%.1f", mantissa) + "×10" + exponent.superscript
    }

    /// A value close to 1 as its deviation, e.g. 0.9999999901 → "1 − 9.9×10⁻⁹".
    static func deviation(fromOne value: Double) -> String {
        let difference = 1 - value
        guard difference != 0 else { return "1" }
        let sign = difference > 0 ? "−" : "+"
        return "1 \(sign) " + scientific(abs(difference))
    }

    /// 1 − √(1 − x) without cancellation, for the gravitational dilation with x = rₛ/r.
    static func oneMinusSqrtOneMinus(_ x: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        return clamped / (1 + sqrt(1 - clamped))
    }

    /// γ − 1 for speed β = v/c without cancellation: β² / (√(1 − β²)(1 + √(1 − β²))).
    static func gammaMinusOne(beta: Double) -> Double {
        let betaSquared = min(beta * beta, 0.99)
        let root = sqrt(1 - betaSquared)
        return betaSquared / (root * (1 + root))
    }

    // MARK: - Visibility

    /// True when the precession per orbit is too small to see in the trail.
    static func isTooSmallToSee(precessionDegreesPerOrbit: Double) -> Bool {
        abs(precessionDegreesPerOrbit) < visiblePrecessionDegreesPerOrbit
    }

    /// True when a length drawn on screen is smaller than half a point.
    static func isTooSmallToSee(screenLengthPoints: Double) -> Bool {
        screenLengthPoints < visibleScreenLengthPoints
    }

    // MARK: - Magnification

    /// "1.7 million×", "210 thousand×" or "42×".
    static func magnification(_ factor: Double) -> String {
        switch factor {
        case 1e9...: return String(format: "%.1f billion×", factor / 1e9)
        case 1e6...: return String(format: "%.1f million×", factor / 1e6)
        case 1e3...: return String(format: "%.0f thousand×", factor / 1e3)
        default: return String(format: "%.0f×", factor)
        }
    }
}
