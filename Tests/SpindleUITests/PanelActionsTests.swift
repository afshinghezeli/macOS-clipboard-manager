import Foundation
import SpindleCore
import SpindleStorage
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct PanelActionsTests {
    private func summary(kind: ItemKind = .text, pinned: Bool = false) -> ItemSummary {
        ItemSummary(id: 1, seq: 1, kind: kind, preview: "x", createdAt: .now, lastUsedAt: .now, isPinned: pinned)
    }

    @Test
    func textOffersEveryWayToPaste() {
        let commands = PanelActions.list(for: summary(), targetAppName: "Notes", canPaste: true).map(\.command)
        #expect(commands == [.paste, .pasteAsPlainText, .copy, .togglePin, .delete])
    }

    @Test
    func imagesHaveNoPlainTextPaste() {
        let commands = PanelActions.list(for: summary(kind: .image), targetAppName: "Notes", canPaste: true).map(
            \.command)
        #expect(!commands.contains(.pasteAsPlainText))
    }

    @Test
    func pinnedItemsCanMove() {
        let commands = PanelActions.list(for: summary(pinned: true), targetAppName: nil, canPaste: false).map(\.command)
        #expect(commands == [.copy, .togglePin, .movePinUp, .movePinDown, .delete])
    }

    @Test
    func withoutPermissionThereIsNoPaste() {
        let commands = PanelActions.list(for: summary(), targetAppName: "Notes", canPaste: false).map(\.command)
        #expect(!commands.contains(.paste))
    }
}
