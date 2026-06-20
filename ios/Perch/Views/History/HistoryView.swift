//
//  HistoryView.swift
//  Perch
//
//  Oura-style, sparse history: today's upright % as a hero, a minimal 7-day and
//  30-day trend, and one encouraging plain-language insight line.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(PostureEngine.self) private var engine

    private var week: [PostureDay] { store.recentDays(7) }
    private var month: [PostureDay] { store.recentDays(30) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xxl) {
                    hero
                    trendCard(title: "Last 7 days", days: week, asBars: true)
                    trendCard(title: "Last 30 days", days: month, asBars: false)
                    insight
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
            }
            .background(PerchBackground())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Space.s) {
            Eyebrow(text: "Upright Today")
            Text("\(Int(engine.uprightPct.rounded()))")
                .font(.system(size: 84, weight: .thin))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text("percent of monitored time")
                .font(.footnote)
                .foregroundStyle(Palette.mist)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.l)
    }

    // MARK: - Trend cards

    private func trendCard(title: String, days: [PostureDay], asBars: Bool) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Eyebrow(text: title)
                    Spacer()
                    Text("avg \(averagePct(days))%")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(Palette.sage)
                }
                if asBars {
                    BarTrend(days: days)
                        .frame(height: 120)
                } else {
                    LineTrend(days: days)
                        .frame(height: 110)
                }
            }
        }
    }

    private func averagePct(_ days: [PostureDay]) -> Int {
        let active = days.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.map(\.uprightPct).reduce(0, +) / Double(active.count)).rounded())
    }

    // MARK: - Insight

    private var insight: some View {
        SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: "leaf")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.sage)
                Text(insightText)
                    .font(.system(.callout, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
            }
        }
    }

    private var insightText: String {
        let thisWeek = averagePct(store.recentDays(7))
        let prior = averagePct(Array(store.recentDays(14).prefix(7)))
        guard prior > 0 else {
            return "Perch is learning your days. Keep your AirPods in and your trend will fill in here."
        }
        let delta = thisWeek - prior
        if delta > 0 {
            return "You've been \(delta)% more upright than last week. Lovely, steady progress."
        } else if delta < 0 {
            return "A little more forward than last week — no worries. Small, gentle corrections add up."
        }
        return "You're holding steady with last week. Consistency is exactly the goal."
    }
}

// MARK: - Slim bar trend (7-day)

private struct BarTrend: View {
    let days: [PostureDay]

    var body: some View {
        GeometryReader { geo in
            let maxBar = geo.size.height - 22
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.monitoredSeconds > 0 ? Palette.sage : Palette.hairline)
                            .frame(height: max(4, maxBar * CGFloat(day.uprightPct / 100)))
                        Text(weekday(day.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.mist)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}

// MARK: - Soft line trend (30-day)

private struct LineTrend: View {
    let days: [PostureDay]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = positions(in: CGSize(width: w, height: h))
            ZStack {
                if points.count > 1 {
                    // Soft fill under the line.
                    fillPath(points: points, height: h)
                        .fill(
                            LinearGradient(
                                colors: [Palette.sage.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    linePath(points: points)
                        .stroke(Palette.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        guard !days.isEmpty else { return [] }
        let stepX = days.count > 1 ? size.width / CGFloat(days.count - 1) : size.width
        return days.enumerated().map { index, day in
            let x = CGFloat(index) * stepX
            let y = size.height - (size.height * CGFloat(day.uprightPct / 100))
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func fillPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(points: points)
        if let last = points.last, let first = points.first {
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: first.x, y: height))
            path.closeSubpath()
        }
        return path
    }
}
