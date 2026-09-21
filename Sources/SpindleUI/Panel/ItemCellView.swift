import AppKit
import SpindleCore
import SpindleStorage

/// One row of the history list: an icon, the item's text on one line, and a pin for pinned items.
final class ItemCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ItemCell")
    static let rowHeight: CGFloat = 34

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private var itemID: Int64?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.font = .systemFont(ofSize: 13)
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        pin.contentTintColor = .tertiaryLabelColor
        pin.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)

        for view in [icon, title, pin] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = title
        imageView = icon
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -6),
            pin.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pin.widthAnchor.constraint(equalToConstant: 12),
            pin.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @MainActor
    func configure(with item: ItemSummary, thumbnails: ThumbnailCache) {
        itemID = item.id
        title.stringValue = ItemPresentation.title(for: item)
        pin.isHidden = !item.isPinned
        setAccessibilityLabel(ItemPresentation.accessibilityLabel(for: item))

        if item.kind == .image {
            let id = item.id
            icon.image =
                thumbnails.image(for: id) { [weak self] image in
                    guard self?.itemID == id else { return }  // the cell was reused meanwhile
                    self?.icon.image = image
                } ?? ItemPresentation.symbol(for: item.kind)
        } else if item.kind == .color, let color = ColorParser.color(from: item.preview) {
            icon.image = ItemPresentation.swatch(color)
        } else {
            icon.image = ItemPresentation.symbol(for: item.kind)
        }
    }
}
