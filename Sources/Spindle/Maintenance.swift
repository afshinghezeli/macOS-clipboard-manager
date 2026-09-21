import Foundation
import SpindleCore
import SpindleStorage
import os

/// Background housekeeping: applies the retention policy about once an hour, when macOS finds it
/// convenient, and once shortly after launch.
@MainActor
final class Maintenance {
    private let logger = Logger(subsystem: Diagnostics.subsystem, category: "Maintenance")
    private let scheduler = NSBackgroundActivityScheduler(identifier: "\(Diagnostics.subsystem).maintenance")
    private let pruner: Pruner
    private let policy: @MainActor () -> RetentionPolicy
    private let didPrune: @MainActor () -> Void

    init(pruner: Pruner, policy: @escaping @MainActor () -> RetentionPolicy, didPrune: @escaping @MainActor () -> Void)
    {
        self.pruner = pruner
        self.policy = policy
        self.didPrune = didPrune
    }

    func start() {
        scheduler.repeats = true
        scheduler.interval = 3600
        scheduler.tolerance = 600
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.run()
                completion(.finished)
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(30))
            await run()
        }
    }

    private func run() async {
        let policy = policy()
        do {
            let result = try await pruner.prune(with: policy)
            if result.removedItems > 0 || result.removedFiles > 0 {
                logger.notice(
                    "Removed \(result.removedItems) items and \(result.removedFiles) files under the retention policy")
                didPrune()
            }
        } catch {
            logger.error("Applying the retention policy failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
