public import SwiftUI

/// The panel's content: the search field, the list and the preview side by side, and a footer.
public struct PanelView: View {
    @Bindable private var model: PanelModel
    @State private var thumbnails: ThumbnailCache

    public init(model: PanelModel) {
        self.model = model
        _thumbnails = State(initialValue: ThumbnailCache(history: model.history))
    }

    public var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $model.query,
                placeholder: String(
                    localized: "Search clipboard history", bundle: .spindleUI, comment: "Search field placeholder."),
                focusToken: model.openCount,
                onCommand: { model.handle($0) }
            )
            .frame(height: 26)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {
                HistoryTableView(
                    items: model.items,
                    selectedID: model.selectedID,
                    thumbnails: thumbnails,
                    onSelect: { model.select($0) },
                    onActivate: { id in
                        model.select(id)
                        model.handle(.paste)
                    }
                )
                .frame(width: 320)

                Divider()

                PreviewView(details: model.preview, image: model.previewImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
