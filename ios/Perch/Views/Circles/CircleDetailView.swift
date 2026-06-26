//
//  CircleDetailView.swift
//  Perch
//
//  Lists circle members with their posture stats: today's upright %, current
//  streak, and 7-day average. Calm and supportive — no leaderboard, no red.
//  The circle owner can delete the circle; other members can leave.
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

    private var isOwner: Bool { circle.ownerId == (auth.userId ?? "") }
    private var currentUserId: String { auth.userId ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                // Header
                VStack(spacing: Space.s) {
                    Text(circle.name)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Supportive, not competitive. No leaderboard here.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)

                // Invite code (for the owner to share).
                VStack(spacing: Space.xs) {
                    Eyebrow(text: "Invite code")
                    Text(circle.inviteCode)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Palette.sage)
                        .tracking(4)
                }
                .padding(.top, Space.s)

                Divider().background(Palette.hairline).padding(.vertical, Space.s)

                // Member cards
                if summaries.isEmpty {
                    Text("No members yet. Invite a friend!")
                        .font(.callout)
                        .foregroundStyle(Palette.mist)
                        .padding(.top, Space.xl)
                } else {
                    ForEach(summaries) { summary in
                        memberCard(summary)
                    }
                }

                // Delete / Leave button
                VStack(spacing: Space.s) {
                    if isOwner {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete this circle", systemImage: "trash")
                                .font(.system(.subheadline, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.amber)
                    } else if members.contains(where: { $0.userId == currentUserId }) {
                        Button(role: .destructive) {
                            leaveCircle()
                        } label: {
                            Label("Leave this circle", systemImage: "rectangle.portrait.and.arrow.right")
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
        .alert("Delete \(circle.name)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteCircle() }
        } message: {
            Text("All members will be removed and the circle will be permanently deleted.")
        }
    }

    // MARK: - Delete / Leave

    private func deleteCircle() {
        Task {
            await db.deleteCircle(circle.id)
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

    // MARK: - Member card

    private func memberCard(_ s: CircleMemberSummary) -> some View {
        SoftCard {
            VStack(spacing: Space.m) {
                HStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Palette.sage)
                    Text(s.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(Int(s.todayUprightPct.rounded()))%")
                        .font(.title2.weight(.thin))
                        .foregroundStyle(trendColor(s.todayUprightPct))
                        .monospacedDigit()
                }

                HStack(spacing: Space.xl) {
                    statLabel("Today", "\(Int(s.todayUprightPct.rounded()))%", Palette.ink)
                    statLabel("Streak", "\(s.streak)d", Palette.sage)
                    statLabel("7-day avg", "\(Int(s.weeklyAvg.rounded()))%", Palette.inkSoft)
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

    // MARK: - Load member summaries

    private func loadSummaries() async {
        let loaded = await db.loadMembers(for: circle.id)
        members = loaded
        summaries = await withTaskGroup(of: CircleMemberSummary.self) { group in
            for member in loaded {
                group.addTask { await buildSummary(for: member) }
            }
            var results: [CircleMemberSummary] = []
            for await summary in group { results.append(summary) }
            return results
        }
        summaries.sort { $0.todayUprightPct > $1.todayUprightPct }
    }

    private func buildSummary(for member: CircleMember) async -> CircleMemberSummary {
        if member.userId == currentUserId {
            return CircleMemberSummary(
                id: member.id,
                name: "You",
                todayUprightPct: engine.uprightPct,
                streak: streakForCurrentUser(),
                weeklyAvg: weeklyAvgForCurrentUser()
            )
        }

        // Load the fellow member's posture days from Supabase.
        let peerDays = await db.loadDaysForUser(member.userId)
        let todayPct: Double
        let streak: Int
        let weekly: Double

        if let todayDay = peerDays.first(where: { Calendar.current.isDateInToday($0.date) }) {
            todayPct = todayDay.uprightPct
        } else {
            todayPct = 0
        }

        // Compute streak from their days.
        streak = computeStreak(from: peerDays)

        // Compute weekly average.
        let weekDays = peerDays.filter {
            let daysAgo = Calendar.current.dateComponents([.day], from: $0.date, to: Date()).day ?? 0
            return daysAgo >= 0 && daysAgo < 7 && $0.monitoredSeconds > 0
        }
        weekly = weekDays.isEmpty ? 0 : weekDays.map(\.uprightPct).reduce(0, +) / Double(weekDays.count)

        let displayName = member.userId
            .split(separator: "@").first
            .map(String.init) ?? member.userId

        return CircleMemberSummary(
            id: member.id,
            name: displayName,
            todayUprightPct: todayPct,
            streak: streak,
            weeklyAvg: weekly
        )
    }

    private func computeStreak(from days: [PostureDay]) -> Int {
        let cal = Calendar.current
        let sorted = days.sorted { $0.date > $1.date }
        var count = 0
        var expected = cal.startOfDay(for: Date())
        for day in sorted {
            guard cal.isDate(day.date, inSameDayAs: expected) else { break }
            if day.monitoredSeconds > 0 {
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
