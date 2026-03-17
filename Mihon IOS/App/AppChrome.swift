//
//  AppChrome.swift
//  Mihon IOS
//

import SwiftUI

struct AppChromeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let biometricLockEnabled = true

    var body: some View {
        ZStack {
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

            if model.state.securityPreferences.blurAppSwitcher && scenePhase != .active {
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

            if biometricLockEnabled && model.state.securityPreferences.requireBiometricUnlock && !model.isAppUnlocked && scenePhase == .active {
                BiometricLockView()
                    .transition(.opacity)
            }
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
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1F3E86"), Color(hex: "#0F172A")], startPoint: .topLeading, endPoint: .bottomTrailing)
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
