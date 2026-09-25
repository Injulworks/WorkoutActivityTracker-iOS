import SwiftUI

struct WorkoutStatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var range: WorkoutStatsRange = .week
    @State private var heatmapDays = 7

    private var summary: WorkoutStatsSummary {
        WorkoutStatsService.summary(for: store.workoutSessions, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                Picker("Range", selection: $range) {
                    Text("Today").tag(WorkoutStatsRange.today)
                    Text("Week").tag(WorkoutStatsRange.week)
                    Text("Month").tag(WorkoutStatsRange.month)
                    Text("Year").tag(WorkoutStatsRange.year)
                    Text("Lifetime").tag(WorkoutStatsRange.lifetime)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                    statCard("Exercises Completed", "\(summary.exercisesCompleted)")
                    statCard("Sessions", "\(summary.sessions)")
                    statCard("Total Time", "\(summary.totalActiveMinutes) min")
                    statCard("Calories", "\(Int(summary.totalCalories)) kcal")
                    statCard("Avg Session", String(format: "%.1f min", summary.averageSessionMinutes))
                    statCard("Longest Session", "\(summary.longestSessionMinutes) min")
                    statCard("Current Streak", "\(summary.currentStreak) days")
                    statCard("Best Streak", "\(summary.bestStreak) days")
                    statCard("Consistency", "\(Int(summary.consistencyPercent))%")
                    statCard("Favorite Exercise", summary.favoriteExerciseName ?? "—")
                }
                .padding(.horizontal)

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack {
                            Text("Workout heatmap").font(Theme.Font.cardTitle).foregroundStyle(Theme.primaryText)
                            Spacer()
                            Picker("Heatmap range", selection: $heatmapDays) {
                                Text("7 days").tag(7)
                                Text("30 days").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        WorkoutHeatmap(days: heatmapDays)
                    }
                }
                .padding(.horizontal)

                // The heatmap/summary above stays the aggregate view; every
                // individually completed workout — with its full breakdown —
                // lives one tap away here instead of only being reachable as
                // a number folded into these totals.
                NavigationLink { WorkoutHistoryView() } label: {
                    GlassCard {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(Theme.accent)
                            Text("Workout History").font(Theme.Font.cardTitle).foregroundStyle(Theme.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            .padding(.vertical, Theme.Spacing.xl)
        }
        .background(Theme.background)
        .navigationTitle("Workout Statistics")
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.primaryText).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WorkoutHeatmap: View {
    @EnvironmentObject private var store: AppStore
    let days: Int
    private var calendar: Calendar { .current }
    private var dates: [Date] { (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: Date())) }.reversed() }
    private func minutes(on day: Date) -> Int { Int(store.workoutSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }.reduce(0.0) { $0 + $1.activeDuration } / 60) }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
            ForEach(dates, id: \.self) { day in
                let value = minutes(on: day)
                RoundedRectangle(cornerRadius: 5)
                    .fill(value == 0 ? Theme.cardBorder : Theme.accent.opacity(min(1, 0.25 + Double(value) / 30)))
                    .frame(height: 32)
                    .overlay(Text(value == 0 ? "" : "\(value)m").font(.caption2).foregroundStyle(.white))
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(value) workout minutes")
            }
        }
    }
}
