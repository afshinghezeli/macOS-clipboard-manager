import AppKit
import SpindleUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.afshinghezeli.Spindle", category: "App")
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SPINDLE_SMOKE_TEST"] == "1" {
            runSmokeTest()
        }
        statusItemController = StatusItemController()
        logger.info("Launched")
    }

    /// See `Scripts/verify-bundle.sh`.
    private func runSmokeTest() -> Never {
        let passed = ResourceCheck.run()
        print(passed ? "SMOKE_OK" : "SMOKE_FAILED: resources not found")
        exit(passed ? 0 : 1)
    }
}
