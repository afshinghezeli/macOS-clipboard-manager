import AppKit
import SpindleCore
import SpindleStorage
import SpindleSystem
import SpindleUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Diagnostics.subsystem, category: "App")
    private var statusItemController: StatusItemController?
    private var capture: CaptureController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SPINDLE_SMOKE_TEST"] == "1" {
            runSmokeTest()
        }

        do {
            let location = try StorageLocation.applicationSupport()
            let database = try AppDatabase.open(at: location)
            let capture = CaptureController(
                ingestor: Ingestor(database: database, blobs: BlobStore(directory: location.blobsDirectory)),
                history: HistoryStore(database: database))
            capture.start(gateway: PasteboardGateway())
            self.capture = capture
        } catch {
            // The menu shows "History unavailable"; M4 adds a way to recover.
            logger.fault("Opening the history failed: \(error.localizedDescription, privacy: .public)")
        }

        statusItemController = StatusItemController(
            state: { [weak self] in
                StatusMenuState(itemCount: self?.capture?.itemCount, isPaused: self?.capture?.isPaused ?? false)
            },
            togglePause: { [weak self] in self?.capture?.togglePause() })
        logger.notice("Launched")
    }

    /// See `Scripts/verify-bundle.sh`.
    private func runSmokeTest() -> Never {
        let passed = ResourceCheck.run()
        print(passed ? "SMOKE_OK" : "SMOKE_FAILED: resources not found")
        exit(passed ? 0 : 1)
    }
}
