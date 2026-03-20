//
//  AppModel+Security.swift
//  Mihon IOS
//

import Foundation

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

        switch await biometricAuthenticator.evaluate(reason: "Unlock Mihon to continue reading and browsing.") {
        case .success:
            isAppUnlocked = true
            biometricErrorMessage = nil
        case .failure(let error):
            isAppUnlocked = false
            biometricErrorMessage = error.localizedDescription
            appendDiagnostic(kind: .security, title: "Biometric Unlock Failed", message: error.localizedDescription, metadata: [:])
        }
    }
}
