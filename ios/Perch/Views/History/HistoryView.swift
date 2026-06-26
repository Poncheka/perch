//
//  HistoryView.swift
//  Perch
//
//  The "Progress" tab. All analytics live here: today's Posture Score hero,
//  Corrections and Streak cards, verdict card, 7-day and 30-day trends,
//  average upright stretch, and progress projection.
//  Oura-style, sparse, calm — framed around Upright % only, no health claims.
//

import SwiftUI

struct HistoryView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureEngine.self) private var engine

    private var week: [PostureDay] { store.recentDays(7) }
    private var month: [PostureDay] { store.recentDays(30) }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                hero
                statCards
                streakCard
                verdictCard
                trendCard(title: "Last 7 days", days: week, asBars: true)
                correctionsTrendCard
                trendCard(title: "Last 30 days", days: month, asBars: false)
                averageStretchCard
                progressCard
                insight
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
        }
        .background(PerchBackground())
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Space.s) {
            Eyebrow(text: "Upright score")
            Text("\(Int(engine.uprightPct.rounded()))")
                .font(.system(size: 84, weight: .thin))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text("Posture Score today")
                .font(.footnote)
                .foregroundStyle(Palette.mist)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.l)
    }

    // MARK: - Stat cards (Corrections + Streak)

    private var statCards: some View {
        HStack(spacing: Space.m) {
            statCard(
                icon: "arrow.triangle.swap",
                value: "\(todayRecord.slouchEvents)",
                label: "Corrections"
            )
            statCard(
                icon: "flame",
                value: "\(streakDays)",
                label: "Streak"
            )
        }
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Palette.sage)
            Text(value)
                .font(.system(.title2, weight: .thin))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.mist)
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private var todayRecord: PostureDay {
        store.todayRecord()
    }

    // MARK: - Streak card

    private var streakCard: some View {
        SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: "flame")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(streakDays > 0 ? Palette.amber : Palette.mist)
                VStack(alignment: .leading, spacing: 3) {
                    if streakDays > 0 {
                        Text("\(streakDays)-day streak")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    } else {
                        Text("No streak yet")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    Text("Keep your AirPods in daily to build a streak.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
            }
        }
    }

    /// Consecutive days (backward from today) with at least ~5 min monitored.
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
            } else {
                break
            }
        }
        return count
    }

    // MARK: - Verdict card

    private var verdictCard: some View {
        let avg = averagePct(week)
        let bucket = verdictBucket(avg)
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(bucket.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.label)
                        .font(.system(.title3, weight: .semibold))
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

    private struct VerdictBucket {
        let label: String
        let icon: String
        let color: Color
        let copy: String
    }

    private func verdictBucket(_ avg: Int) -> VerdictBucket {
        switch avg {
        case 80...100:
            return VerdictBucket(
                label: "Strong",
                icon: "star",
                color: Palette.sage,
                copy: "You're holding steady in the strong band. Your posture habits are serving you well."
            )
        case 60..<80:
            return VerdictBucket(
                label: "Getting there",
                icon: "leaf",
                color: Palette.amber,
                copy: "You're making real progress. A few more mindful moments each day and you'll be in the strong zone."
            )
        default:
            return VerdictBucket(
                label: "Room to grow",
                icon: "sparkles",
                color: Palette.amber,
                copy: "Every upright minute counts. Perch is here to gently remind you — small shifts add up fast."
            )
        }
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

    // MARK: - Corrections trend card

    private var correctionsTrendCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Eyebrow(text: "Corrections")
                    Spacer()
                    Text("\(totalCorrectionsThisWeek) total")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(Palette.mist)
                }
                CorrectionsBarTrend(days: week)
                    .frame(height: 90)
            }
        }
    }

    private var totalCorrectionsThisWeek: Int {
        week.reduce(0) { $0 + $1.slouchEvents }
    }

    // MARK: - Average upright stretch

    private var averageStretchCard: some View {
        SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Average upright stretch")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(averageStretchText)
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .lineSpacing(2)
                }
                Spacer()
            }
        }
    }

    private var averageStretchText: String {
        let active = week.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return "Not enough data yet — keep your AirPods in." }
        let totalUpright = active.reduce(0.0) { $0 + $1.uprightSeconds }
        let totalCorrections = active.reduce(0) { $0 + $1.slouchEvents }
        guard totalCorrections > 0 else {
            let stretch = Int(totalUpright / 60)
            return stretch > 0
                ? "You held good posture ~\(stretch) min at a stretch on average this week."
                : "Not enough data yet for a meaningful average."
        }
        let avgStretch = totalUpright / Double(totalCorrections) / 60
        return avgStretch >= 1
            ? "You held good posture ~\(Int(avgStretch.rounded())) min at a stretch on average this week."
            : "Short but steady stretches this week — that still adds up."
    }

    private func averagePct(_ days: [PostureDay]) -> Int {
        let active = days.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.map(\.uprightPct).reduce(0, +) / Double(active.count)).rounded())
    }

    // MARK: - Progress projection

    private var progressCard: some View {
        SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: projectionIcon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(projectionTitle)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(projectionCopy)
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .lineSpacing(2)
                }
                Spacer()
            }
        }
    }

    private var projectionIcon: String {
        if weeklyTrend > 0 { return "arrow.up.forward" }
        if weeklyTrend < 0 { return "leaf" }
        return "equal"
    }

    private var projectionTitle: String {
        if weeklyTrend > 0, let weeks = projectedWeeks {
            return "At this pace, ~\(weeks) weeks to consistently strong"
        }
        if weeklyTrend < 0 {
            return "Gentle encouragement"
        }
        return "Steady as you go"
    }

    private var projectionCopy: String {
        if weeklyTrend > 0, projectedWeeks != nil {
            return "Your Posture Score is trending up. Keep at it — you're building a lasting habit."
        }
        if weeklyTrend < 0 {
            return "Your score dipped a bit this week. No worries — Perch will keep nudging you gently. Every day is a fresh start."
        }
        return "Your posture is holding steady week over week. Consistency is exactly the goal — no big swings needed."
    }

    private var weeklyTrend: Double {
        let thisWeek = averagePct(store.recentDays(7))
        let lastWeek = averagePct(Array(store.recentDays(14).prefix(7)))
        return Double(thisWeek - lastWeek)
    }

    private var projectedWeeks: Int? {
        guard weeklyTrend > 0 else { return nil }
        let current = Double(averagePct(week))
        guard current < 80 else { return nil }
        let delta = max(weeklyTrend, 0.5)
        let weeks = (80 - current) / delta
        return Int(weeks.rounded(.up))
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

// MARK: - Corrections bar trend (7-day, slouch events per day)

private struct CorrectionsBarTrend: View {
    let days: [PostureDay]

    var body: some View {
        let maxCorrections = days.map(\.slouchEvents).max() ?? 1
        GeometryReader { geo in
            let maxBar = geo.size.height - 22
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.monitoredSeconds > 0 ? Palette.amberSoft : Palette.hairline)
                            .frame(height: max(4, maxBar * CGFloat(day.slouchEvents) / CGFloat(max(maxCorrections, 1))))
                        Text("\(day.slouchEvents)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.mist)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
