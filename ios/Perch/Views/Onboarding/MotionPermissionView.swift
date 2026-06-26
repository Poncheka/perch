//
//  MotionPermissionView.swift
//  Perch
//
//  A dedicated full-screen step shown AFTER onboarding but BEFORE the paywall
//  and calibration. The real iOS Motion & Fitness permission prompt is ONLY
//  triggered when the user explicitly taps "Allow access" — never before.
//
//  After the check: if supported, proceeds to the next phase. If unsupported or
//  denied, offers recovery paths. The user is never hard-blocked.
//

import SwiftUI
import CoreMotion

struct MotionPermissionView: View {
    let onComplete: () -> Void

    enum Phase: Equatable {
        case priming
        case checking
        case supported
        case unsupported
        case denied
    }

    @State private var phase: Phase = .priming
    @State private var didTapAllow = false
    private let checkTimeout: Double = 2.0

    var body: some View {
        ZStack {
            PerchBackground()

            VStack(spacing: Space.xl) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 46, weight: .thin))
                    .foregroundStyle(iconColor)
                    .frame(height: 64)

                VStack(spacing: Space.l) {
                    Text(titleText)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    Text(subtitleText)
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                VStack(spacing: Space.m) {
                    switch phase {
                    case .priming:
                        PerchPrimaryButton(title: "Allow access") {
                            guard !didTapAllow else { return }
                            didTapAllow = true
                            startCheck()
                        }
                    case .checking:
                        ProgressView()
                            .tint(Palette.sage)
                            .padding(.top, Space.s)
                    case .supported:
                        PerchPrimaryButton(title: "Continue") { onComplete() }
                    case .unsupported:
                        VStack(spacing: Space.m) {
                            PerchPrimaryButton(title: "Try other AirPods") {
                                onComplete()
                            }
                            PerchTextButton(title: "Continue anyway", color: Palette.mist) {
                                onComplete()
                            }
                        }
                    case .denied:
                        VStack(spacing: Space.m) {
                            PerchPrimaryButton(title: "Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            PerchTextButton(title: "Continue anyway", color: Palette.mist) {
                                onComplete()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)
        }
    }

    // MARK: - Derived properties

    private var iconName: String {
        switch phase {
        case .priming: return "figure.walk.motion"
        case .checking: return "airpods"
        case .supported: return "checkmark.seal"
        case .unsupported, .denied: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .supported: return Palette.sage
        case .unsupported, .denied: return Palette.amber
        default: return Palette.sage
        }
    }

    private var titleText: String {
        switch phase {
        case .priming: return "Allow Motion\n& Fitness"
        case .checking: return "Checking your\nAirPods…"
        case .supported: return "You're all set."
        case .unsupported: return "Not supported."
        case .denied: return "Motion access\nis needed."
        }
    }

    private var subtitleText: String {
        switch phase {
        case .priming:
            return "Perch reads the motion sensor in your AirPods to know when you're slouching — even in the background. Your motion data never leaves your phone."
        case .checking:
            return "One moment while we make sure your AirPods can sense motion."
        case .supported:
            return "Your AirPods can sense motion. Perch is ready to keep you upright."
        case .unsupported:
            return "These AirPods don't support motion sensing. Perch needs AirPods (3rd gen), AirPods Pro, AirPods Max, or Beats Fit Pro."
        case .denied:
            return "Perch uses Motion & Fitness to sense your posture. Enable it in Settings, or try different AirPods that support motion sensing."
        }
    }

    // MARK: - Real check logic

    /// Only called after the user explicitly taps "Allow access".
    private func startCheck() {
        phase = .checking
        Task { await runRealCheck() }
    }

    /// Start CMHeadphoneMotionManager — this triggers the OS Motion & Fitness
    /// permission prompt AND verifies motion capability in one step.
    /// The guard on `didTapAllow` ensures this only runs once, on explicit user action.
    private func runRealCheck() async {
        let manager = CMHeadphoneMotionManager()

        guard manager.isDeviceMotionAvailable else {
            withAnimation { phase = .unsupported }
            return
        }

        var sampleArrived = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard !sampleArrived, motion != nil else { return }
                sampleArrived = true
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + checkTimeout) {
                guard !sampleArrived else { return }
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }
        }

        let isDenied: Bool
        if #available(iOS 18.0, *) {
            isDenied = CMHeadphoneMotionManager.authorizationStatus() == .denied
        } else {
            isDenied = !sampleArrived
        }

        withAnimation {
            if sampleArrived {
                phase = .supported
            } else if isDenied {
                phase = .denied
            } else {
                phase = .unsupported
            }
        }
    }
}
