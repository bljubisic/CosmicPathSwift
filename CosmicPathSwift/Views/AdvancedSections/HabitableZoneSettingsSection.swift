//
//  HabitableZoneSettingsSection.swift
//  CosmicPathSwift
//
//  "Habitable Zone" section of the Advanced sheet (issue #20, PR 6): which
//  flux limits define the zone's edges, and the planet's albedo. Rendering
//  only, so the changes apply immediately, even while running (2-body only).
//

import SwiftUI

struct HabitableZoneSettingsSection: View {
    @Bindable var viewModel: SimulationViewModel

    private var settings: Binding<HabitableZoneSettings> { $viewModel.config.advanced.habitableZone }

    var body: some View {
        Section {
            limitsPicker
            albedoSlider
        } header: {
            Text("Habitable Zone")
        } footer: {
            Text("Applies immediately.")
        }
    }

    private var limitsPicker: some View {
        let limits = settings.limits.wrappedValue
        return CaptionedRow(
            "Limits",
            caption: "\(limits.edgeDescription): starlight \(String(format: "%g", limits.innerFlux))× to \(String(format: "%g", limits.outerFlux))× what Earth receives."
        ) {
            Picker("Limits", selection: settings.limits) {
                ForEach(HabitableZoneLimits.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var albedoSlider: some View {
        CaptionedRow(
            String(format: "Albedo: %.2f", settings.bondAlbedo.wrappedValue),
            caption: "Fraction of starlight the planet reflects. Higher is cooler."
        ) {
            Slider(
                value: settings.bondAlbedo,
                in: HabitableZoneSettings.albedoRange,
                step: HabitableZoneSettings.albedoStep
            )
        }
    }
}
