//
//  ProgressView.swift
//  Perch
//
//  The "Progress" tab. Historical trends only — no live score.
//  Three tappable summary cards, each pushing to a detail screen
//  via NavigationStack. Wrapped in a vertical ScrollView so all
//  sections are reachable with bottom padding to clear the tab bar.
//

import SwiftUI

struct ProgressView: View {
    @Environment(PerchStore.self) private var store

    private var week: [PostureDay] { store.recentDays(7) }
    private var month: [PostureDay] { store.recentDays(30) }
    private var all: [PostureDay] { store.recentDays(90) }

    private var daysWithData: Int {
        week.filter { $0.monitoredSeconds > 0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xxl) {
                    if daysWithData == 0 {
                        emptyState
                    } else {
                        postureScoreCard
                        correctionsCard
                        streakCard
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xxxl + Space.xxl)
            }
            .background(PerchBackground())
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .postureScoreDetail:
                    PostureScoreDetailView()
                case .correctionsDetail:
                    CorrectionsDetailView()
                case .streakDetail:
                    StreakDetailView()
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            Spacer().frame(height: 100)
            Image(systemName: "chart.bar")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Palette.mist)
            Text("Your trend will fill in\nas you use Perch")
                .font(.system(.title3, weight: .regular))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer().frame(height: 200)
        }
    }

    // MARK: - 1) Posture Score Over Time card

    private var postureScoreCard: some View {
        let avg = averagePct(week)
        let trend = weeklyTrendIcon(avg)
        return NavigationLink(value: ProgressRoute.postureScoreDetail) {
            SoftCard {
                VStack(spacing: Space.m) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Eyebrow(text: "Posture Score")
                            Text("\(avg)")
                                .font(.system(size: 42, weight: .thin))
                                .foregroundStyle(Palette.ink)
                                + Text("%")
                                .font(.system(.title3, weight: .thin))
                                .foregroundStyle(Palette.mist)
                            Text("7-day average")
                                .font(.caption)
                                .foregroundStyle(Palette.mist)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Image(systemName: trend.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(trend.color)
                            Text(trend.label)
                                .font(.caption2)
                                .foregroundStyle(Palette.mist)
                        }
                    }
                    if week.count > 1 {
                        Sparkline(days: week, metric: { $0.uprightPct })
                            .frame(height: 44)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2) Corrections Over Time card

    private var correctionsCard: some View {
        let today = store.todayRecord()
        return NavigationLink(value: ProgressRoute.correctionsDetail) {
            SoftCard {
                VStack(spacing: Space.m) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Eyebrow(text: "Corrections")
                            Text("\(today.slouchEvents)")
                                .font(.system(size: 42, weight: .thin))
                                .foregroundStyle(Palette.ink)
                            Text("today")
                                .font(.caption)
                                .foregroundStyle(Palette.mist)
                        }
                        Spacer()
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Palette.sage)
                    }
                    if week.count > 1 {
                        Sparkline(days: week, metric: { Double($0.slouchEvents) })
                            .frame(height: 44)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3) Streak card

    private var streakCard: some View {
        NavigationLink(value: ProgressRoute.streakDetail) {
            SoftCard {
                VStack(spacing: Space.m) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Eyebrow(text: "Streak")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(streakDays)")
                                    .font(.system(size: 42, weight: .thin))
                                    .foregroundStyle(Palette.ink)
                                Text(streakDays == 1 ? "day" : "days")
                                    .font(.system(.title3, weight: .thin))
                                    .foregroundStyle(Palette.mist)
                            }
                            Text("current streak")
                                .font(.caption)
                                .foregroundStyle(Palette.mist)
                        }
                        Spacer()
                        Image(systemName: streakDays > 0 ? "flame.fill" : "flame")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(streakDays > 0 ? Palette.amber : Palette.mist)
                    }
                    // Mini streak week visualization
                    StreakWeekPreview(days: week)
                        .frame(height: 24)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func averagePct(_ days: [PostureDay]) -> Int {
        let active = days.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.map(\.uprightPct).reduce(0, +) / Double(active.count)).rounded())
    }

    private func weeklyTrendIcon(_ avg: Int) -> (icon: String, color: Color, label: String) {
        let lastWeek = averagePct(Array(store.recentDays(14).prefix(7)))
        let delta = avg - lastWeek
        if delta >= 3 { return ("arrow.up.right", Palette.sage, "Improving") }
        if delta <= -3 { return ("arrow.down.right", Palette.amber, "Declining") }
        return ("minus", Palette.mist, "Steady")
    }

    private var streakDays: Int {
        let cal = Calendar.current
        let days = store.recentDays(90).sorted { $0.date > $1.date }
        var count = 0
        var expected = cal.startOfDay(for: Date())
        for day in days {
            guard cal.isDate(day.date, inSameDayAs: expected) else { break }
            if day.monitoredSeconds >= 300 {
                count += 1
                expected = cal.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else { break }
        }
        return count
    }
}

// MARK: - Navigation routes

enum ProgressRoute: Hashable {
    case postureScoreDetail
    case correctionsDetail
    case streakDetail
}

// MARK: - Small sparkline for summary cards

private struct Sparkline: View {
    let days: [PostureDay]
    let metric: (PostureDay) -> Double

    var body: some View {
        let values = days.map(metric)
        let maxVal = values.max() ?? 1
        guard maxVal > 0, values.count > 1 else {
            return AnyView(Color.clear.frame(height: 4))
        }
        return AnyView(
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let stepX = w / CGFloat(values.count - 1)
                let points = values.enumerated().map { i, v in
                    CGPoint(x: CGFloat(i) * stepX, y: h - (h * CGFloat(v / maxVal)))
                }
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for pt in points.dropFirst() { path.addLine(to: pt) }
                }
                .stroke(Palette.sage.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        )
    }
}

// MARK: - Streak week preview dots

private struct StreakWeekPreview: View {
    let days: [PostureDay]
    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days) { day in
                Circle()
                    .fill(day.monitoredSeconds >= 300 ? Palette.sage : Palette.hairline)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
