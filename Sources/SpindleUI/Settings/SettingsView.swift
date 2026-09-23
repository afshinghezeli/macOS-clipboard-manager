import AppKit
public import Foundation
import SpindleCore
import SpindleStorage
public import SpindleSystem
import SwiftUI
import UniformTypeIdentifiers

/// What the settings window needs from the rest of the app.
public struct SettingsEnvironment {
    public var pasteboardAccess: @MainActor () -> PasteboardAccess
    public var clearHistory: @MainActor () async -> Void
    /// Imports Maccy's history from the given folder; returns how many items came in.
    public var importFromMaccy: @MainActor (URL) async throws -> Int
    /// `nil` hides the update settings, for builds that don't update themselves.
    public var updates: UpdateControls?

    public init(
        pasteboardAccess: @escaping @MainActor () -> PasteboardAccess,
        clearHistory: @escaping @MainActor () async -> Void,
        importFromMaccy: @escaping @MainActor (URL) async throws -> Int = { _ in 0 },
        updates: UpdateControls? = nil
    ) {
        self.pasteboardAccess = pasteboardAccess
        self.clearHistory = clearHistory
        self.importFromMaccy = importFromMaccy
        self.updates = updates
    }
}

/// The update preferences the updater keeps itself.
public struct UpdateControls {
    public var automaticallyChecks: @MainActor () -> Bool
    public var setAutomaticallyChecks: @MainActor (Bool) -> Void
    public var checkNow: @MainActor () -> Void

    public init(
        automaticallyChecks: @escaping @MainActor () -> Bool,
        setAutomaticallyChecks: @escaping @MainActor (Bool) -> Void,
        checkNow: @escaping @MainActor () -> Void
    ) {
        self.automaticallyChecks = automaticallyChecks
        self.setAutomaticallyChecks = setAutomaticallyChecks
        self.checkNow = checkNow
    }
}

/// The settings window: General, History, Privacy.
struct SettingsView: View {
    @Bindable var settings: Settings
    var environment: SettingsEnvironment

