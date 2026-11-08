//
//  RealTimeRate.swift
//  CosmicPathSwift
//
//  How much simulated time passes per real second in the Realistic scale
//  (issue #21, PR 2). Visual keeps its relative Speed multiplier instead.
//  The strong-field setup (PR 3) has its own sub-second rates: orbits near a
//  stellar black hole take milliseconds.
//

import Foundation

/// "1 s = X": simulated time per second of wall-clock time.
enum RealTimeRate: String, CaseIterable, Codable, Sendable {
    case oneMicrosecond
    case tenMicroseconds
    case hundredMicroseconds
    case oneMillisecond
    case tenMilliseconds
    case hundredMilliseconds
    case oneHour
    case sixHours
    case oneDay
    case oneWeek
    case oneMonth
    case oneYear
    case tenYears
    /// For the Pythagorean preset, whose chaos takes about 300 years at L = 10 AU.
    case hundredYears

    /// Rates offered for planetary scenarios.
    static let planetaryChoices: [RealTimeRate] = [
        .oneHour, .sixHours, .oneDay, .oneWeek, .oneMonth, .oneYear, .tenYears, .hundredYears
    ]

    /// Rates offered near a stellar black hole.
    static let strongFieldChoices: [RealTimeRate] = [
        .oneMicrosecond, .tenMicroseconds, .hundredMicroseconds,
        .oneMillisecond, .tenMilliseconds, .hundredMilliseconds
    ]

    /// The Rate picker's choices for the active regime.
    static func choices(strongField: Bool) -> [RealTimeRate] {
        strongField ? strongFieldChoices : planetaryChoices
    }

    private static let microsecond: Double = 1e-6
    private static let millisecond: Double = 1e-3
    private static let hour: Double = 3_600
    private static let day: Double = SIConstants.secondsPerDay
    private static let year: Double = SIConstants.julianYear

    /// Simulated seconds per real second.
    var simulatedSecondsPerSecond: Double {
        switch self {
        case .oneMicrosecond: return Self.microsecond
        case .tenMicroseconds: return 10 * Self.microsecond
        case .hundredMicroseconds: return 100 * Self.microsecond
        case .oneMillisecond: return Self.millisecond
        case .tenMilliseconds: return 10 * Self.millisecond
        case .hundredMilliseconds: return 100 * Self.millisecond
        case .oneHour: return Self.hour
        case .sixHours: return 6 * Self.hour
        case .oneDay: return Self.day
        case .oneWeek: return 7 * Self.day
        case .oneMonth: return Self.year / 12
        case .oneYear: return Self.year
        case .tenYears: return 10 * Self.year
        case .hundredYears: return 100 * Self.year
        }
    }

    /// The simulated span alone, e.g. "1 month".
    var spanName: String {
        switch self {
        case .oneMicrosecond: return "1 µs"
        case .tenMicroseconds: return "10 µs"
        case .hundredMicroseconds: return "100 µs"
        case .oneMillisecond: return "1 ms"
        case .tenMilliseconds: return "10 ms"
        case .hundredMilliseconds: return "100 ms"
        case .oneHour: return "1 h"
        case .sixHours: return "6 h"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .oneMonth: return "1 month"
        case .oneYear: return "1 year"
        case .tenYears: return "10 years"
        case .hundredYears: return "100 years"
        }
    }

    /// Picker and badge label, e.g. "1 s = 1 month".
    var label: String { "1 s = \(spanName)" }
}
