import AppKit
import SpindleStorage

/// Thumbnails for image rows, loaded on demand and kept in memory only while there is room.
///
/// Thumbnails are small (at most 256 px, about 10 KB), so decoding one on the main thread is cheap;
/// reading it from the database is not, and happens off the main thread.
@MainActor
final class ThumbnailCache {
    private let history: HistoryStore?
    private let cache = NSCache<NSNumber, NSImage>()
    private var loading: Set<Int64> = []

    init(history: HistoryStore?) {
        self.history = history
        cache.totalCostLimit = 16 << 20
    }

    /// The thumbnail if it is in memory. Otherwise starts loading it and calls `loaded` when done.
    func image(for itemID: Int64, loaded: @escaping @MainActor (NSImage) -> Void) -> NSImage? {
        if let image = cache.object(forKey: NSNumber(value: itemID)) { return image }
        guard let history, loading.insert(itemID).inserted else { return nil }
        Task {
            defer { loading.remove(itemID) }
            guard let data = try? await history.thumbnail(for: itemID), let image = NSImage(data: data) else { return }
            cache.setObject(image, forKey: NSNumber(value: itemID), cost: data.count)
            loaded(image)
        }
        return nil
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
