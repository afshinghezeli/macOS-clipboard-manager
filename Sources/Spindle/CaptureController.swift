import Foundation
import SpindleCore
import SpindleStorage
import SpindleSystem
import os

/// Connects the pasteboard monitor to storage: decides what to keep and hands it to the ingestor.
@MainActor
final class CaptureController {
    private let logger = Logger(subsystem: Diagnostics.subsystem, category: "Capture")
    private let ingestor: Ingestor
    private let history: HistoryStore
    private let filter = CaptureFilter()
    private var pause = CapturePause()
    private var monitor: ClipboardMonitor?

    /// `nil` until the first count has loaded. Kept up to date from the ingestor's change stream, so
    /// showing it never touches the database on the main thread.
    private(set) var itemCount: Int?

    /// Called for every item stored or moved to the top, for example to update the open panel.
    var onChange: (@MainActor (HistoryChange) -> Void)?

    init(ingestor: Ingestor, history: HistoryStore) {
        self.ingestor = ingestor
        self.history = history
    }

    var isPaused: Bool { pause.isPaused(at: .now) }

    func start(gateway: PasteboardGateway) {
        let monitor = ClipboardMonitor(gateway: gateway) { [weak self] read in self?.handle(read) }
        self.monitor = monitor
        monitor.start()

        refreshItemCount()
        Task { [ingestor, weak self] in
            for await change in ingestor.changes {
                if case .inserted = change, let count = self?.itemCount { self?.itemCount = count + 1 }
                self?.onChange?(change)
            }
        }
    }

    /// Reloads the count from the database, after something other than capture changed it.
    func refreshItemCount() {
        Task { [history, weak self] in
            let count = try? await history.itemCount()
            self?.itemCount = count
        }
    }

    func togglePause() {
        if isPaused {
            pause.resume()
            logger.notice("Capture resumed")
        } else {
            pause.pause(until: nil)
            logger.notice("Capture paused")
        }
    }

    private func handle(_ read: PasteboardRead) {
        switch read {
        case .copy(let copy):
            if let reason = pause.admit(at: copy.capturedAt) ?? filter.skipReason(for: copy) {
                logger.debug("Skipped a copy: \(String(describing: reason), privacy: .public)")
                return
            }
            // Detached: a write must finish even if whatever started it goes away (GRDB cancels
            // writes whose task is cancelled).
            Task.detached(priority: .utility) { [ingestor, logger] in
                do {
                    let outcome = try await ingestor.ingest(copy)
                    logger.debug("Ingested: \(String(describing: outcome), privacy: .public)")
                } catch {
                    logger.error("Storing a copy failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .marked:
            logger.debug("Skipped a copy marked private by its source")
        case .restricted(let access):
            // M4.6 turns this into a banner with a link to System Settings.
            logger.notice("macOS restricts clipboard access: \(String(describing: access), privacy: .public)")
        case .ownWrite, .nothingToKeep, .changedDuringRead:
            break
        }
    }
}