    var body: some View {
        TabView {
            GeneralSettings(settings: settings, updates: environment.updates)
                .tabItem {
                    Label(
                        String(localized: "General", bundle: .spindleUI, comment: "Settings tab."),
                        systemImage: "gearshape")
                }
            HistorySettings(
                settings: settings, clearHistory: environment.clearHistory, importFromMaccy: environment.importFromMaccy
            )
            .tabItem {
                Label(
                    String(localized: "History", bundle: .spindleUI, comment: "Settings tab."), systemImage: "clock"
                )
            }
            PrivacySettings(settings: settings, pasteboardAccess: environment.pasteboardAccess)
                .tabItem {
                    Label(
                        String(localized: "Privacy", bundle: .spindleUI, comment: "Settings tab."),
                        systemImage: "hand.raised")
                }
        }
        // A TabView reports no height of its own to AppKit, so the window would open as a strip
        // with empty tabs. This fits the tallest tab; shorter ones keep the window the same size.
        .frame(width: 520, height: 480)
        .padding(20)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var settings: Settings
    var updates: UpdateControls?
    @State private var launchState = LaunchAtLogin.state
    @State private var launchError: String?

    var body: some View {
        Form {
            LabeledContent(
                String(
                    localized: "Open Spindle", bundle: .spindleUI,
                    comment: "Menu bar menu item; opens the history panel.")
            ) {
                ShortcutRecorder(
                    shortcut: Binding(
                        get: { settings.openShortcut }, set: { settings.openShortcut = $0 ?? .openPanelDefault }),
                    defaultShortcut: .openPanelDefault)
            }
            LabeledContent(
                String(
                    localized: "Ignore Next Copy", bundle: .spindleUI,
                    comment: "Menu item; the next copy isn't recorded.")
            ) {
                ShortcutRecorder(shortcut: $settings.ignoreNextCopyShortcut, defaultShortcut: nil)
            }
            Toggle(
                String(
                    localized: "Open at login", bundle: .spindleUI, comment: "Settings: start Spindle when logging in."),
                // A closure, not `set: setLaunchAtLogin`: passing the method directly crashes the
                // Swift 6.1 compiler while generating code for this file.
                isOn: Binding(get: { launchState != .off }, set: { setLaunchAtLogin($0) }))
            if launchState == .needsApproval {
                HStack {
                    Text(
                        "Allow Spindle in Login Items to finish.", bundle: .spindleUI,
                        comment: "Settings: launch at login needs approval."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Button(
                        String(
                            localized: "Open Login Items", bundle: .spindleUI, comment: "Button: opens System Settings."
                        )
                    ) {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            }
            if let launchError {
                Text(verbatim: launchError).font(.caption).foregroundStyle(.red)
            }
            Toggle(
                String(localized: "Paste as plain text by default", bundle: .spindleUI, comment: "Settings toggle."),
                isOn: $settings.prefersPlainText)
            Text(
                "Return then pastes plain text, and ⇧Return pastes with formatting.", bundle: .spindleUI,
                comment: "Settings: explains the plain text toggle."
            )
            .font(.caption).foregroundStyle(.secondary)

            if let updates {
                UpdateSettings(settings: settings, updates: updates)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchState = LaunchAtLogin.state
    }
}

/// Checking for updates is the only time Spindle's updater reaches the network, so it can be
/// turned off here.
struct UpdateSettings: View {
    @Bindable var settings: Settings
    var updates: UpdateControls
    @State private var automaticallyChecks: Bool

    init(settings: Settings, updates: UpdateControls) {
        self.settings = settings
        self.updates = updates
        _automaticallyChecks = State(initialValue: updates.automaticallyChecks())
    }

    var body: some View {
        Section(String(localized: "Updates", bundle: .spindleUI, comment: "Settings section.")) {
            Toggle(
                String(
                    localized: "Check for updates automatically", bundle: .spindleUI,
                    comment: "Settings toggle; checks once a day."),
                isOn: Binding(
                    get: { automaticallyChecks },
                    set: {
                        updates.setAutomaticallyChecks($0)
                        automaticallyChecks = $0
                    }))
            Toggle(
                String(
                    localized: "Include beta versions", bundle: .spindleUI,
                    comment: "Settings toggle; offers test versions as updates."),
                isOn: $settings.receivesBetaUpdates)
            Button(
                String(localized: "Check Now", bundle: .spindleUI, comment: "Button: checks for updates.")
            ) {
                updates.checkNow()
            }
        }
    }
}

// MARK: - History

struct HistorySettings: View {
    @Bindable var settings: Settings
    var clearHistory: @MainActor () async -> Void
    var importFromMaccy: @MainActor (URL) async throws -> Int = { _ in 0 }
    @State private var importResult: String?
    @State private var isImporting = false
    @State private var confirmingClear = false
    @State private var isClearing = false

    private static let day: TimeInterval = 86_400

    var body: some View {
        Form {
            Picker(
                String(localized: "Keep items", bundle: .spindleUI, comment: "Settings: how long history is kept."),
                selection: $settings.retention.maxAge
            ) {
                Text("Forever", bundle: .spindleUI, comment: "Retention choice.").tag(TimeInterval?.none)
                ForEach([1.0, 7, 30, 90, 365], id: \.self) { days in
                    Text(verbatim: Self.durationName(days)).tag(TimeInterval?.some(days * Self.day))
                }
            }
            Picker(
                String(localized: "Keep images", bundle: .spindleUI, comment: "Settings: how long images are kept."),
                selection: Binding(
                    get: { settings.retention.maxAgeByKind[.image] },
                    set: { settings.retention.maxAgeByKind[.image] = $0 })
            ) {
                Text("Like other items", bundle: .spindleUI, comment: "Image retention choice: no separate limit.").tag(
                    TimeInterval?.none)
                ForEach([1.0, 7, 30], id: \.self) { days in
                    Text(verbatim: Self.durationName(days)).tag(TimeInterval?.some(days * Self.day))
                }
            }
            Picker(
                String(
                    localized: "Storage limit", bundle: .spindleUI, comment: "Settings: largest size of the history."),
                selection: $settings.retention.maxTotalBytes
            ) {
                ForEach([500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 10_000_000_000], id: \.self) {
                    bytes in
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).tag(
                        Int?.some(bytes))
                }
                Text("No limit", bundle: .spindleUI, comment: "Storage limit choice.").tag(Int?.none)
            }
            Text(
                "Pinned items are always kept. When a limit is reached, the oldest items go first.", bundle: .spindleUI,
                comment: "Settings: explains retention."
            )
            .font(.caption).foregroundStyle(.secondary)

            Section {
                HStack {
                    Button(
                        String(
                            localized: "Import from Maccy…", bundle: .spindleUI,
                            comment: "Button: brings over Maccy's history.")
                    ) {
                        guard let folder = chooseMaccyFolder() else { return }
                        isImporting = true
                        Task {
                            importResult = await runImport(from: folder)
                            isImporting = false
                        }
                    }
                    .disabled(isImporting)
                    if let importResult {
                        Text(verbatim: importResult).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(
                    String(localized: "Clear History…", bundle: .spindleUI, comment: "Button: deletes the history."),
                    role: .destructive
                ) {
                    confirmingClear = true
                }
                .disabled(isClearing)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Clear the clipboard history?", bundle: .spindleUI, comment: "Confirmation title."),
            isPresented: $confirmingClear
        ) {
            Button(
                String(localized: "Clear History", bundle: .spindleUI, comment: "Confirmation button."),
                role: .destructive
            ) {
                isClearing = true
                Task {
                    await clearHistory()
                    isClearing = false
                }
            }
        } message: {
            Text(
                "Everything except pinned items is deleted from this Mac. This can't be undone.", bundle: .spindleUI,
                comment: "Confirmation message.")
        }
    }

    private func chooseMaccyFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(
            localized: "Choose the Maccy folder to import its history.", bundle: .spindleUI,
            comment: "Open panel message for importing from Maccy.")
        panel.prompt = String(
            localized: "Import", bundle: .spindleUI, comment: "Open panel button for importing from Maccy.")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = MaccyImporter.defaultFolder
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func runImport(from folder: URL) async -> String {
        do {
            let count = try await importFromMaccy(folder)
            return String(
                localized: "Imported \(count) items from Maccy.", bundle: .spindleUI,
                comment: "Result of importing from Maccy.")
        } catch MaccyImporter.ImportError.noHistoryFound {
            return String(
                localized: "That folder has no Maccy history. It is usually in ~/Library/Containers/org.p0deje.Maccy.",
                bundle: .spindleUI,
                comment: "Importing from Maccy: the chosen folder has no history.")
        } catch {
            return String(
                localized: "The import failed: \(error.localizedDescription)", bundle: .spindleUI,
                comment: "Importing from Maccy failed; followed by the reason.")
        }
    }

    static func durationName(_ days: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = days >= 365 ? [.year] : days >= 30 ? [.month] : days >= 7 ? [.weekOfMonth] : [.day]
        return formatter.string(from: days * day) ?? "\(Int(days))"
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @Bindable var settings: Settings
    var pasteboardAccess: @MainActor () -> PasteboardAccess
    @State private var selection: String?
    @State private var canPaste = PasteInjector.isPermitted
    @State private var access = PasteboardAccess.allowed

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(settings.ignoredApps.sorted(by: Self.byName), id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            Image(nsImage: Self.icon(bundleID)).resizable().frame(width: 18, height: 18)
                            Text(verbatim: AppNames.displayName(bundleID: bundleID, stored: nil) ?? bundleID)
                        }
                    }
                }
                .frame(minHeight: 130)
                HStack {
                    Button(
                        String(localized: "Add App…", bundle: .spindleUI, comment: "Button: pick an app to ignore."),
                        action: addApp)
                    Button(
                        String(
                            localized: "Remove", bundle: .spindleUI, comment: "Button: stop ignoring the selected app.")
                    ) {
                        if let selection { settings.ignoredApps.remove(selection) }
                    }
                    .disabled(selection == nil)
                }
            } header: {
                Text("Never keep copies from", bundle: .spindleUI, comment: "Settings section: ignored apps.")
            } footer: {
                Text(
                    "Copies that password managers mark as private are never kept, whichever app they come from.",
                    bundle: .spindleUI, comment: "Settings: explains ignored apps."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Toggle(
                String(
                    localized: "Keep copies from other devices", bundle: .spindleUI,
                    comment: "Settings toggle: Universal Clipboard."),
                isOn: $settings.keepsRemoteCopies)

            Section(String(localized: "Permissions", bundle: .spindleUI, comment: "Settings section.")) {
                PermissionRow(
                    title: String(localized: "Paste into other apps", bundle: .spindleUI, comment: "Permission name."),
                    granted: canPaste,
                    detail: String(
                        localized: "Listed under Accessibility in System Settings.", bundle: .spindleUI,
                        comment: "Where the paste permission is."),
                    open: SystemSettingsPane.accessibility.open)
                if #available(macOS 15.4, *) {
                    PermissionRow(
                        title: String(localized: "Read the clipboard", bundle: .spindleUI, comment: "Permission name."),
                        granted: access == .allowed,
                        detail: String(
                            localized: "Listed under Paste from Other Apps in System Settings.", bundle: .spindleUI,
                            comment: "Where the clipboard permission is."),
                        open: SystemSettingsPane.pasteboard.open)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // Permissions change in System Settings while this window is open; check now and then.
            while !Task.isCancelled {
                canPaste = PasteInjector.isPermitted
                access = pasteboardAccess()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { settings.ignoredApps.insert(bundleID) }
        }
    }

    private static func byName(_ lhs: String, _ rhs: String) -> Bool {
        let left = AppNames.displayName(bundleID: lhs, stored: nil) ?? lhs
        let right = AppNames.displayName(bundleID: rhs, stored: nil) ?? rhs
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private static func icon(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

struct PermissionRow: View {
    var title: String
    var granted: Bool
    var detail: String
    var buttonTitle = String(
        localized: "Open System Settings", bundle: .spindleUI, comment: "Button: opens System Settings.")
    var open: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(buttonTitle, action: open)
                    .controlSize(.small)
            }
        }
    }
}
