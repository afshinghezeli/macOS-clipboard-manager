import SpindleSystem
import SwiftUI

/// Shown when macOS blocks Spindle from reading the clipboard (macOS 15.4 and later), so the user
/// knows why new copies are missing and where to fix it.
struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(
                "macOS is blocking clipboard access, so new copies aren't being recorded.", bundle: .spindleUI,
                comment: "Panel banner when clipboard access is denied or set to ask.")
            Spacer()
            Button(
                String(localized: "Open System Settings", bundle: .spindleUI, comment: "Button: opens System Settings.")
            ) {
                SystemSettingsPane.pasteboard.open()
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}
