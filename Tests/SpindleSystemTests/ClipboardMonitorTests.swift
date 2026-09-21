import AppKit
import SpindleCore
import Testing

@testable import SpindleSystem

@Suite
struct PollingPolicyTests {
    private let policy = PollingPolicy()

    @Test
    func pollsTwiceASecondWhileSomeoneIsWorking() {
        #expect(policy.interval(secondsSinceInput: 5, lowPowerMode: false) == 0.5)
    }

    @Test
    func slowsDownWhenTheMacIsIdle() {
        #expect(policy.interval(secondsSinceInput: 61, lowPowerMode: false) == 2)
    }

    @Test
    func slowsDownInLowPowerMode() {
        #expect(policy.interval(secondsSinceInput: 5, lowPowerMode: true) == 1)
        #expect(policy.interval(secondsSinceInput: 120, lowPowerMode: true) == 2)
    }
}

@MainActor
@Suite
final class ClipboardMonitorTests {
    // `nonisolated(unsafe)` only so that deinit (nonisolated in Swift 6.1) can release it; deinit
    // runs after the test has finished, when nothing else can touch the pasteboard.
    private nonisolated(unsafe) let pasteboard = NSPasteboard.withUniqueName()
    private var reads: [PasteboardRead] = []
    private var access = PasteboardAccess.denied
    private func makeMonitor(
        access: @escaping @MainActor (NSPasteboard) -> PasteboardAccess = { _ in .allowed }
    )
        -> ClipboardMonitor
    {
        ClipboardMonitor(
            gateway: PasteboardGateway(pasteboard: pasteboard, access: access),
            frontmostApp: { AppIdentity(bundleID: "com.apple.TextEdit", name: "TextEdit") },
            secondsSinceInput: { 0 },
            onRead: { [unowned self] in self.reads.append($0) })
    }

    deinit {
        pasteboard.releaseGlobally()
    }

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @Test
    func ignoresWhatWasOnTheClipboardBeforeStarting() {
        let monitor = makeMonitor()
        copy("before launch")
        monitor.start()
        defer { monitor.stop() }
        monitor.pollNow()
        #expect(reads.isEmpty)
    }

    @Test
    func reportsEachChangeOnce() {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        copy("first")
        monitor.pollNow()
        monitor.pollNow()
        copy("second")
        monitor.pollNow()
        let texts = reads.compactMap { read -> String? in
            if case .copy(let copy) = read { return copy.plainText }
            return nil
        }
        #expect(texts == ["first", "second"])
    }

    @Test
    func doesNotRetryARefusedRead() {
        let monitor = makeMonitor(access: { [unowned self] _ in self.access })
        monitor.start()
        defer { monitor.stop() }
        copy("secret")
        monitor.pollNow()
        access = .allowed
        monitor.pollNow()
        #expect(reads == [.restricted(.denied)])
    }

    @Test
    func staysQuietWhileSuspendedAndCatchesUpOnResume() {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        monitor.suspend()
        copy("while the screen was asleep")
        monitor.pollNow()
        #expect(reads.isEmpty)
        monitor.resume()
        #expect(reads.count == 1)
    }

    @Test
    func doesNothingWhenStopped() {
        let monitor = makeMonitor()
        copy("not watching")
        monitor.pollNow()
        #expect(reads.isEmpty)
        #expect(!monitor.isRunning)
    }
}
