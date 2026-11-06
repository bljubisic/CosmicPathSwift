//
//  ScreenRecorder.swift
//  CosmicPathSwift
//
//  ReplayKit screen recording of the simulation, split out of
//  `SimulationViewModel`. Owns the recording state and the temporary `.mp4`
//  file handed to the share sheet.
//

import Foundation
import ReplayKit

@Observable
@MainActor
final class ScreenRecorder {

    /// True while a ReplayKit screen recording is in progress.
    private(set) var isRecording: Bool = false

    /// The finished recording awaiting share/save, set by `stop()`.
    ///
    /// `ContentView` binds its share sheet to this via `.sheet(item:)`: the sheet
    /// appears when it becomes non-nil, and SwiftUI sets it back to nil on dismiss.
    /// The recorder owns the temp file — whenever this value is cleared or
    /// replaced, the previous recording's file is deleted.
    var pendingRecording: RecordingItem? {
        didSet {
            if let old = oldValue, old != pendingRecording {
                try? FileManager.default.removeItem(at: old.url)
            }
        }
    }

    /// Starts a ReplayKit screen recording.
    ///
    /// Has no effect if the device does not support recording (`isAvailable`),
    /// or if a recording is already in progress. `isRecording` is set to `true`
    /// only after ReplayKit confirms the recording has started successfully.
    func start() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !isRecording else { return }
        recorder.startRecording { [weak self] error in
            Task { @MainActor [weak self] in
                if error == nil {
                    self?.isRecording = true
                }
            }
        }
    }

    /// Stops the current recording and writes the clip to a temporary `.mp4` file.
    ///
    /// On success, sets `pendingRecording`, which presents the share/save sheet.
    /// Has no effect if no recording is in progress.
    func stop() {
        guard isRecording else { return }
        // Uniquely-named temp file so it persists until the share sheet is dismissed.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit_\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mp4")
        RPScreenRecorder.shared().stopRecording(withOutput: tempURL) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.isRecording = false
                if error == nil {
                    self?.pendingRecording = RecordingItem(url: tempURL)
                }
            }
        }
    }

    /// Silently stops any in-progress recording and deletes any unshared clip,
    /// without presenting a share sheet (used by Reset).
    func discard() {
        if isRecording {
            RPScreenRecorder.shared().stopRecording { _, _ in }
            isRecording = false
        }
        // Clearing deletes the temp file (see `pendingRecording.didSet`).
        pendingRecording = nil
    }
}
