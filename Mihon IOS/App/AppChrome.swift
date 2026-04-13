//
//  AppChrome.swift
//  Mihon IOS
//

import SwiftUI

struct AppChromeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let biometricLockEnabled = true

    // Fix #5: Alert state lives here (stable parent) to avoid detached-view warnings
    // when BiometricLockView is conditionally removed from the hierarchy.
    @State private var showBiometricRetryAlert = false

    private var isPrivacyOverlayActive: Bool {
        model.state.securityPreferences.blurAppSwitcher && scenePhase != .active
    }

    private var isBiometricLockActive: Bool {
        biometricLockEnabled
            && model.state.securityPreferences.requireBiometricUnlock
            && !model.isAppUnlocked
            && scenePhase == .active
    }

    var body: some View {
        ZStack {
            // Main content — hidden from VoiceOver when locked/blurred (Fix #1)
            Group {
                switch model.bootState {
                case .launching:
                    LaunchView()
                case .failed(let message):
                    CrashView(message: message)
                case .ready:
                    RootTabView()
                        .sheet(isPresented: onboardingBinding) {
                            OnboardingView()
                        }
                        .sheet(isPresented: $model.releaseNotesPresented) {
                            ReleaseNotesView()
                        }
                }
            }
            .accessibilityHidden(isPrivacyOverlayActive || isBiometricLockActive)

            // Privacy blur overlay (app switcher)
            if isPrivacyOverlayActive {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                    Text("Mihon Hidden")
                        .font(.headline)
                }
                .foregroundStyle(.primary)
            }

            // Biometric lock overlay
            if isBiometricLockActive {
                BiometricLockView(
                    onBiometricFailure: {
                        showBiometricRetryAlert = true
                    }
                )
                .transition(.opacity)
            }
        }
        // Fix #5: Alert is attached here (always-live parent) — safe across scene-phase transitions
        .alert("Face ID Failed", isPresented: $showBiometricRetryAlert) {
            Button("Retry") {
                Task { await model.requestBiometricUnlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.biometricErrorMessage ?? "Authentication failed. Please try again.")
        }
        .onAppear {
            if biometricLockEnabled && model.state.securityPreferences.requireBiometricUnlock {
                model.lockAppIfNeeded()
                Task { await model.unlockAppIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if biometricLockEnabled {
                    Task { await model.unlockAppIfNeeded() }
                }
            case .inactive:
                break
            case .background:
                if biometricLockEnabled {
                    model.lockAppIfNeeded()
                }
            @unknown default:
                break
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !model.state.onboardingCompleted },
            set: { newValue in
                if !newValue {
                    model.markOnboardingCompleted()
                }
            }
        )
    }
}

private struct BiometricLockView: View {
    @EnvironmentObject private var model: AppModel
    /// Callback to the stable parent view that should present the retry alert.
    /// Fix #5: Alert presentation is delegated upward so it isn't detached
    /// when this view is removed from the ZStack during scene-phase transitions.
    let onBiometricFailure: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Mihon Locked")
                    .font(.title3.weight(.semibold))

                Text(model.biometricErrorMessage ?? "Unlock with Face ID to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("Unlock") {
                    Task { await model.requestBiometricUnlock() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
        }
        .onChange(of: model.biometricErrorMessage) { _, newValue in
            guard let message = newValue, !message.isEmpty else { return }
            onBiometricFailure()
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            // Fix #7: Use semantic Asset Catalog colors so light/dark/high-contrast
            // appearances are handled automatically instead of hardcoded hex values.
            LinearGradient(
                colors: [
                    Color("LaunchGradientTop"),
                    Color("LaunchGradientBottom")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "book.pages")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                Text("Loading Mihon for iOS")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private struct CrashView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Unable to Launch",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Welcome") {
                    Label("Native iOS tab shell for Library, Updates, History, Browse, and More.", systemImage: "square.grid.2x2")
                    Label("Source catalog replaces Android extension APK installation.", systemImage: "shippingbox")
                    Label("Reader progress, notes, trackers, and source repos are persisted locally.", systemImage: "externaldrive")
                }

                Section("Initial Setup") {
                    LabeledContent("Language", value: model.currentLanguageLabel)
                    LabeledContent("Default Source Repo", value: model.state.sourceRepos.first ?? "None")
                }
            }
            .navigationTitle("Welcome to Mihon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") {
                        model.markOnboardingCompleted()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("This Build") {
                    Label("Expanded page surface for Library, Browse, Reader, Tracking, Backup, and Migration.", systemImage: "sparkles")
                    Label("Native settings hierarchy and source catalog management.", systemImage: "gearshape.2")
                    Label("Richer reader preferences with orientation and color filters.", systemImage: "text.page")
                }
            }
            .navigationTitle("What's New")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
