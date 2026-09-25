import SwiftUI

// MARK: - Shared metrics card

/// The 7-row session summary (Duration / Active Time / Break Time / Breaks
/// Taken / Average Break / Longest Break / Calories). Extracted out of
/// `WorkoutSummaryView` (the Complete screen) so Workout History's detail
/// screen renders the exact same numbers the same way, rather than a second,
/// independently-drifting copy. `WorkoutSession` is still the only source —
/// this purely projects it.
struct WorkoutMetricsCard: View {
    let session: WorkoutSession

    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.m) {
                row("Duration", formatted(session.totalDuration))
                row("Active Time", formatted(session.activeDuration))
                row("Break Time", formatted(session.totalBreakDuration))
                row("Breaks Taken", "\(session.breakCount)")
                row("Average Break", formatted(session.averageBreakDuration))
                row("Longest Break", formatted(session.longestBreak))
                row("Calories", "\(Int(session.caloriesBurned.rounded())) kcal (estimated)")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).font(Theme.Font.body).foregroundStyle(Theme.primaryText)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Label derivation (no fabricated categories)

/// `WorkoutSession` has no name/category field, and none of Problem 2's
/// requirements ask for one — so History labels a session from what's
/// actually recorded (its exercises, or its HIIT/Walking discriminator)
/// instead of inventing a "Full Body" / "Core" style category.
func historyTitle(for session: WorkoutSession, store: AppStore) -> String {
    switch session.exerciseID {
    case "hiit": return "HIIT"
    case "walking": return "Walking"
    default: break
    }
    let names = session.activeSegments.map { WorkoutBreakdown.resolveExerciseName($0.exerciseID, store: store) }
    guard let first = names.first else { return "Workout" }
    var seen = Set<String>()
    let distinct = names.filter { seen.insert($0).inserted }
    guard distinct.count > 1 else { return first }
    return "\(first) +\(distinct.count - 1) more"
}

func historySubtitle(for session: WorkoutSession) -> String {
    var parts: [String] = []
    if !session.activeSegments.isEmpty {
        let n = session.activeSegments.count
        parts.append("\(n) exercise\(n == 1 ? "" : "s")")
    } else if let laps = session.laps, !laps.isEmpty {
        parts.append("\(laps.count) lap\(laps.count == 1 ? "" : "s")")
    }
    parts.append(WorkoutBreakdownFormat.duration(session.activeDuration))
    if session.caloriesBurned > 0 {
        parts.append("\(Int(session.caloriesBurned.rounded())) kcal")
    }
    return parts.joined(separator: " · ")
}

func historyIcon(for session: WorkoutSession) -> String {
    switch session.exerciseID {
    case "hiit": return "bolt.fill"
    case "walking": return "figure.walk"
    default: return "figure.strengthtraining.traditional"
    }
}

// MARK: - History list

/// "Workout History": every individually completed workout, most recent
/// first, grouped by day — the lifetime log the aggregate Workout Statistics
/// view doesn't provide. Reads `store.workoutSessions` directly; no second
/// persisted history is created.
struct WorkoutHistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var range: WorkoutStatsRange = .lifetime

    private var sessions: [WorkoutSession] {
        // Same "has anything actually happened" filter the Feed already
        // uses, so History and Feed agree on what counts as a real workout.
        let candidates = store.workoutSessions.filter { $0.activeDuration > 0 }
        return WorkoutStatsService.filter(candidates, range: range)
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var groupedByDay: [(day: Date, sessions: [WorkoutSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, sessions: grouped[day]!.sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Picker("Range", selection: $range) {
                    Text("All").tag(WorkoutStatsRange.lifetime)
                    Text("Week").tag(WorkoutStatsRange.week)
                    Text("Month").tag(WorkoutStatsRange.month)
                    Text("Year").tag(WorkoutStatsRange.year)
                }
                .pickerStyle(.segmented)

                if sessions.isEmpty {
                    Text("No completed workouts in this range yet.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Theme.Spacing.xxl)
                } else {
                    ForEach(groupedByDay, id: \.day) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text(group.day.formatted(date: .long, time: .omitted))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.leading, Theme.Spacing.xs)

                            VStack(spacing: Theme.Spacing.s) {
                                ForEach(group.sessions) { session in
                                    NavigationLink {
                                        WorkoutHistoryDetailView(session: session)
                                    } label: {
                                        WorkoutHistoryRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background)
        .navigationTitle("Workout History")
    }
}

private struct WorkoutHistoryRow: View {
    @EnvironmentObject var store: AppStore
    let session: WorkoutSession

    var body: some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: historyIcon(for: session))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.cardBackground))

                VStack(alignment: .leading, spacing: 2) {
                    Text(historyTitle(for: session, store: store))
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.primaryText)
                    Text(historySubtitle(for: session))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: Theme.Spacing.s)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

// MARK: - History detail

/// A single completed workout's full record: the same metrics card and the
/// same `WorkoutBreakdownView` the Complete screen uses (Problem 1) — History
/// is a second entry point into the same projection, not a second
/// implementation of it.
struct WorkoutHistoryDetailView: View {
    @ObservedObject private var store = AppStore.shared
    let session: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text(historyTitle(for: session, store: store))
                        .font(Theme.Font.sectionTitle)
                        .foregroundStyle(Theme.primaryText)
                    Text(session.startedAt.formatted(date: .long, time: .shortened))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                WorkoutMetricsCard(session: session)
                WorkoutBreakdownView(session: session, store: store)
            }
            .padding(Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .background(Theme.background)
        .navigationTitle("Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
