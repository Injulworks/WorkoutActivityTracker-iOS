import XCTest
@testable import WorkoutActivityCore

/// All fixtures are synthetic.
final class WorkoutStatsTests: XCTestCase {
    private let cal = Calendar.current
    private let ref = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(daysAgo: Int, minutes: Double, calories: Double = 50, exercise: String = "plank") -> WorkoutSession {
        let start = cal.date(byAdding: .day, value: -daysAgo, to: ref)!
        let seg = WorkoutExerciseSegment(exerciseID: exercise, start: start, end: start.addingTimeInterval(minutes * 60))
        return WorkoutSession(id: UUID(), exerciseID: exercise, startedAt: start,
                              endedAt: start.addingTimeInterval(minutes * 60), caloriesBurned: calories,
                              segments: [.exercise(seg)])
    }

    func testCalorieEstimateIsMETxKgxHours() {
        XCTAssertEqual(CalorieCalculator.estimate(met: 8, weightKg: 70, activeSeconds: 1800), 280, accuracy: 0.001)
        XCTAssertEqual(CalorieCalculator.estimate(met: 8, weightKg: 70, activeSeconds: 1800, multiplier: 0.5), 140, accuracy: 0.001)
    }

    func testSummaryTotalsForToday() {
        let s = WorkoutStatsService.summary(for: [session(daysAgo: 0, minutes: 10), session(daysAgo: 0, minutes: 20, calories: 100)],
                                            range: .today, referenceDate: ref)
        XCTAssertEqual(s.sessions, 2)
        XCTAssertEqual(s.totalActiveMinutes, 30)
        XCTAssertEqual(s.totalCalories, 150, accuracy: 0.001)
        XCTAssertEqual(s.longestSessionMinutes, 20)
        XCTAssertEqual(s.favoriteExerciseName, "Plank")
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let sessions = [0, 1, 2, 4].map { session(daysAgo: $0, minutes: 5) }
        let s = WorkoutStatsService.summary(for: sessions, range: .lifetime, referenceDate: ref)
        XCTAssertEqual(s.currentStreak, 3)
        XCTAssertEqual(s.bestStreak, 3)
    }

    func testStreakIsZeroWhenNothingToday() {
        let s = WorkoutStatsService.summary(for: [session(daysAgo: 1, minutes: 5)], range: .lifetime, referenceDate: ref)
        XCTAssertEqual(s.currentStreak, 0)
        XCTAssertEqual(s.bestStreak, 1)
    }

    func testRangeFilterWindows() {
        let sessions = [0, 6, 7, 29, 30, 364, 365].map { session(daysAgo: $0, minutes: 5) }
        func n(_ r: WorkoutStatsRange) -> Int { WorkoutStatsService.filter(sessions, range: r, referenceDate: ref).count }
        XCTAssertEqual(n(.today), 1)
        XCTAssertEqual(n(.week), 2)
        XCTAssertEqual(n(.month), 4)
        XCTAssertEqual(n(.year), 6)
        XCTAssertEqual(n(.lifetime), 7)
    }

    func testOrphanedOpenSegmentIsClosedAtLastAutosave() {
        let start = ref
        var open = WorkoutSession(startedAt: start, endedAt: start.addingTimeInterval(120),
                                  segments: [.exercise(WorkoutExerciseSegment(exerciseID: "plank", start: start, end: nil))])
        open = WorkoutSessionIntegrity.finalizingOrphanedSegments(in: [open])[0]
        XCTAssertEqual(open.activeDuration, 120, accuracy: 0.001)
    }

    func testLegacySessionWithoutSegmentsFallsBackToTotalMinusBreaks() {
        let start = ref
        let s = WorkoutSession(exerciseID: "situp", startedAt: start, endedAt: start.addingTimeInterval(600),
                               breaks: [WorkoutBreak(start: start, end: start.addingTimeInterval(100))])
        XCTAssertEqual(s.activeDuration, 500, accuracy: 0.001)
    }

    func testSessionRoundTripsThroughJSON() throws {
        let original = session(daysAgo: 0, minutes: 12)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSession.self, from: data), original)
    }

    func testCustomWorkoutMapsToExerciseWithMET() {
        let c = CustomWorkout(name: "Sample Circuit", caloriesPerMinute: 7)
        XCTAssertEqual(c.asExercise.id, "custom-\(c.id.uuidString)")
        XCTAssertEqual(c.asExercise.met, 7 * 60 / 70, accuracy: 0.001)
    }
}
