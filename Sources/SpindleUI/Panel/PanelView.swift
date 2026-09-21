public import SwiftUI

/// The panel's content.
public struct PanelView: View {
    @Bindable private var model: PanelModel
    @FocusState private var searchFocused: Bool

    public init(model: PanelModel) {
        self.model = model
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
            Spacer(minLength: 0)
        }
        .onChange(of: model.openCount, initial: true) { searchFocused = true }
    }
}
