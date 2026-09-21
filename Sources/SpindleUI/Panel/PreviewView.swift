import AppKit
import SpindleCore
import SpindleStorage
import SwiftUI

/// The right side of the panel: the selected item in full, and where it came from.
struct PreviewView: View {
    var details: ItemDetails?
    var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let details {
                content(details)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                MetadataView(details: details)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func content(_ details: ItemDetails) -> some View {
        switch details.summary.kind {
        case .image:
            if let image {
                // Scaled down to fit, never up: a small image stays sharp at its own size.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .accessibilityLabel(ItemPresentation.kindName(.image))
            }
        case .file:
            FileListView(urls: details.fileURLs)
        case .color:
            ColorPreview(text: details.text ?? details.summary.preview)
        case .text, .richText, .link:
            TextPreview(text: details.text ?? "", isTruncated: details.isTextTruncated)
        }
    }
}

private struct TextPreview: View {
    var text: String
    var isTruncated: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if isTruncated {
                    Text("Showing the first 100 KB.", bundle: .spindleUI, comment: "Below a long text in the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}

private struct FileListView: View {
    var urls: [URL]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: url.lastPathComponent)
                                .font(.system(size: 13))
                            Text(verbatim: url.deletingLastPathComponent().path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ColorPreview: View {
    var text: String

    var body: some View {
        VStack(spacing: 14) {
            if let color = ColorParser.color(from: text) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: color))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                    .frame(width: 140, height: 140)
            }
            Text(verbatim: text)
                .font(.system(size: 17, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Source app, when it was copied, how often it was used, and what it contains.
private struct MetadataView: View {
    var details: ItemDetails

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row(
                String(
                    localized: "Source", bundle: .spindleUI,
                    comment: "Preview metadata label: the app it was copied from."),
                AppNames.displayName(bundleID: details.sourceBundleID, stored: details.sourceAppName)
                    ?? String(
                        localized: "Unknown", bundle: .spindleUI, comment: "Preview metadata: source app unknown."))
            GridRow {
                label(
                    String(
                        localized: "Copied", bundle: .spindleUI, comment: "Preview metadata label: when it was copied.")
                )
                Text(details.summary.createdAt, format: .relative(presentation: .named))
            }
            if details.summary.useCount > 1 {
                row(
                    String(
                        localized: "Used", bundle: .spindleUI,
                        comment: "Preview metadata label: how often it was copied or pasted."),
                    String(
                        localized: "\(details.summary.useCount) times", bundle: .spindleUI,
                        comment: "Preview metadata: how often an item was copied or pasted."))
            }
            row(
                String(
                    localized: "Content", bundle: .spindleUI, comment: "Preview metadata label: what the item contains."
                ),
                ContentDescription.describe(details))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            label(title)
            Text(verbatim: value).lineLimit(1)
        }
    }

    private func label(_ title: String) -> some View {
        Text(verbatim: title).foregroundStyle(.tertiary).gridColumnAlignment(.trailing)
    }
}

/// A short description of what an item contains, like "12 words · 2 lines · 1 KB".
enum ContentDescription {
    static func describe(_ details: ItemDetails) -> String {
        var parts: [String] = []
        switch details.summary.kind {
        case .image:
            if let width = details.imageWidth, let height = details.imageHeight {
                parts.append("\(width) × \(height)")
            }
        case .file:
            parts.append(
                String(
                    localized: "\(details.fileURLs.count) files", bundle: .spindleUI, comment: "Number of copied files."
                ))
        case .text, .richText, .link, .color:
            if let text = details.text {
                let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
                parts.append(
                    String(localized: "\(words) words", bundle: .spindleUI, comment: "Number of words in text."))
                if lines > 1 {
                    parts.append(
                        String(localized: "\(lines) lines", bundle: .spindleUI, comment: "Number of lines in text."))
                }
            }
        }
        // A file item stores the file's location, not the file, so its size would mislead.
        if details.summary.kind != .file {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(details.byteSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}
