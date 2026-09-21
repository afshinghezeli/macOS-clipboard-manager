public import SwiftUI

/// The panel's content: the search field, the list and the preview side by side, and a footer.
public struct PanelView: View {
    @Bindable private var model: PanelModel
    @State private var thumbnails: ThumbnailCache
    @FocusState private var searchFocused: Bool

    public init(model: PanelModel) {
        self.model = model
        _thumbnails = State(initialValue: ThumbnailCache(history: model.history))
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField(
                String(localized: "Search clipboard history", bundle: .spindleUI, comment: "Search field placeholder."),
                text: $model.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .focused($searchFocused)

            Divider()

            HStack(spacing: 0) {
                HistoryTableView(
                    items: model.items,
                    selectedID: model.selectedID,
                    thumbnails: thumbnails,
                    onSelect: { model.select($0) },
                    onActivate: { _ in }
                )
                .frame(width: 320)

                Divider()

                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.openCount, initial: true) { searchFocused = true }
    }
}
