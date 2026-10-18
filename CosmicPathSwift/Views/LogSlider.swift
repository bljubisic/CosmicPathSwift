//
//  LogSlider.swift
//  CosmicPathSwift
//
//  Labelled slider with a logarithmic value mapping, shared by the 2-body
//  and 3-body control panels.
//

import SwiftUI

/// A slider that maps a linear 0...1 thumb position to a logarithmic value range.
///
/// ## Why Logarithmic?
///
/// Physical parameters like mass span orders of magnitude (0.1× to 10×).
/// A linear slider would compress the useful 0.5–2.0 range into a tiny portion
/// of the track. The log mapping ensures equal thumb travel for equal multiplicative
/// changes: moving from 1× to 2× takes the same distance as 2× to 4×.
///
/// The default value (1.0) sits at the geometric center of the range when
/// `min × max = 1.0` (e.g. 0.1...10), so the thumb starts in the middle.
struct LogSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let displayText: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            Slider(value: normalizedValue, in: 0...1)
                .tint(color)
            Text(displayText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .trailing)
        }
    }

    /// Binding between the 0...1 thumb position and the logarithmic value.
    private var normalizedValue: Binding<Double> {
        let logMin = log(range.lowerBound)
        let logMax = log(range.upperBound)
        return Binding(
            get: {
                let clamped = min(max(value, range.lowerBound), range.upperBound)
                return (log(clamped) - logMin) / (logMax - logMin)
            },
            set: { normalized in
                value = exp(logMin + normalized * (logMax - logMin))
            }
        )
    }
}
