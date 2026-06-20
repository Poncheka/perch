//
//  Components.swift
//  Perch
//
//  Small reusable view building blocks shared across screens.
//

import SwiftUI

/// A small uppercase, tracked, muted label for the clinical feel.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.mist

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .default, weight: .semibold))
            .tracking(2.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A soft rounded surface card with a low, diffuse shadow.
struct SoftCard<Content: View>: View {
    var padding: CGFloat = Space.xl
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.surface)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

/// Primary, calm, full-width action button.
struct PerchPrimaryButton: View {
    let title: String
    var fill: Color = Palette.sage
    var foreground: Color = Palette.cream
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(fill)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// A quiet text-style button for tertiary actions.
struct PerchTextButton: View {
    let title: String
    var color: Color = Palette.sage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .medium))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// Warm full-screen background with a faint sage-to-paper gradient wash.
struct PerchBackground: View {
    var body: some View {
        ZStack {
            Palette.paper
            LinearGradient(
                colors: [Palette.sage.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
