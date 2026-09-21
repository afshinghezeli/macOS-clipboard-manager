import AppKit
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct PanelSnapshotTests {
    @Test
    func emptyPanel() throws {
        let model = PanelModel()
        try Snapshot.write(PanelView(model: model), named: "panel-empty", size: NSSize(width: 760, height: 460))
        try Snapshot.write(
            PanelView(model: model), named: "panel-empty-dark", size: NSSize(width: 760, height: 460),
            appearance: .darkAqua)
    }
}
