import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.afshinghezeli.Spindle", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Launched")
    }
}
