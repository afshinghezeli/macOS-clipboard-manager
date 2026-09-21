import Foundation

/// Confirms that the module's resources resolve from the running process.
///
/// `Scripts/verify-bundle.sh` launches the packaged app with the source checkout hidden and
/// `SPINDLE_SMOKE_TEST=1`; the app calls this, reports, and exits.
public enum ResourceCheck {
    public static func run() -> Bool {
        Bundle.spindleUI.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
            != nil
    }
}
