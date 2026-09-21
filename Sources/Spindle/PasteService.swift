import AppKit
import SpindleCore
import SpindleStorage
import SpindleSystem
import SpindleUI
import os

/// Puts a chosen history item back on the clipboard and, unless only copying, pastes it into the
/// app that was in front when the panel opened.
@MainActor
final class PasteService {
    private let logger = Logger(subsystem: Diagnostics.subsystem, category: "Paste")
    private let history: HistoryStore
    private let gateway: PasteboardGateway
    private var askedForPermission = false

    init(history: HistoryStore, gateway: PasteboardGateway) {
        self.history = history
        self.gateway = gateway
    }

    /// - Parameter hidePanel: closes the panel after the clipboard is written, before pasting, so
    ///   the target app gets its focus back.
    func perform(_ item: ItemSummary, mode: PasteMode, into target: NSRunningApplication?, hidePanel: () -> Void) async
    {
        do {
            var items = try await history.pasteItems(for: item.id, plainTextOnly: mode == .pasteAsPlainText)
            if items.isEmpty {
                // Nothing plain to offer (an image, say): paste it as it was copied.
                items = try await history.pasteItems(for: item.id)
            }
            guard !items.isEmpty else { return }
            gateway.write(items, sourceBundleID: Bundle.main.bundleIdentifier ?? "com.afshinghezeli.Spindle")
            hidePanel()
            try await history.markUsed(item.id)
        } catch {
            logger.error("Reading the item to paste failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard mode != .copy, let target else { return }
        guard PasteInjector.isPermitted else {
            // The item is on the clipboard either way. Ask once per launch, and only now, when the
            // user has just tried to paste; onboarding explains it properly (M4.5).
            if !askedForPermission {
                askedForPermission = true
                PasteInjector.requestPermission()
            }
            return
        }
        do {
            try await PasteInjector.paste(into: target)
        } catch {
            logger.notice(
                "Pasting into \(target.bundleIdentifier ?? "?", privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
