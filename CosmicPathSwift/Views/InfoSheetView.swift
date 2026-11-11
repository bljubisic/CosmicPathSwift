//
//  InfoSheetView.swift
//  CosmicPathSwift
//
//  "What am I looking at?" (issue #34): renders `InfoContent` for the current
//  scene. Opened from the ⓘ button next to the other controls. The content is
//  rebuilt from the view model on every update, so the numbers stay in step
//  with the metrics panel while the simulation runs.
//

import SwiftUI

struct InfoSheetView: View {
    let viewModel: SimulationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = InfoContent.make(from: viewModel.infoSnapshot)
        NavigationStack {
            List {
                ForEach(content.sections) { section in
                    Section(section.title) {
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(section.facts, id: \.label) { fact in
                            LabeledContent(fact.label) {
                                Text(fact.value)
                                    .font(.callout.monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        ForEach(section.terms, id: \.term) { term in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(term.term).font(.callout.bold())
                                Text(term.definition)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .navigationTitle("What Am I Looking At?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Medium detent leaves the scene visible while reading about it.
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

#Preview {
    InfoSheetView(viewModel: SimulationViewModel())
}
