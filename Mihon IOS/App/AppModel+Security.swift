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

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            biometricErrorMessage = authError?.localizedDescription ?? "Face ID is not available on this device."
            appendDiagnostic(kind: .security, title: "Biometric Unavailable", message: biometricErrorMessage ?? "Face ID is not available.", metadata: [:])
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Mihon to continue reading and browsing."
            )
            if success {
                isAppUnlocked = true
                biometricErrorMessage = nil
            }
        } catch {
            biometricErrorMessage = error.localizedDescription
            appendDiagnostic(kind: .security, title: "Biometric Unlock Failed", message: error.localizedDescription, metadata: [:])
        }
    }
}

