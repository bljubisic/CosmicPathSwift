//
//  RealTimeRate.swift
//  CosmicPathSwift
//
//  How much simulated time passes per real second in the Realistic scale
//  (issue #21, PR 2). Visual keeps its relative Speed multiplier instead.
//  The strong-field setup (PR 3) has its own sub-second rates: orbits near a
//  stellar black hole take milliseconds. S2 around Sgr A* (PR 4) takes 16
//  years per orbit, so it has its own range again.
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
    case oneMinute
    case tenMinutes
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

    /// Rates offered for S2 around Sgr A*: from a slow periapsis passage
    /// (1 week) to an orbit every 1.6 s (10 years).
    static let galacticCenterChoices: [RealTimeRate] = [.oneWeek, .oneMonth, .oneYear, .tenYears]

    /// Rates offered for a planet around a stellar black hole: its orbits take
    /// from about half a minute (1,000 rₛ) to a day and a half (300,000 rₛ).
    static let blackHolePlanetChoices: [RealTimeRate] = [.oneMinute, .tenMinutes, .oneHour, .sixHours]

    /// The Rate picker's choices for `regime`.
    static func choices(for regime: RateRegime) -> [RealTimeRate] {
        switch regime {
        case .planetary: return planetaryChoices
        case .stellarBlackHole: return strongFieldChoices
        case .galacticCenter: return galacticCenterChoices
        case .blackHolePlanet: return blackHolePlanetChoices
        }
    }

    private static let microsecond: Double = 1e-6
    private static let millisecond: Double = 1e-3
    private static let minute: Double = 60
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
        case .oneMinute: return Self.minute
        case .tenMinutes: return 10 * Self.minute
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
        case .oneMinute: return "1 min"
        case .tenMinutes: return "10 min"
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

// MARK: - RateRegime

/// Which family of Realistic rates applies. Each regime keeps its own chosen rate
/// (`TimeSettings`), because their timescales differ by up to 15 orders of magnitude.
enum RateRegime: Equatable, Sendable {
    /// Planets and stars: hours to centuries.
    case planetary
    /// A probe near a stellar black hole: microseconds to tenths of a second.
    case stellarBlackHole
    /// S2 around Sagittarius A*: weeks to decades.
    case galacticCenter
    /// A rocky planet around a stellar black hole: minutes to hours.
    case blackHolePlanet
}
