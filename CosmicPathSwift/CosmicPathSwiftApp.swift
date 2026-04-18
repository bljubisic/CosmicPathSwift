//
//  CosmicPathSwiftApp.swift
//  CosmicPathSwift
//
//  Created by Bratislav Ljubisic Home  on 1/12/25.
//

import SwiftUI

/// App entry point. Launches a single window containing the `ContentView`,
/// which manages the full simulation UI (canvas, metrics, and controls).
@main
struct CosmicPathSwiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
