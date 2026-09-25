import Foundation

struct WorkoutStatsSummary {
    var exercisesCompleted: Int
    var sessions: Int
    var totalActiveMinutes: Int
    var totalCalories: Double
    var averageSessionMinutes: Double
    var longestSessionMinutes: Int
    var currentStreak: Int
    var bestStreak: Int
    var favoriteExerciseName: String?
    var consistencyPercent: Double
}

enum WorkoutStatsRange { case today, week, month, year, lifetime }

enum WorkoutStatsService {
    /// Filters sessions to a date window, reused by both the aggregate
    /// `summary` below and Workout History — so "this week/month/year" means
    /// exactly the same thing in both places rather than two independent
    /// date calculations drifting apart.
    static func filter(_ sessions: [WorkoutSession], range: WorkoutStatsRange, referenceDate: Date = Date()) -> [WorkoutSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        switch range {
        case .today:
            return sessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return sessions.filter { $0.date >= start && $0.date <= today }
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return sessions.filter { $0.date >= start && $0.date <= today }
        case .year:
            let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
            return sessions.filter { $0.date >= start && $0.date <= today }
        case .lifetime:
            return sessions
        }
    }

    static func summary(for sessions: [WorkoutSession], range: WorkoutStatsRange, referenceDate: Date = Date()) -> WorkoutStatsSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let filtered = filter(sessions, range: range, referenceDate: referenceDate)

        // Live workout sessions are persisted while running, so the overall
        // dashboard updates immediately instead of waiting for End & Save.
        let completed = filtered
        let totalActiveSeconds = completed.reduce(0.0) { $0 + $1.activeDuration }
        let totalCalories = completed.reduce(0.0) { $0 + $1.caloriesBurned }
        let longestSeconds = completed.map(\.activeDuration).max() ?? 0

        // Favorite = most frequently performed exercise across the filtered range.
        let counts = Dictionary(grouping: completed, by: \.exerciseID).mapValues(\.count)
        let favoriteID = counts.max { $0.value < $1.value }?.key
        let favoriteName = favoriteID.flatMap { WorkoutExercise.find($0)?.name }

        // Streak/consistency computed across ALL sessions (not just the
        // filtered range) so "Current Streak" means the same thing regardless
        // of which range tab is selected.
        let allByDay = Dictionary(grouping: sessions, by: \.date)
        var currentStreak = 0
        var day = today
        while allByDay[day] != nil {
            currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        let sortedDays = allByDay.keys.sorted()
        var best = 0
        var running = 0
        var previousDay: Date?
        for d in sortedDays {
            if let previousDay, calendar.date(byAdding: .day, value: 1, to: previousDay) == d {
                running += 1
            } else {
                running = 1
            }
            best = max(best, running)
            previousDay = d
        }
        best = max(best, currentStreak)

        let rangeDayCount: Double
        switch range {
        case .today: rangeDayCount = 1
        case .week: rangeDayCount = 7
        case .month: rangeDayCount = 30
        case .year: rangeDayCount = 365
        case .lifetime: rangeDayCount = max(1, Double(Set(sessions.map(\.date)).count))
        }
        let daysInRangeWithSession = Double(Set(filtered.map(\.date)).count)

        return WorkoutStatsSummary(
            exercisesCompleted: completed.count,
            sessions: completed.count,
            totalActiveMinutes: Int(totalActiveSeconds / 60),
            totalCalories: totalCalories,
            averageSessionMinutes: completed.isEmpty ? 0 : (totalActiveSeconds / 60) / Double(completed.count),
            longestSessionMinutes: Int(longestSeconds / 60),
            currentStreak: currentStreak,
            bestStreak: best,
            favoriteExerciseName: favoriteName,
            consistencyPercent: min(100, daysInRangeWithSession / rangeDayCount * 100)
        )
    }
}
