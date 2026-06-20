//
//  PaywallView.swift
//  Perch
//
//  Honest, calm paywall: 14-day free trial with everything unlocked, then a
//  choice of plan. No dark patterns — clear about the trial and the reminder.
//

import SwiftUI

struct PaywallView: View {
    enum Context { case onboarding, manage }

    let context: Context

    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(Billing.self) private var billing

    @State private var selected: Plan = .annual
    @State private var working = false

    var body: some View {
        ZStack {
            PerchBackground()
            ScrollView {
                VStack(spacing: Space.xl) {
                    header
                    benefits
                    planOptions
                    Spacer(minLength: Space.s)
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xxl)
                .padding(.bottom, 220)
            }
            footer
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "figure.seated.side")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Palette.sage)
            Text("14 days, fully\nunlocked. On us.")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text("Try every part of Perch free for 14 days. We'll remind you before your trial ends — cancel anytime.")
                .font(.body)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            benefitRow("Effortless background monitoring")
            benefitRow("Gentle, non-startling nudges")
            benefitRow("Daily and 30-day posture trends")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.sage)
            Text(text)
                .font(.system(.callout, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    // MARK: - Plans

    private var planOptions: some View {
        VStack(spacing: Space.m) {
            planRow(.annual, subtitle: "$19.99 per year", badge: "Best value")
            planRow(.monthly, subtitle: "$2.99 per month", badge: nil)
            planRow(.lifetime, subtitle: "$29.99 one-time", badge: nil)
        }
    }

    private func planRow(_ plan: Plan, subtitle: String, badge: String?) -> some View {
        let isSelected = selected == plan
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = plan }
        } label: {
            HStack(spacing: Space.l) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Palette.sage : Palette.mist)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(.caption, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.cream)
                        .padding(.vertical, 5)
                        .padding(.horizontal, Space.m)
                        .background(Capsule().fill(Palette.sage))
                }
            }
            .padding(Space.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .stroke(isSelected ? Palette.sage : Palette.hairline, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Space.m) {
            PerchPrimaryButton(title: working ? "Just a moment…" : "Start 14-day free trial") {
                Task { await startTrial() }
            }
            .disabled(working)

            HStack(spacing: Space.l) {
                PerchTextButton(title: "Restore purchases", color: Palette.mist) {
                    Task { await restore() }
                }
                Text("·").foregroundStyle(Palette.mist)
                Text("Then \(selected.priceLabel)")
                    .font(.footnote)
                    .foregroundStyle(Palette.mist)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Palette.paper.opacity(0), Palette.paper], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var closeButton: some View {
        Group {
            if context == .manage || store.subscription.isUnlocked {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.mist)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Space.s)
                .padding(.top, Space.s)
            }
        }
    }

    // MARK: - Actions

    private func startTrial() async {
        working = true
        if let sub = await billing.startFreeTrial() {
            store.applySubscription(sub)
        }
        working = false
        dismiss()
    }

    private func restore() async {
        working = true
        if let sub = await billing.restore() {
            store.applySubscription(sub)
        }
        working = false
    }
}
