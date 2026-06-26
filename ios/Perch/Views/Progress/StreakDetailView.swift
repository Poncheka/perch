//
//  StreakDetailView.swift
//  Perch
//
//  Detail screen for Streak. Shows a calendar-style view of active days,
//  the current and longest streak, and a cumulative Posture Score chart
//  so the user can see whether they're trending better or worse over time.
//

import SwiftUI

struct StreakDetailView: View {
    @Environment(PerchStore.self) private var store

    private let cal = Calendar.current

    private var days: [PostureDay] { store.recentDays(90).sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                // Streak hero
                streakHero
                
                // Calendar view of recent days
                calendarCard
                
                // Longest streak card
                longestStreakCard
                
                // Cumulative Score chart
                cumulativeScoreCard
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxxl + Space.xxl)
        }
        .background(PerchBackground())
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Streak hero
    
    private var streakHero: some View {
        let current = currentStreak
        return VStack(spacing: Space.xs) {
            Image(systemName: current > 0 ? "flame.fill" : "flame")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(current > 0 ? Palette.amber : Palette.mist)
            Text("\(current)")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(Palette.ink)
            Text(current == 1 ? "day streak" : "days streak")
                .font(.callout)
                .foregroundStyle(Palette.mist)
        }
        .padding(.top, Space.l)
    }
    
    // MARK: - Calendar card
    
    private var calendarCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.l) {
                Eyebrow(text: "Recent days")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                    // Day headers
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.mist)
                            .frame(maxWidth: .infinity)
                    }
                    // Last ~5 weeks of days
                    ForEach(calendarDays(), id: \.self) { day in
                        calendarDayCell(day)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func calendarDayCell(_ day: CalendarDay) -> some View {
        if let date = day.date {
            let hasData = dayWithData(for: date) != nil
            let isToday = cal.isDateInToday(date)
            let isFuture = date > Date()
            
            ZStack {
                if isToday {
                    Circle()
                        .stroke(Palette.sage, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
                if hasData {
                    Circle()
                        .fill(Palette.sage.opacity(0.3))
                        .frame(width: 24, height: 24)
                }
                if isFuture {
                    Text(cal.component(.day, from: date).description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Palette.hairline)
                } else {
                    Text(cal.component(.day, from: date).description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(hasData ? Palette.ink : Palette.mist)
                }
            }
            .frame(height: 32)
        } else {
            Color.clear.frame(height: 32)
        }
    }
    
    private func dayWithData(for date: Date) -> PostureDay? {
        days.first(where: { cal.isDate($0.date, inSameDayAs: date) && $0.monitoredSeconds >= 300 })
    }
    
    // MARK: - Longest streak card
    
    private var longestStreakCard: some View {
        let longest = longestStreak
        return SoftCard {
            HStack(spacing: Space.l) {
                Image(systemName: "trophy")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(longest > 0 ? Palette.amber : Palette.mist)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Longest streak")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(longest > 0 ? "\(longest) \(longest == 1 ? "day" : "days")" : "Not yet — keep at it")
                        .font(.title3)
                        .foregroundStyle(Palette.inkSoft)
                    Text(longest > 0 ? "Your personal best so far." : "Your first streak is waiting for you.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Cumulative Score chart
    
    private var cumulativeScoreCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.l) {
                Eyebrow(text: "Cumulative Posture Score")
                CumulativeScoreChart(days: days.reversed())
                    .frame(height: 160)
                Text("Each point is your Posture Score for that day — higher is better.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
                    .lineSpacing(2)
            }
        }
    }
    
    // MARK: - Compute streaks
    
    private var currentStreak: Int {
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
    
    private var longestStreak: Int {
        var longest = 0
        var current = 0
        // Process days in chronological order (oldest first)
        let sorted = days.sorted { $0.date < $1.date }
        var prev: Date?
        for day in sorted {
            if let prev = prev {
                let diff = cal.dateComponents([.day], from: prev, to: day.date).day ?? 2
                if diff == 1 && day.monitoredSeconds >= 300 {
                    current += 1
                } else {
                    longest = max(longest, current)
                    current = day.monitoredSeconds >= 300 ? 1 : 0
                }
            } else {
                current = day.monitoredSeconds >= 300 ? 1 : 0
            }
            prev = day.date
        }
        longest = max(longest, current)
        return longest
    }
    
    // MARK: - Calendar data
    
    private struct CalendarDay: Hashable {
        let date: Date?
    }
    
    private func calendarDays() -> [CalendarDay] {
        let today = cal.startOfDay(for: Date())
        // Go back 5 weeks and find the start of that week (Sunday)
        let start = cal.date(byAdding: .day, value: -34, to: today) ?? today
        let weekday = cal.component(.weekday, from: start) - 1 // 0 = Sunday
        let gridStart = cal.date(byAdding: .day, value: -weekday, to: start) ?? start
        
        var result: [CalendarDay] = []
        for i in 0..<42 { // 6 weeks of 7 days
            let date = cal.date(byAdding: .day, value: i, to: gridStart)
            result.append(CalendarDay(date: date))
        }
        return result
    }
}

// MARK: - Cumulative Score line chart

private struct CumulativeScoreChart: View {
    let days: [PostureDay]
    
    var body: some View {
        let active = days.enumerated().filter { $0.element.monitoredSeconds > 0 }
        guard active.count > 1 else {
            return AnyView(
                Text("Keep tracking — your trend will appear here.")
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
                
                ZStack {
                    // Fill
                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: h))
                        path.addLine(to: CGPoint(x: points[0].x, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Palette.sage.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line
                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(Palette.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        )
    }
}
