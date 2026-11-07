//
//  CaptionedRow.swift
//  CosmicPathSwift
//
//  Row layout shared by the Advanced sheet's sections: a title, a short
//  explanatory caption, then the control.
//

import SwiftUI

/// A titled row with a caption, followed by its control.
struct CaptionedRow<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    init(_ title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}
