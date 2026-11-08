//
//  RealTimeRate.swift
//  CosmicPathSwift
//
//  How much simulated time passes per real second in the Realistic scale
//  (issue #21, PR 2). Visual keeps its relative Speed multiplier instead.
//

import Foundation

/// "1 s = X": simulated time per second of wall-clock time.
enum RealTimeRate: String, CaseIterable, Codable, Sendable {
    case oneHour
    case sixHours
    case oneDay
    case oneWeek
    case oneMonth
    case oneYear
    case tenYears
    /// For the Pythagorean preset, whose chaos takes about 300 years at L = 10 AU.
    case hundredYears

    private static let hour: Double = 3_600
    private static let day: Double = SIConstants.secondsPerDay
    private static let year: Double = SIConstants.julianYear

    /// Simulated seconds per real second.
    var simulatedSecondsPerSecond: Double {
        switch self {
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
