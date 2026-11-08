//
//  TimeControl.swift
//  CosmicPathSwift
//
//  Pure helpers for the Advanced sheet's time controls (issue #20):
//
//    • `FrameStepPlanner` turns the accuracy and speed multipliers into an
//      integer step count per rendered frame, carrying fractions over so slow
//      speeds are exact on average.
//    • `TrailSampler` schedules trail points (and other periodic events) by
//      simulated time rather than by step, so they look the same whatever `dt` is.
//

import Foundation

// MARK: - FrameStepPlanner

/// Decides how many integration steps to run in each rendered frame.
///
/// Exact steps per frame = baseSteps / timeStepMultiplier × timeSpeed. Halving the
/// step size doubles the step count, so on-screen speed only depends on `timeSpeed`.
struct FrameStepPlanner {
    /// Rendered frames per second of the simulation loop.
    static let framesPerSecond = 60

    /// Absorbs floating-point error so e.g. 0.5 + 0.5 counts as a whole step.
    private static let wholeStepTolerance = 1e-9

    /// Fractional step left over from previous frames, in [0, 1).
    private(set) var carry: Double = 0

    /// True when the last frame wanted more than its step cap.
    private(set) var isSpeedLimited = false

    /// Returns the step count for one frame and updates the carried fraction.
    ///
    /// - Parameter maxSteps: Cap on steps this frame. Defaults to
    ///   `TimeSettings.maxStepsPerFrame`; lowered when more than one engine runs.
    mutating func steps(
        baseSteps: Int,
        time: TimeSettings,
        maxSteps: Int = TimeSettings.maxStepsPerFrame
    ) -> Int {
        take(Self.exactSteps(baseSteps: baseSteps, time: time), maxSteps: maxSteps)
    }

    /// Step count for one frame at a real-time rate ("1 s = X", Realistic scale):
    /// exact steps = rate / fps / (dt × secondsPerTime). The fraction carries
    /// over and the cap applies exactly as in `steps(baseSteps:time:maxSteps:)`.
    ///
    /// - Parameters:
    ///   - rateSecondsPerSecond: Simulated seconds per real second.
    ///   - timeStep: Integration step in simulation time units.
    ///   - secondsPerTime: Seconds per simulation time unit.
    mutating func steps(
        rateSecondsPerSecond: Double,
        timeStep: Double,
        secondsPerTime: Double,
        maxSteps: Int = TimeSettings.maxStepsPerFrame
    ) -> Int {
        let stepSeconds = timeStep * secondsPerTime
        let exact = stepSeconds > 0 && rateSecondsPerSecond > 0
            ? rateSecondsPerSecond / Double(Self.framesPerSecond) / stepSeconds
            : 0
        return take(exact, maxSteps: maxSteps)
    }

    /// Simulated seconds per real second when every frame runs `steps` steps
    /// of `timeStep` (the rate reached when the cap limits the speed).
    static func achievedRate(steps: Int, timeStep: Double, secondsPerTime: Double) -> Double {
        Double(steps) * timeStep * secondsPerTime * Double(framesPerSecond)
    }

    /// Adds `exactSteps` to the carry and returns the whole steps, capped.
    private mutating func take(_ exactSteps: Double, maxSteps: Int) -> Int {
        let exact = exactSteps + carry
        let whole = Int((exact + Self.wholeStepTolerance).rounded(.down))

        if whole > maxSteps {
            // Don't bank the overflow: it would only replay as a burst later.
            carry = 0
            isSpeedLimited = true
            return maxSteps
        }
        carry = max(exact - Double(whole), 0)
        isSpeedLimited = false
        return whole
    }

    /// Step cap for one frame. `TimeSettings.maxStepsPerFrame` is a budget of
    /// Verlet steps (one force evaluation each), so costlier integrators and
    /// extra engines (the chaos twin) share it out. Never below 1.
    static func stepCap(integrator: IntegratorKind, engineCount: Int) -> Int {
        let cost = integrator.forceEvaluationsPerStep * max(engineCount, 1)
        return max(TimeSettings.maxStepsPerFrame / cost, 1)
    }

    /// Clears the carried fraction (a new simulation starts on a whole frame).
    mutating func reset() {
        carry = 0
        isSpeedLimited = false
    }

    /// Ideal (fractional) steps per frame. Invalid multipliers fall back to 1.
    private static func exactSteps(baseSteps: Int, time: TimeSettings) -> Double {
        let stepMultiplier = time.timeStepMultiplier > 0 ? time.timeStepMultiplier : 1
        let speed = time.timeSpeed > 0 ? time.timeSpeed : 1
        return Double(max(baseSteps, 0)) / stepMultiplier * speed
    }
}

// MARK: - TrailSampler

/// Schedules samples at a fixed interval of simulated time, independent of `dt`.
///
/// Each call reports where in the step the due samples fall, as fractions of
/// the step in (0, 1]; the caller interpolates between the step's start and end
/// state. Time since the last sample carries over between calls (rather than
/// resetting to zero), so the spacing is exactly `interval` on average.
struct TrailSampler {
    /// Relative tolerance so accumulated rounding doesn't delay a sample by a whole step.
    private static let relativeTolerance = 1e-9

    /// Simulated time between samples. Zero or less means "every step".
    let interval: Double

    /// Simulated time since the last sample, in [0, interval).
    private(set) var timeSinceSample: Double = 0

    init(interval: Double) {
        self.interval = interval
    }

    /// Advances by one step of length `dt` and returns the fraction of the step
    /// at which each due sample falls, in increasing order.
    mutating func sampleFractions(forStep dt: Double) -> [Double] {
        guard dt > 0 else { return [] }
        guard interval > 0 else { return [1] }

        let tolerance = Self.relativeTolerance * max(dt, interval)
        var fractions: [Double] = []
        var sampleTime = interval - timeSinceSample   // offset into this step
        var lastSampleTime: Double?

        while sampleTime <= dt + tolerance {
            fractions.append(min(sampleTime / dt, 1))
            lastSampleTime = sampleTime
            sampleTime += interval
        }

        if let lastSampleTime {
            timeSinceSample = max(dt - lastSampleTime, 0)
        } else {
            timeSinceSample += dt
        }
        return fractions
    }
}
