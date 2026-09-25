import Foundation
import Combine

// Minimal reference host for the UI files in this folder.
// Replace with your own persistence layer; only the members below are used.

struct HealthProfile: Codable, Equatable { var weightKg: Double = 70 }
struct WorkoutSettings: Codable, Equatable { var workoutCalorieMultiplier: Double = 1.0 }

final class AppStore: ObservableObject {
    static let shared = AppStore()
    @Published var workoutSessions: [WorkoutSession] = []
    @Published var customWorkouts: [CustomWorkout] = []
    @Published var settings = WorkoutSettings()
    @Published var healthProfile = HealthProfile()

    func upsertWorkoutSession(_ session: WorkoutSession) {
        if let i = workoutSessions.firstIndex(where: { $0.id == session.id }) {
            workoutSessions[i] = session
        } else {
            workoutSessions.append(session)
        }
        // TODO(host): persist workoutSessions (JSON file, SwiftData, ...)
    }
}
