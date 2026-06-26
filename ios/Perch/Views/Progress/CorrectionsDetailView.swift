//
//  CorrectionsDetailView.swift
//  Perch
//
//  Detail screen for Corrections Over Time. Shows a bar chart of
//  corrections per day with selectable ranges (Week / Month / All),
//  a trend indicator, and one plain-language summary line.
//

import SwiftUI

struct CorrectionsDetailView: View {
    @Environment(PerchStore.self) private var store

    enum Range: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case all = "All time"
    }
    @State private var selectedRange: Range = .week

    private var days: [PostureDay] {
        switch selectedRange {
        case .week: return store.recentDays(7)
        case .month: return store.recentDays(30)
        case .all: return store.recentDays(90)
        }
    }

    private var totalCorrections: Int {
        days.reduce(0) { $0 + $1.slouchEvents }
    }

    private var avgPerDay: Double {
        let active = days.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return Double(totalCorrections) / Double(active.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                // Hero number
                VStack(spacing: Space.xs) {
                    Eyebrow(text: "\(selectedRange.rawValue) corrections")
                    Text("\(totalCorrections)")
                        .font(.system(size: 72, weight: .thin))
                        .foregroundStyle(Palette.ink)
                    Text("\(String(format: "%.1f", avgPerDay)) per day on average")
                        .font(.callout)
                        .foregroundStyle(Palette.mist)
                }
                .padding(.top, Space.l)

                // Range picker
                Picker("Range", selection: $selectedRange) {
                    ForEach(Range.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.xl)

                // Bar chart
                SoftCard {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Eyebrow(text: "Corrections per day")
                        CorrectionsBarChart(days: days)
                            .frame(height: 180)
                    }
                }

                // Trend indicator
                trendCard

                // Plain-language summary
                summaryCard
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxxl + Space.xxl)
        }
        .background(PerchBackground())
        .navigationTitle("Corrections")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Trend card

    private var trendCard: some View {
        let delta = correctionsTrend
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: delta < 0 ? "arrow.down.right" : (delta > 0 ? "arrow.up.right" : "minus"))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(delta < 0 ? Palette.sage : (delta > 0 ? Palette.amber : Palette.mist))
                VStack(alignment: .leading, spacing: 3) {
                    Text(delta < 0 ? "Fewer corrections" : (delta > 0 ? "More corrections" : "Steady"))
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(correctionsTrendLabel(delta))
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.sage)
                Text(summaryText)
                    .font(.system(.callout, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
            }
        }
    }

    // MARK: - Helpers

    private var correctionsTrend: Int {
        let thisWeek = store.recentDays(7).reduce(0) { $0 + $1.slouchEvents }
        let lastWeek = Array(store.recentDays(14).prefix(7)).reduce(0) { $0 + $1.slouchEvents }
        return thisWeek - lastWeek
    }

    private func correctionsTrendLabel(_ delta: Int) -> String {
        if delta < 0 {
            return "\(abs(delta)) fewer slouches than last week. That's real progress."
        }
        if delta > 0 {
            return "\(delta) more slouches than last week. Happens to everyone — tomorrow is a fresh day."
        }
        return "About the same as last week. Steady and aware."
    }

    private var summaryText: String {
        let trend = correctionsTrend
        if trend < 0 {
            return "Fewer slouches than last week. Your body is learning to hold itself upright — that's the whole point."
        } else if trend > 0 {
            return "A few more corrections this week. Nothing to stress over — every nudge is a micro-adjustment toward better posture."
        }
        return "Your correction count is steady. Perch is keeping you gently aware — that quiet awareness is the goal."
    }
}

// MARK: - Bar chart for corrections

private struct CorrectionsBarChart: View {
    let days: [PostureDay]

    var body: some View {
        let maxCorrections = days.map(\.slouchEvents).max() ?? 1
        guard maxCorrections > 0 else {
            return AnyView(
                Text("No corrections recorded for this range.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            )
        }
        return AnyView(
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barWidth = max(6, (w / CGFloat(days.count)) - 8)
                let labelH: CGFloat = 20

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.monitoredSeconds > 0 ? Palette.sageSoft : Palette.hairline)
                                .frame(
                                    width: barWidth,
                                    height: max(4, (h - labelH) * CGFloat(day.slouchEvents) / CGFloat(max(maxCorrections, 1)))
                                )
                            Text(weekdayLabel(day.date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.mist)
                                .frame(height: labelH)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        )
    }

    private func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}
