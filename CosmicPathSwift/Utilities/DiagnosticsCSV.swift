//
//  DiagnosticsCSV.swift
//  CosmicPathSwift
//
//  CSV export of the recorded run (issue #20, PR 6). `#` comment lines
//  describe the configuration, then one row per body per sample. All values
//  are in the scale's simulation units (Visual: G = 500, c = 200, 1 AU = 150 px;
//  Realistic: AU, M☉, days).
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsCSV {

    /// Column header row.
    static let columnHeader = "time,body,mass,x,y,z,vx,vy,vz,dE_over_E,dL_over_L"

    /// Locale-independent formatting, so the decimal point is always ".".
    private static let locale = Locale(identifier: "en_US_POSIX")

    /// Builds the whole file.
    static func make(samples: [DiagnosticsSample], config: SimulationConfig) -> String {
        var lines = header(config: config)
        lines.append(columnHeader)
        for sample in samples {
            for body in sample.bodies {
                lines.append(row(sample: sample, body: body))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `#` comment lines describing the run's configuration.
    static func header(config: SimulationConfig) -> [String] {
        let engine = config.advanced.engine
        var fields: [(String, String)] = [("mode", config.mode.rawValue)]
        switch config.mode {
        case .twoBody:
            fields += [
                ("mass1_solar", number(config.mass1Multiplier)),
                ("mass2_earth", number(config.mass2Multiplier)),
                ("black_hole_mode", String(config.isBlackHoleMode)),
                ("separation_AU", number(config.separationAU)),
                ("eccentricity", number(config.orbitEccentricity)),
                ("inclination_deg", number(config.inclinationDeg))
            ]
        case .threeBody:
            fields += [("preset", config.threeBodyPreset.rawValue)]
        }
        let scale = config.scale
        fields += [
            ("scale", config.advanced.scale.rawValue),
            // The scenario's step in this scale's time unit (Visual: exactly `timeStep`).
            ("time_step", number(config.timeStep * ScenarioTiming.timeRatio(config: config))),
            ("dt_multiplier", number(config.advanced.time.timeStepMultiplier)),
            ("integrator", engine.integrator.rawValue),
            ("softening_\(scale.units.lengthSymbol)", number(reportedSoftening(config: config))),
            ("collision_mode", engine.collisionMode.rawValue)
        ]
        return ["# CosmicPath diagnostics", "# units: \(config.scale.unitsDescription)"]
            + fields.map { "# \($0.0): \($0.1)" }
    }

    /// The softening as set in Visual (the picker's value) or the scale's fixed length.
    private static func reportedSoftening(config: SimulationConfig) -> Double {
        switch config.scale.softeningRule {
        case .userChoice: return config.advanced.engine.softening
        case .fixed(let length): return length
        }
    }

    private static func row(sample: DiagnosticsSample, body: BodySnapshot) -> String {
        let values = [
            number(sample.time), String(body.id), number(body.mass),
            number(body.position.x), number(body.position.y), number(body.position.z),
            number(body.velocity.x), number(body.velocity.y), number(body.velocity.z),
            number(sample.energyDrift), number(sample.angularMomentumDrift)
        ]
        return values.joined(separator: ",")
    }

    /// Ten significant digits, POSIX decimal point.
    private static func number(_ value: Double) -> String {
        String(format: "%.10g", locale: locale, value)
    }
}

// MARK: - Transferable

/// The recorded run, handed to `ShareLink`. The CSV is only built when the
/// user actually shares, not every time the view re-renders.
struct DiagnosticsExport: Transferable {
    let samples: [DiagnosticsSample]
    let config: SimulationConfig

    var fileName: String {
        "cosmicpath-\(config.mode.rawValue).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(DiagnosticsCSV.make(samples: export.samples, config: export.config).utf8)
        }
        .suggestedFileName { $0.fileName }
    }
}
