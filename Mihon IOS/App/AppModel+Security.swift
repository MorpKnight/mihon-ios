//
//  AppModel+Security.swift
//  Mihon IOS
//

import Foundation
import LocalAuthentication

extension AppModel {
    func lockAppIfNeeded() {
        guard Self.biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock else { return }
        isAppUnlocked = false
        biometricErrorMessage = nil
    }

    func unlockAppIfNeeded() async {
        guard Self.biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock, !isAppUnlocked else { return }
        await requestBiometricUnlock()
    }

    func requestBiometricUnlock() async {
        guard Self.biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock else {
            isAppUnlocked = true
            biometricErrorMessage = nil
            return
        }

        biometricErrorMessage = nil
        switch await biometricAuthenticator.evaluate(reason: "Unlock Mihon to continue reading and browsing.") {
        case .success:
            isAppUnlocked = true
            biometricErrorMessage = nil
        case .failure(let error):
            isAppUnlocked = false
            if let message = userFacingBiometricMessage(for: error) {
                biometricErrorMessage = message
                appendDiagnostic(
                    kind: .security,
                    severity: .critical,
                    title: "Biometric Unlock Failed",
                    message: message,
                    errorCode: DiagnosticErrorCode.secBiometricUnlockFailed.rawValue,
                    module: "Security",
                    resolutionHint: "Authenticate with your device passcode, then retry Face ID unlock.",
                    metadata: [:]
                )
            }
        }
    }

    private func userFacingBiometricMessage(for error: Error) -> String? {
        if let laError = error as? LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return nil
            case .biometryLockout:
                return "Face ID is temporarily locked. Authenticate with passcode, then try again."
            case .biometryNotAvailable:
                return "Face ID is not available on this device."
            case .biometryNotEnrolled:
                return "Face ID is not set up. Please enroll Face ID in Settings."
            default:
                return laError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
