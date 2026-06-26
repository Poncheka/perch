//
//  PostureScoreDetailView.swift
//  Perch
//
//  Detail screen for Posture Score Over Time. Shows a line chart with
//  selectable ranges (Week / Month / All time), a trend indicator,
//  the Strong/Getting there/Room to grow verdict, and a progress projection
//  framed around Upright % only — no health claims.
//

import SwiftUI

struct PostureScoreDetailView: View {
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

    private var avg: Int { averagePct(days) }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                // Hero number
                VStack(spacing: Space.xs) {
                    Eyebrow(text: "\(selectedRange.rawValue) average")
                    Text("\(avg)")
                        .font(.system(size: 72, weight: .thin))
                        .foregroundStyle(Palette.ink)
                        + Text("%")
                        .font(.system(.title, weight: .thin))
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

                // Line chart
                SoftCard {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Eyebrow(text: "Posture Score")
                        PostureLineChart(days: days)
                            .frame(height: 180)
                    }
                }

                // Trend indicator
                trendCard

                // Verdict card
                verdictCard

                // Progress projection
                projectionCard
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxxl + Space.xxl)
        }
        .background(PerchBackground())
        .navigationTitle("Posture Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Trend card

    private var trendCard: some View {
        let delta = weeklyTrend
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: delta >= 3 ? "arrow.up.right" : (delta <= -3 ? "arrow.down.right" : "minus"))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(delta >= 3 ? Palette.sage : (delta <= -3 ? Palette.amber : Palette.mist))
                VStack(alignment: .leading, spacing: 3) {
                    Text(delta >= 3 ? "Trending up" : (delta <= -3 ? "Trending down" : "Steady"))
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(deltaTrendLabel(delta))
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
            }
        }
    }

    // MARK: - Verdict

    private var verdictCard: some View {
        let bucket = verdictBucket(avg)
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(bucket.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.label)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(bucket.color)
                    Text(bucket.copy)
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .lineSpacing(2)
                }
                Spacer()
            }
        }
    }

    // MARK: - Projection

    private var projectionCard: some View {
        let trend = weeklyTrend
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: projectionIcon(trend))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(projectionTitle(trend))
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(projectionCopy(trend))
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .lineSpacing(2)
                }
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var weeklyTrend: Double {
        let thisWeek = averagePct(store.recentDays(7))
        let lastWeek = averagePct(Array(store.recentDays(14).prefix(7)))
        return Double(thisWeek - lastWeek)
    }

    private func averagePct(_ days: [PostureDay]) -> Int {
        let active = days.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.map(\.uprightPct).reduce(0, +) / Double(active.count)).rounded())
    }

    private func deltaTrendLabel(_ delta: Double) -> String {
        if delta >= 3 { return "Your posture score has improved \(Int(delta))% compared to last week." }
        if delta <= -3 { return "Your score dipped \(Int(-delta))% — a few mindful moments and you'll be back." }
        return "Consistency is the goal — no big swings needed."
    }

    private struct VerdictBucket {
        let label: String
        let icon: String
        let color: Color
        let copy: String
    }

    private func verdictBucket(_ avg: Int) -> VerdictBucket {
        switch avg {
        case 80...100:
            return VerdictBucket(label: "Strong", icon: "star", color: Palette.sage,
                copy: "You're holding steady in the strong band. Your posture habits are serving you well.")
        case 60..<80:
            return VerdictBucket(label: "Getting there", icon: "leaf", color: Palette.amber,
                copy: "You're making real progress. A few more mindful moments each day and you'll be in the strong zone.")
        default:
            return VerdictBucket(label: "Room to grow", icon: "sparkles", color: Palette.amber,
                copy: "Every upright minute counts. Perch is here to gently remind you — small shifts add up fast.")
        }
    }

    private func projectionIcon(_ trend: Double) -> String {
        if trend > 0 { return "arrow.up.forward" }
        if trend < 0 { return "leaf" }
        return "equal"
    }

    private func projectionTitle(_ trend: Double) -> String {
        let weeks = projectedWeeks(trend)
        if trend > 0, let w = weeks { return "At this pace, ~\(w) weeks to consistently strong" }
        if trend < 0 { return "Gentle encouragement" }
        return "Steady as you go"
    }

    private func projectionCopy(_ trend: Double) -> String {
        if trend > 0, projectedWeeks(trend) != nil {
            return "Your Posture Score is trending up. Keep at it — you're building a lasting habit."
        }
        if trend < 0 {
            return "Your score dipped a bit this week. No worries — Perch will keep nudging you gently. Every day is a fresh start."
        }
        return "Your posture is holding steady week over week. Consistency is exactly the goal."
    }

    private func projectedWeeks(_ trend: Double) -> Int? {
        guard trend > 0 else { return nil }
        let current = Double(avg)
        guard current < 80 else { return nil }
        let delta = max(trend, 0.5)
        return Int(((80 - current) / delta).rounded(.up))
    }
}

// MARK: - Line chart for Posture Score

private struct PostureLineChart: View {
    let days: [PostureDay]

    var body: some View {
        let active = days.enumerated().filter { $0.element.monitoredSeconds > 0 }
        guard active.count > 1 else {
            return AnyView(
                Text("Not enough data for this range.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            )
        }
        return AnyView(
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let all = active.map { $0.element }
                let stepX = all.count > 1 ? w / CGFloat(all.count - 1) : w
                let points = all.enumerated().map { i, day in
                    CGPoint(x: CGFloat(i) * stepX, y: h - (h * CGFloat(day.uprightPct / 100)))
                }

                ZStack(alignment: .topLeading) {
                    // Grid lines
                    ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h * (1 - ratio)))
                            path.addLine(to: CGPoint(x: w, y: h * (1 - ratio)))
                        }
                        .stroke(Palette.hairline, lineWidth: 0.5)
                    }

                    // Fill
                    if points.count > 1 {
                        Path { path in
                            path.move(to: points[0])
                            for pt in points.dropFirst() { path.addLine(to: pt) }
                            path.addLine(to: CGPoint(x: points.last!.x, y: h))
                            path.addLine(to: CGPoint(x: points[0].x, y: h))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Palette.sage.opacity(0.15), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            path.move(to: points[0])
                            for pt in points.dropFirst() { path.addLine(to: pt) }
                        }
                        .stroke(Palette.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        )
    }
}
