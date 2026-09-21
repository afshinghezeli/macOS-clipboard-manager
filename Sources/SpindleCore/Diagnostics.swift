import Foundation

public enum Diagnostics {
    /// The subsystem for every `Logger` and `OSSignposter` in Spindle: the app's bundle id, so debug
    /// builds (`….Spindle.dev`) and releases can be told apart in Console and `/usr/bin/log`.
    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.afshinghezeli.Spindle"
}
