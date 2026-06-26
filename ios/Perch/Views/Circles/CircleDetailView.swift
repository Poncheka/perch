//
//  CircleDetailView.swift
//  Perch
//
//  Pillar detail: member leaderboard (ranked by Posture Score, crown on leader,
//  fairness rule for thin data), stacked 7-day comparison chart, and member
//  management. Calm and supportive tone — the crown is a fun reward, not a
//  judgment.
//

import SwiftUI

struct CircleDetailView: View {
    let circle: CircleModel

    @Environment(PerchStore.self) private var store
    @Environment(PostureEngine.self) private var engine
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db
    @Environment(\.dismiss) private var dismiss

    @State private var members: [CircleMember] = []
    @State private var summaries: [CircleMemberSummary] = []
    @State private var showDeleteConfirm = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var currentCircle: CircleModel

    private var isOwner: Bool { currentCircle.ownerId == (auth.userId ?? "") }
    private var currentUserId: String { auth.userId ?? "" }

    init(circle: CircleModel) {
        self.circle = circle
        _currentCircle = State(initialValue: circle)
        _renameText = State(initialValue: circle.name)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                // Header
                VStack(spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        Text(currentCircle.name)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Palette.ink)

                        if isOwner {
                            Button {
                                renameText = currentCircle.name
                                showRename = true
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Palette.mist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Supportive, not competitive. The crown is just for fun.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)

                // Invite code section
                VStack(spacing: Space.xs) {
                    Eyebrow(text: "Invite code")
                    Text(currentCircle.inviteCode)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Palette.sage)
                        .tracking(4)
                }
                .padding(.top, Space.s)

                // Share button
                PerchTextButton(title: "Invite a friend", color: Palette.sage) {
                    let av = UIActivityViewController(
                        activityItems: [
                            "Join my Perch pillar \"\(currentCircle.name)\"! Use invite code \(currentCircle.inviteCode) or download Perch: https://getperch.app/join?code=\(currentCircle.inviteCode)"
                        ],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(av, animated: true)
                    }
                }

                Divider().background(Palette.hairline).padding(.vertical, Space.s)

                // Stacked comparison chart
                if !summaries.isEmpty {
                    VStack(spacing: Space.s) {
                        Eyebrow(text: "7-day trend")
                        StackedComparisonChart(summaries: summaries)
                            .frame(height: 160)
                            .padding(.vertical, Space.s)
                    }
                    .padding(.horizontal, Space.s)
                }

                Divider().background(Palette.hairline).padding(.vertical, Space.s)

                // Leaderboard
                if !summaries.isEmpty {
                    VStack(spacing: Space.s) {
                        Eyebrow(text: "Today's ranking")
                        Text("Members with at least 10 min tracked today are ranked.")
                            .font(.caption)
                            .foregroundStyle(Palette.mist)
                    }
                    .padding(.bottom, Space.xs)

                    ForEach(leaderboardSummaries) { summary in
                        leaderboardCard(summary)
                    }
                } else {
                    Text("No members yet. Invite a friend!")
                        .font(.callout)
                        .foregroundStyle(Palette.mist)
                        .padding(.top, Space.xl)
                }

                // Delete / Leave button
                VStack(spacing: Space.s) {
                    if isOwner {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete this pillar", systemImage: "trash")
                                .font(.system(.subheadline, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.amber)
                    } else if members.contains(where: { $0.userId == currentUserId }) {
                        Button(role: .destructive) {
                            leaveCircle()
                        } label: {
                            Label("Leave this pillar", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(.subheadline, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.amber)
                    }
                }
                .padding(.top, Space.l)
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .background(PerchBackground())
        .task { await loadSummaries() }
        .alert("Delete \(currentCircle.name)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteCircle() }
        } message: {
            Text("All members will be removed and the pillar will be permanently deleted.")
        }
        .alert("Rename pillar", isPresented: $showRename) {
            TextField("Pillar name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameCircle() }
        } message: {
            Text("Pick a new name for your pillar.")
        }
    }

    // MARK: - Leaderboard (ranked, crown on leader)

    /// Sorted: ranked members first (highest score), then unranked (not enough data).
    private var leaderboardSummaries: [CircleMemberSummary] {
        let ranked = summaries.filter { $0.hasEnoughData }
            .sorted { $0.todayUprightPct > $1.todayUprightPct }
        let unranked = summaries.filter { !$0.hasEnoughData }
            .sorted { $0.todayUprightPct > $1.todayUprightPct }
        return ranked + unranked
    }

    private func leaderboardCard(_ summary: CircleMemberSummary) -> some View {
        let isLeader = leaderboardSummaries.first?.id == summary.id && summary.hasEnoughData

        return SoftCard {
            VStack(spacing: Space.m) {
                HStack {
                    if isLeader {
                        Text("👑")
                            .font(.title3)
                    }
                    Image(systemName: "person.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Palette.sage)
                    Text(summary.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if summary.hasEnoughData {
                        Text(summary.leaderboardLabel)
                            .font(.title2.weight(.thin))
                            .foregroundStyle(trendColor(summary.todayUprightPct))
                            .monospacedDigit()
                    } else {
                        Text(summary.leaderboardLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.mist)
                    }
                }

                HStack(spacing: Space.xl) {
                    statLabel("Today", summary.hasEnoughData ? "\(Int(summary.todayUprightPct.rounded()))%" : "—", Palette.ink)
                    statLabel("Streak", "\(summary.streak)d", Palette.sage)
                    statLabel("7-day avg", "\(Int(summary.weeklyAvg.rounded()))%", Palette.inkSoft)
                    Spacer()
                }
            }
        }
    }

    private func statLabel(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.mist)
                .tracking(0.8)
                .textCase(.uppercase)
        }
    }

    private func trendColor(_ pct: Double) -> Color {
        if pct >= 80 { return Palette.sage }
        if pct >= 60 { return Palette.amber }
        return Palette.amberSoft
    }

    // MARK: - Delete / Leave / Rename

    private func deleteCircle() {
        Task {
            await db.deleteCircle(currentCircle.id)
            dismiss()
        }
    }

    private func leaveCircle() {
        guard let membership = members.first(where: { $0.userId == currentUserId }) else { return }
        Task {
            await db.removeMember(membership.id)
            dismiss()
        }
    }

    private func renameCircle() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            try? await db.renameCircle(currentCircle.id, to: trimmed)
            await MainActor.run {
                currentCircle.name = trimmed
            }
        }
    }

    // MARK: - Load member summaries

    private func loadSummaries() async {
        let loaded = await db.loadMembers(for: currentCircle.id)
        members = loaded
        summaries = await withTaskGroup(of: CircleMemberSummary.self) { group in
            for member in loaded {
                group.addTask { await buildSummary(for: member) }
            }
            var results: [CircleMemberSummary] = []
            for await summary in group { results.append(summary) }
            return results
        }
    }

    private func buildSummary(for member: CircleMember) async -> CircleMemberSummary {
        if member.userId == currentUserId {
            let today = store.todayRecord()
            let week = store.recentDays(7).map { $0.monitoredSeconds > 0 ? $0.uprightPct : 0 }
            return CircleMemberSummary(
                id: member.id,
                userId: member.userId,
                name: store.profile.displayName ?? "You",
                todayUprightPct: engine.uprightPct,
                streak: streakForCurrentUser(),
                weeklyAvg: weeklyAvgForCurrentUser(),
                todayMonitoredSeconds: today.monitoredSeconds,
                weekScores: week
            )
        }

        let peerProfile = await db.loadProfile(userId: member.userId)
        let displayName = peerProfile?.displayName ?? "Member"

        let peerDays = await db.loadDaysForUser(member.userId)
        let todayPct: Double
        let todaySecs: Double
        let streak: Int
        let weekly: Double
        var weekScores: [Double] = Array(repeating: 0, count: 7)

        if let todayDay = peerDays.first(where: { Calendar.current.isDateInToday($0.date) }) {
            todayPct = todayDay.uprightPct
            todaySecs = todayDay.monitoredSeconds
        } else {
            todayPct = 0
            todaySecs = 0
        }

        streak = computeStreak(from: peerDays)

        let cal = Calendar.current
        let weekDays = peerDays.filter {
            let daysAgo = cal.dateComponents([.day], from: $0.date, to: Date()).day ?? 0
            return daysAgo >= 0 && daysAgo < 7
        }
        weekly = weekDays.isEmpty ? 0 : weekDays.map(\.uprightPct).reduce(0, +) / Double(weekDays.count)

        // Build 7-day scores array (index 0 = 6 days ago, index 6 = today).
        for i in 0..<7 {
            let dayDate = cal.date(byAdding: .day, value: -(6 - i), to: cal.startOfDay(for: Date())) ?? Date()
            if let day = peerDays.first(where: { cal.isDate($0.date, inSameDayAs: dayDate) }),
               day.monitoredSeconds > 0 {
                weekScores[i] = day.uprightPct
            } else {
                weekScores[i] = 0
            }
        }

        return CircleMemberSummary(
            id: member.id,
            userId: member.userId,
            name: displayName,
            todayUprightPct: todayPct,
            streak: streak,
            weeklyAvg: weekly,
            todayMonitoredSeconds: todaySecs,
            weekScores: weekScores
        )
    }

    private func computeStreak(from days: [PostureDay]) -> Int {
        let cal = Calendar.current
        let sorted = days.sorted { $0.date > $1.date }
        var count = 0
        var expected = cal.startOfDay(for: Date())
        for day in sorted {
            guard cal.isDate(day.date, inSameDayAs: expected) else { break }
            if day.monitoredSeconds >= 300 {
                count += 1
                expected = cal.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else { break }
        }
        return count
    }

    private func streakForCurrentUser() -> Int {
        computeStreak(from: store.recentDays(90))
    }

    private func weeklyAvgForCurrentUser() -> Double {
        let week = store.recentDays(7)
        let active = week.filter { $0.monitoredSeconds > 0 }
        guard !active.isEmpty else { return 0 }
        return active.map(\.uprightPct).reduce(0, +) / Double(active.count)
    }
}

// MARK: - Stacked comparison chart

/// Overlaid 7-day trend lines — one line per member, color-coded.
/// Each member's daily Posture Score is plotted as a line.
private struct StackedComparisonChart: View {
    let summaries: [CircleMemberSummary]

    /// Distinct colors per member (using sage + amber variants).
    private let memberColors: [Color] = [
        Palette.sage,
        Palette.amber,
        Palette.sageSoft,
        Palette.amberSoft,
        Color.teal.opacity(0.7),
        Color.indigo.opacity(0.5),
        Color.mint.opacity(0.7),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height - 20
                ZStack {
                    // Grid lines
                    ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                        Path { path in
                            let y = h - (h * CGFloat(pct) / 100)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Palette.hairline, lineWidth: 0.5)
                    }

                    // Lines per member
                    ForEach(Array(summaries.prefix(7).enumerated()), id: \.element.id) { index, summary in
                        let color = memberColors[index % memberColors.count]
                        let points = positions(for: summary.weekScores, in: CGSize(width: w, height: h))
                        if points.count > 1 {
                            linePath(points: points)
                                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }

            // Legend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    ForEach(Array(summaries.prefix(7).enumerated()), id: \.element.id) { index, summary in
                        HStack(spacing: Space.xs) {
                            Circle()
                                .fill(memberColors[index % memberColors.count])
                                .frame(width: 8, height: 8)
                            Text(summary.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.mist)
                        }
                    }
                }
            }
        }
    }

    private func positions(for scores: [Double], in size: CGSize) -> [CGPoint] {
        guard scores.count > 1 else {
            if let s = scores.first {
                return [CGPoint(x: size.width / 2, y: size.height - (size.height * CGFloat(s / 100)))]
            }
            return []
        }
        let stepX = size.width / CGFloat(scores.count - 1)
        return scores.enumerated().map { index, score in
            let x = CGFloat(index) * stepX
            let y = size.height - (size.height * CGFloat(score / 100))
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
}
