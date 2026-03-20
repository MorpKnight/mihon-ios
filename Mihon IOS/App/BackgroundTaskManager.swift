//
//  BackgroundTaskManager.swift
//  Mihon IOS
//

import Foundation
import UIKit

@MainActor
protocol BackgroundTaskManaging: AnyObject {
    @discardableResult
    func beginTask(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UUID
    func endTask(_ id: UUID)
}

@MainActor
final class AppBackgroundTaskManager: BackgroundTaskManaging {
    private var activeTasks: [UUID: UIBackgroundTaskIdentifier] = [:]

    @discardableResult
    func beginTask(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            expirationHandler()
            self?.endTask(token)
        }
        activeTasks[token] = identifier
        return token
    }

    func endTask(_ id: UUID) {
        guard let identifier = activeTasks.removeValue(forKey: id) else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
