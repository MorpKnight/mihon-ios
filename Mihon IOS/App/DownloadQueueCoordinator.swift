//
//  DownloadQueueCoordinator.swift
//  Mihon IOS
//

import Foundation

@MainActor
protocol DownloadQueueCoordinating: AnyObject {
    var activeJobID: UUID? { get }
    func startIfIdle(
        jobs: [DownloadJob],
        run: @escaping @Sendable (UUID) async -> Void
    ) -> UUID?
    func cancelIfActive(jobID: UUID) -> Bool
    func finishIfActive(jobID: UUID) -> Bool
}

@MainActor
final class DownloadQueueCoordinator: DownloadQueueCoordinating {
    private(set) var activeJobID: UUID?
    private var activeTask: Task<Void, Never>?

    func startIfIdle(
        jobs: [DownloadJob],
        run: @escaping @Sendable (UUID) async -> Void
    ) -> UUID? {
        guard activeTask == nil else { return nil }
        guard let next = jobs
            .filter({ $0.state == .queued })
            .sorted(by: { $0.queuedAt < $1.queuedAt })
            .first
        else { return nil }

        activeJobID = next.id
        activeTask = Task.detached(priority: .utility) {
            await run(next.id)
        }
        return next.id
    }

    func cancelIfActive(jobID: UUID) -> Bool {
        guard activeJobID == jobID else { return false }
        activeTask?.cancel()
        activeTask = nil
        activeJobID = nil
        return true
    }

    func finishIfActive(jobID: UUID) -> Bool {
        guard activeJobID == jobID else { return false }
        activeTask = nil
        activeJobID = nil
        return true
    }
}
