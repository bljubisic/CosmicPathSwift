//
//  SeededGenerator.swift
//  CosmicPathSwift
//
//  A small seedable random number generator. Swift's built-in
//  `SystemRandomNumberGenerator` can't be seeded, so reproducible layouts
//  (the Custom preset's Random layout) need their own generator.
//

import Foundation

/// SplitMix64 (Steele, Lea & Flood, 2014): fast, well-distributed, and fully
/// determined by its 64-bit seed. Not suitable for cryptography.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1) from the top 53 bits of the next value.
    ///
    /// Used instead of `Double.random(in:using:)`, whose algorithm the standard
    /// library doesn't promise to keep, so a seed gives the same layout in every
    /// app version.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }
}
