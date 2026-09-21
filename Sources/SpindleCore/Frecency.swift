public import Foundation

/// How often and how recently an item was used, as a single number the database can index.
///
/// Each use adds 1 to a score that halves every ``halfLife``. Storing the score directly would mean
/// rewriting every row as time passes. Instead the stored key is `ln(score) + λ·t`, which doesn't
/// change over time, and ordering by key equals ordering by current score at any moment.
public enum Frecency {
    public static let halfLife: TimeInterval = 72 * 3600

    private static let decayRate = log(2) / halfLife
    // Measuring time from 2020 keeps λ·t small, so keys keep plenty of floating-point precision.
    private static let epoch = Date(timeIntervalSince1970: 1_577_836_800)

    private static func decayedTime(_ date: Date) -> Double {
        decayRate * date.timeIntervalSince(epoch)
    }

    /// The key of an item used once, at `date`.
    public static func key(firstUsedAt date: Date) -> Double {
        decayedTime(date)
    }

    /// The key after one more use at `date`.
    public static func key(_ key: Double, usedAgainAt date: Date) -> Double {
        let now = decayedTime(date)
        return log(exp(key - now) + 1) + now
    }

    /// The decayed use count at `date`: 1.0 right after a single use, 0.5 one half-life later.
    public static func score(_ key: Double, at date: Date) -> Double {
        exp(key - decayedTime(date))
    }
}
