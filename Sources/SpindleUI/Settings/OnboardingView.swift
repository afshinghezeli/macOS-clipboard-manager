import AppKit
import SpindleCore
import SpindleSystem
import SwiftUI

/// Shown on first launch: how to open Spindle, the permission it needs to paste, and what it never
/// keeps. One page, so nothing is hidden behind "Next".
struct OnboardingView: View {
    @Bindable var settings: Settings
    var pasteboardAccess: @MainActor () -> PasteboardAccess
    var done: () -> Void

    @State private var canPaste = PasteInjector.isPermitted
    @State private var access = PasteboardAccess.allowed

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Spindle", bundle: .spindleUI, comment: "Onboarding title.")
                    .font(.system(size: 22, weight: .semibold))
                Text(
                    "Spindle remembers what you copy, so you can find it again and paste it anywhere.",
                    bundle: .spindleUI,
                    comment: "Onboarding subtitle."
                )
                .foregroundStyle(.secondary)
            }

            step(
                number: 1,
                title: String(localized: "Open it with a shortcut", bundle: .spindleUI, comment: "Onboarding step.")
            ) {
                ShortcutRecorder(
                    shortcut: Binding(
                        get: { settings.openShortcut }, set: { settings.openShortcut = $0 ?? .openPanelDefault }),
                    defaultShortcut: .openPanelDefault)
                Text(
                    "You can also click the clipboard icon in the menu bar.", bundle: .spindleUI,
                    comment: "Onboarding hint."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            step(
                number: 2,
                title: String(localized: "Let Spindle paste for you", bundle: .spindleUI, comment: "Onboarding step.")
            ) {
                Text(
                    "To paste, Spindle presses ⌘V in the app you were using. macOS asks you to allow that under Accessibility. Without it, Spindle copies the item and you press ⌘V yourself.",
                    bundle: .spindleUI, comment: "Onboarding: why the paste permission is needed."
                )
                .fixedSize(horizontal: false, vertical: true)
                PermissionRow(
                    title: String(localized: "Paste into other apps", bundle: .spindleUI, comment: "Permission name."),
                    granted: canPaste,
                    detail: String(
                        localized: "Listed under Accessibility in System Settings.", bundle: .spindleUI,
                        comment: "Where the paste permission is."),
                    buttonTitle: String(
                        localized: "Allow…", bundle: .spindleUI, comment: "Button: asks macOS for the paste permission."
                    )
                ) {
                    // The system prompt appears only the first time; after that, System Settings is the way.
                    if !PasteInjector.requestPermission() { SystemSettingsPane.accessibility.open() }
                }
                if #available(macOS 15.4, *), access != .allowed {
                    PermissionRow(
                        title: String(localized: "Read the clipboard", bundle: .spindleUI, comment: "Permission name."),
                        granted: false,
                        detail: String(
                            localized: "Listed under Paste from Other Apps in System Settings.", bundle: .spindleUI,
                            comment: "Where the clipboard permission is."),
                        open: SystemSettingsPane.pasteboard.open)
                }
            }

            step(
                number: 3,
                title: String(localized: "What stays private", bundle: .spindleUI, comment: "Onboarding step.")
            ) {
                Text(
                    "Your history stays on this Mac. Copies that password managers mark as private are never kept, and neither is anything copied in Passwords, Keychain Access or the apps you add in Settings.",
                    bundle: .spindleUI, comment: "Onboarding: privacy summary."
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(
                    String(
                        localized: "Start Using Spindle", bundle: .spindleUI, comment: "Onboarding: closes the window."),
                    action: done
                )
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 540)
        .task {
            // The paste permission is granted in System Settings while this window is open.
            while !Task.isCancelled {
                canPaste = PasteInjector.isPermitted
                access = pasteboardAccess()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.quaternary))
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: title).font(.headline)
                content()
            }
        }
    }
}
