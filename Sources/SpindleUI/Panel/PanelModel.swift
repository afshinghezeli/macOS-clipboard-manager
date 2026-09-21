public import Observation

/// Everything the panel shows and does, independent of its views, so it can be tested without a
/// window.
@MainActor
@Observable
public final class PanelModel {
    public var query = ""

    /// Increases every time the panel opens; views watch it to reset focus and scroll position.
    public private(set) var openCount = 0

    public init() {}

    /// Call right before the panel appears.
    public func panelWillOpen() {
        query = ""
        openCount += 1
    }
}
