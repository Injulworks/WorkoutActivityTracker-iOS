import Foundation
import Combine

final class WorkoutDashboardViewModel: ObservableObject {
    @Published private(set) var today: WorkoutStatsSummary = WorkoutStatsService.summary(for: [], range: .today)
    @Published private(set) var week: WorkoutStatsSummary = WorkoutStatsService.summary(for: [], range: .week)
    @Published private(set) var month: WorkoutStatsSummary = WorkoutStatsService.summary(for: [], range: .month)

    private let store: AppStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppStore = .shared) {
        self.store = store
        store.$workoutSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.today = WorkoutStatsService.summary(for: sessions, range: .today)
                self?.week = WorkoutStatsService.summary(for: sessions, range: .week)
                self?.month = WorkoutStatsService.summary(for: sessions, range: .month)
            }
            .store(in: &cancellables)
    }

    /// HealthProfile.weightKg is the single source of truth for body weight
    /// app-wide — this used to read a separate AppSettings.workoutWeightKg
    /// field that started at the same default (82) but never stayed in sync
    /// once either was edited independently, so Profile and Settings could
    /// show two different numbers for what was supposed to be one value.
    var weightKg: Double { store.healthProfile.weightKg }
}
