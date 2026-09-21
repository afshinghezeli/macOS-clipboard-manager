public import Foundation

/// How much history to keep. Pinned items are never removed by any of these limits.
///
/// The default keeps everything until the history's payloads reach 2 GB (decimal, as Finder counts),
/// then drops the oldest
/// items. There is no item cap and no age limit unless the user sets one.
public struct RetentionPolicy: Hashable, Sendable, Codable {
    /// Keep at most this many unpinned items. `nil` means no limit.
    public var maxItems: Int?
    /// Remove unpinned items not used for this long. `nil` means keep them regardless of age.
    public var maxAge: TimeInterval?
    /// Remove the oldest unpinned items while the stored payloads exceed this many bytes.
    public var maxTotalBytes: Int?
    /// Age limits for particular kinds, overriding ``maxAge``; for example, images for 30 days.
    public var maxAgeByKind: [ItemKind: TimeInterval]

    public init(
        maxItems: Int? = nil,
        maxAge: TimeInterval? = nil,
        maxTotalBytes: Int? = 2_000_000_000,
        maxAgeByKind: [ItemKind: TimeInterval] = [:]
    ) {
        self.maxItems = maxItems
        self.maxAge = maxAge
        self.maxTotalBytes = maxTotalBytes
        self.maxAgeByKind = maxAgeByKind
    }

    /// The age limit that applies to items of `kind`, if any.
    public func maxAge(for kind: ItemKind) -> TimeInterval? {
        maxAgeByKind[kind] ?? maxAge
    }
}

extension ItemKind: Codable {}
