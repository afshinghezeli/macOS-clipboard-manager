public import AppKit
public import SpindleCore
import os

/// What macOS lets Spindle do with the clipboard (macOS 15.4 and later).
public enum PasteboardAccess: Hashable, Sendable {
    /// Reads work without a prompt. This includes "never asked yet" on systems that don't enforce
    /// pasteboard privacy.
    case allowed
    /// Every read shows the user a system alert, so background reads must stop.
    case askEachTime
    /// Reads are refused.
    case denied
}

/// The result of looking at the pasteboard after its change count moved.
public enum PasteboardRead: Hashable, Sendable {
    case copy(CapturedCopy)
    /// Spindle wrote this itself, when pasting from history.
    case ownWrite
    /// Marked private by its source; nothing but the list of types was looked at.
    case marked
    /// macOS doesn't allow reading right now.
    case restricted(PasteboardAccess)
    /// Nothing Spindle keeps, for example only private or promised types.
    case nothingToKeep
    /// The pasteboard changed again while it was being read; read it again.
    case changedDuringRead
}

/// The source app as seen when a copy was noticed.
public struct AppIdentity: Hashable, Sendable {
    public var bundleID: String?
    public var name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The only code in Spindle that touches `NSPasteboard.general` (ADR 0004).
///
/// NSPasteboard isn't thread-safe and AppKit uses it on the main thread, so all access happens on
/// the main actor. Reads are synchronous calls into the pasteboard server, which is why this reads
/// as little as possible: allow-listed flavors only, never TIFF when a compressed image is offered,
/// and nothing at all when the copy carries a privacy marker.
@MainActor
public final class PasteboardGateway {
    private let pasteboard: NSPasteboard
    private let access: @MainActor (NSPasteboard) -> PasteboardAccess
    private var ownChangeCounts: [Int] = []
    private let signposter = OSSignposter(subsystem: "com.afshinghezeli.Spindle", category: "Capture")

    /// Largest payload read per flavor; see ``PasteboardFlavor/captureLimit``.
    var sizeLimit: (PasteboardFlavor) -> Int = \.captureLimit

    public init(
        pasteboard: NSPasteboard = .general,
        access: @escaping @MainActor (NSPasteboard) -> PasteboardAccess = PasteboardGateway.systemAccess
    ) {
        self.pasteboard = pasteboard
        self.access = access
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func read(frontmostApp: AppIdentity, at date: Date) -> PasteboardRead {
        // Reads block the main thread; anything over 16 ms here is worth investigating.
        let interval = signposter.beginInterval("capture")
        defer { signposter.endInterval("capture", interval) }

        let changeCount = pasteboard.changeCount
        if ownChangeCounts.contains(changeCount) { return .ownWrite }

        // The list of types is metadata; reading it doesn't count as reading the clipboard.
        let declared = (pasteboard.types ?? []).map { PasteboardFlavor($0.rawValue) }
        if !PasteboardFlavor.privacyMarkers.isDisjoint(with: declared) { return .marked }

        let access = access(pasteboard)
        guard access == .allowed else { return .restricted(access) }

        let items = (pasteboard.pasteboardItems ?? []).map(readItem).filter { !$0.representations.isEmpty }
        guard pasteboard.changeCount == changeCount else { return .changedDuringRead }
        guard !items.isEmpty else { return .nothingToKeep }

        var source = frontmostApp
        if let claimed = pasteboard.string(forType: NSPasteboard.PasteboardType(PasteboardFlavor.source.rawValue)),
            !claimed.isEmpty, claimed != frontmostApp.bundleID
        {
            source = AppIdentity(bundleID: claimed, name: nil)
        }
        return .copy(
            CapturedCopy(
                items: items,
                declaredTypes: declared,
                sourceBundleID: source.bundleID,
                sourceAppName: source.name,
                changeCount: changeCount,
                capturedAt: date))
    }

    private func readItem(_ item: NSPasteboardItem) -> CapturedItem {
        let available = Set(item.types.map { PasteboardFlavor($0.rawValue) })
        let hasCompressedImage = !available.isDisjoint(with: [.png, .jpeg, .heic])
        var representations: [Representation] = []
        for flavor in PasteboardFlavor.captured where available.contains(flavor) {
            // A 5K screenshot is about 59 MB as TIFF; don't pay for it when PNG is right there.
            if flavor == .tiff && hasCompressedImage { continue }
            guard let data = item.data(forType: NSPasteboard.PasteboardType(flavor.rawValue)),
                !data.isEmpty, data.count <= sizeLimit(flavor)
            else { continue }
            representations.append(Representation(flavor: flavor, data: data))
        }
        return CapturedItem(representations: representations)
    }

    /// Replaces the pasteboard's contents with `items`, marked as coming from `sourceBundleID`, and
    /// returns the new change count. The next ``read(frontmostApp:at:)`` of that change reports
    /// ``PasteboardRead/ownWrite``.
    @discardableResult
    public func write(_ items: [CapturedItem], sourceBundleID: String) -> Int {
        pasteboard.clearContents()
        let pasteboardItems = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for representation in item.representations {
                pasteboardItem.setData(
                    representation.data, forType: NSPasteboard.PasteboardType(representation.flavor.rawValue))
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(pasteboardItems)
        pasteboard.setString(sourceBundleID, forType: NSPasteboard.PasteboardType(PasteboardFlavor.source.rawValue))
        let changeCount = pasteboard.changeCount
        ownChangeCounts.append(changeCount)
        if ownChangeCounts.count > 16 { ownChangeCounts.removeFirst() }
        return changeCount
    }

    /// Reads the user's choice in System Settings → Privacy & Security → Paste from Other Apps.
    public static func systemAccess(_ pasteboard: NSPasteboard) -> PasteboardAccess {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch pasteboard.accessBehavior {
        case .alwaysDeny: return .denied
        case .ask: return .askEachTime
        // `.default` means "never asked". Where pasteboard privacy isn't enforced, reads succeed;
        // where it is, the first read prompts once and the state becomes `.ask`.
        case .default, .alwaysAllow: return .allowed
        @unknown default: return .allowed
        }
    }
}
