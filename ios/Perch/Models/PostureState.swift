//
//  PostureState.swift
//  Perch
//
//  The core posture state machine driven entirely by PostureSource.
//

import SwiftUI

/// Live posture state derived from the PostureSource signal.
enum PostureState: Equatable {
    /// AirPods out — monitoring paused, ring dimmed.
    case idle
    /// Connected and within threshold.
    case monitoringGood
    /// Connected and past threshold; grace timer running.
    case monitoringSlouch
    /// Sustained slouch — nudge has fired.
    case nudging
    /// Monitoring silently (snooze / quiet hours / call / movement).
    case muted

    /// Whether the engine is actively watching posture in this state.
    var isMonitoring: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }

    /// The accent color the live ring should adopt.
    var ringColor: Color {
        switch self {
        case .idle, .muted: return Palette.mist
        case .monitoringGood: return Palette.sage
        case .monitoringSlouch: return Palette.sageSoft
        case .nudging: return Palette.amber
        }
    }

    /// The short, warm status line shown under the ring.
    var statusLine: String {
        switch self {
        case .idle: return "Pop in your AirPods and Perch starts watching."
        case .monitoringGood: return "You're sitting tall."
        case .monitoringSlouch: return "Ease your head back up."
        case .nudging: return "Ease your head back up."
        case .muted: return "Paused for now. Enjoy the moment."
        }
    }
}
