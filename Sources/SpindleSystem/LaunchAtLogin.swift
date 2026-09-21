import ServiceManagement

/// Starting Spindle when the user logs in, through `SMAppService`. Nothing is registered unless
/// the user turns it on.
@MainActor
public enum LaunchAtLogin {
    public enum State: Equatable, Sendable {
        case off
        case on
        /// Turned on, but macOS wants the user to allow it in System Settings → General → Login Items.
        case needsApproval
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    public static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
