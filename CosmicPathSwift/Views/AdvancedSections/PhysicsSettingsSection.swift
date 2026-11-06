//
//  PhysicsSettingsSection.swift
//  CosmicPathSwift
//
//  "Physics" section of the Advanced sheet (issue #20, PR 5): integrator,
//  softening length, and the 3-body collision mode. These are baked into the
//  engine when it is created, so changing one restarts the simulation and
//  they can only be edited while paused.
//

import SwiftUI

struct PhysicsSettingsSection: View {
    @Bindable var viewModel: SimulationViewModel

    private var engine: Binding<EngineSettings> { $viewModel.config.advanced.engine }

    var body: some View {
        Section {
            integratorPicker
            softeningPicker
            if viewModel.isThreeBodyMode {
                collisionPicker
            }
        } header: {
            Text("Physics")
        } footer: {
            Text("Changing these restarts the simulation, so they can only be edited while paused.")
        }
        .disabled(viewModel.isRunning)
    }

    private var integratorPicker: some View {
        CaptionedRow(
            "Integrator",
            caption: "Verlet is 2nd-order and symplectic: energy error stays bounded. RK4 is 4th-order but energy slowly drifts. Yoshida 4 is 4th-order and symplectic, at 3× the cost. With GR on, Verlet and Yoshida are only 1st-order in the small GR term. Compare them with ΔE/E in 3-Body mode."
        ) {
            Picker("Integrator", selection: engine.integrator) {
                ForEach(IntegratorKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var softeningPicker: some View {
        CaptionedRow(
            "Softening",
            caption: "Smallest distance used in the force law, so close passes stay finite. Smaller is more realistic but needs finer accuracy. Also sets the 3-body merge distance and the closest starting distance."
        ) {
            Picker("Softening", selection: engine.softening) {
                ForEach(EngineSettings.softeningChoices, id: \.self) { value in
                    Text(String(format: "%g px", value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var collisionPicker: some View {
        CaptionedRow(
            "Collisions",
            caption: "Merge combines bodies that touch, conserving momentum. Pass Through lets them fly through each other."
        ) {
            Picker("Collisions", selection: engine.collisionMode) {
                ForEach(CollisionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
