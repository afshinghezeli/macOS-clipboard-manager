public import AppKit
import CoreGraphics

/// How often to look at the pasteboard's change count.
///
/// macOS has no public "pasteboard changed" notification, so every clipboard manager polls. Polling
/// is cheap (a change-count check costs well under a millisecond) but every timer fire wakes the
/// CPU, so the interval stretches when nobody is at the Mac.
public struct PollingPolicy: Hashable, Sendable {
    public var activeInterval: TimeInterval = 0.5
    public var idleInterval: TimeInterval = 2
    public var lowPowerInterval: TimeInterval = 1
    /// Seconds without keyboard or mouse input after which the Mac counts as idle.
    public var idleAfter: TimeInterval = 60

    public init() {}

    public func interval(secondsSinceInput: TimeInterval, lowPowerMode: Bool) -> TimeInterval {
        if secondsSinceInput >= idleAfter { return idleInterval }
        return lowPowerMode ? max(activeInterval, lowPowerInterval) : activeInterval
    }
}

/// Watches the pasteboard and reports each change once.
///
/// Every change count is handled exactly once, whatever the outcome: a read that macOS refuses is
/// not retried on the next tick, because on macOS 15.4 and later a retry could mean another system
/// prompt. Nothing already on the clipboard when monitoring starts is reported.
@MainActor
public final class ClipboardMonitor {
    private let gateway: PasteboardGateway
    private let policy: PollingPolicy
    private let frontmostApp: @MainActor () -> AppIdentity
    private let secondsSinceInput: @MainActor () -> TimeInterval
    private let now: @MainActor () -> Date
    private let onRead: @MainActor (PasteboardRead) -> Void

    private var lastChangeCount: Int?
    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private var isSuspended = false
    private var observers: [any NSObjectProtocol] = []

    public init(
        gateway: PasteboardGateway,
        policy: PollingPolicy = PollingPolicy(),
        frontmostApp: @escaping @MainActor () -> AppIdentity = ClipboardMonitor.systemFrontmostApp,
        secondsSinceInput: @escaping @MainActor () -> TimeInterval = ClipboardMonitor.systemSecondsSinceInput,
        now: @escaping @MainActor () -> Date = { .now },
        onRead: @escaping @MainActor (PasteboardRead) -> Void
    ) {
        self.gateway = gateway
        self.policy = policy
        self.frontmostApp = frontmostApp
        self.secondsSinceInput = secondsSinceInput
        self.now = now
        self.onRead = onRead
    }

    public var isRunning: Bool { lastChangeCount != nil }

    public func start() {
        guard !isRunning else { return }
        lastChangeCount = gateway.changeCount
        observeSleepAndSessionChanges()
        schedule()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        lastChangeCount = nil
    }

    /// Checks the pasteboard right away, for example when the panel opens, so the list is current.
    public func pollNow() {
        guard let lastChangeCount, !isSuspended else { return }
        let changeCount = gateway.changeCount
        guard changeCount != lastChangeCount else { return }
        // Stamp before reading: whatever the read returns, this change is handled.
        self.lastChangeCount = changeCount
        onRead(gateway.read(frontmostApp: frontmostApp(), at: now()))
    }

    // MARK: - Scheduling

    private func tick() {
        pollNow()
        let wanted = policy.interval(
            secondsSinceInput: secondsSinceInput(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if wanted != currentInterval { schedule() }
    }

    private func schedule() {
        timer?.invalidate()
        guard !isSuspended else {
            timer = nil
            return
        }
        currentInterval = policy.interval(
            secondsSinceInput: secondsSinceInput(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let timer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Tolerance lets macOS batch our wake-ups with others'. Common modes keep the timer firing
        // while a menu is open.
        timer.tolerance = currentInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func suspend() {
        isSuspended = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        pollNow()
        schedule()
    }

    private func observeSleepAndSessionChanges() {
        let center = NSWorkspace.shared.notificationCenter
        let pausing: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resuming: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in pausing {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.suspend() }
                })
        }
        for name in resuming {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resume() }
                })
        }
    }

    // MARK: - System defaults

    public static func systemFrontmostApp() -> AppIdentity {
        let app = NSWorkspace.shared.frontmostApplication
        return AppIdentity(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }

    public static func systemSecondsSinceInput() -> TimeInterval {
        // ~0 is kCGAnyInputEventType: keyboard, mouse or trackpad, whichever came last.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
