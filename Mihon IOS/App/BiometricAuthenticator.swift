//
//  BiometricAuthenticator.swift
//  Mihon IOS
//

import Foundation
import LocalAuthentication

enum BiometricAuthenticationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Face ID is not available on this device."
        }
    }
}

protocol BiometricAuthenticating {
    func evaluate(reason: String) async -> Result<Void, Error>
}

final class LocalBiometricAuthenticator: BiometricAuthenticating {
    func evaluate(reason: String) async -> Result<Void, Error> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            return .failure(authError ?? BiometricAuthenticationError.unavailable)
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            guard success else {
                return .failure(BiometricAuthenticationError.unavailable)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
