import Foundation
import Combine

final class WorkoutRuntime: ObservableObject {
    static let shared = WorkoutRuntime()
    @Published var active: WorkoutSessionViewModel?
    @Published var isFullscreenPresented = false
    private init() {}
}

final class WorkoutSessionViewModel: ObservableObject {
    @Published var currentExercise: WorkoutExercise
    @Published var segments: [WorkoutSegment] = []
    
    @Published private(set) var isRunning = false
    @Published private(set) var isOnBreak = false
    @Published private(set) var workoutElapsed: TimeInterval = 0
    @Published private(set) var breakElapsed: TimeInterval = 0
    @Published private(set) var completedSession: WorkoutSession?
    @Published private(set) var loggedSets: [WorkoutSet] = []
    
    var breaksTaken: Int { segments.compactMap { if case .rest = $0 { return $0 } else { return nil } }.count }
    
    private let store: AppStore
    private let session: WorkoutSession
    private var timer: Timer?
    private var startedAt: Date?
    private var currentBreakStart: Date?
    private var lastAutosaveAt = Date.distantPast
    
    init(exercise: WorkoutExercise, store: AppStore = .shared) {
        self.currentExercise = exercise
        self.store = store
        self.session = WorkoutSession(startedAt: Date())
        self.segments = [.exercise(WorkoutExerciseSegment(exerciseID: exercise.id))]
    }
    
    // Root cause of the rest double-counting bug (real screenshot: Break
    // Time 00:05, Total rest 00:10): WorkoutRestSegment.duration is ALREADY
    // a live, timestamp-based value ((end ?? Date()) - start), so the
    // in-progress rest segment's own .duration already reflects elapsed
    // break time. The old formula added `breakElapsed` (the separately
    // ticked @Published var, driven by the same 0.1s timer off the same
    // start instant) on top of that — the same quantity counted twice for
    // whichever break is currently active. Summing segment durations alone
    // is the single authoritative source; no second counter needed.
    var totalBreakElapsed: TimeInterval {
        segments.compactMap {
            if case let .rest(rest) = $0 { return rest.duration }
            return nil
        }.reduce(0, +)
    }

    // Root cause of "switching exercises inherits the previous exercise's
    // time" (and the same defect papering over the resting-state leak
    // switchExercise() had — see that function): this summed EVERY
    // exercise segment in `segments` regardless of which exercise it
    // belonged to, so Leg Raises' displayed time included Sit-ups' time
    // too. Filtering to the CURRENT exercise's own segments still
    // correctly sums across multiple rest-interrupted intervals of THAT
    // exercise (the intended behavior), it just never leaks in another
    // exercise's segments.
    var activeElapsed: TimeInterval {
        segments.compactMap {
            if case let .exercise(ex) = $0, ex.exerciseID == currentExercise.id { return ex.duration }
            return nil
        }.reduce(0, +)
    }
    
    var cumulativeActiveElapsed: TimeInterval {
        segments.compactMap {
            if case let .exercise(ex) = $0 { return ex.duration }
            return nil
        }.reduce(0, +)
    }
    
    func currentCalories(weightKg: Double) -> Double {
        var totalCalories: Double = 0
        for segment in segments {
            if case let .exercise(ex) = segment {
                if let met = metForCalories(exerciseID: ex.exerciseID) {
                    totalCalories += CalorieCalculator.estimate(met: met, weightKg: weightKg, activeSeconds: ex.duration, multiplier: store.settings.workoutCalorieMultiplier)
                }
            }
        }
        return totalCalories
    }

    /// MET lookup for calorie calculation. `WorkoutExercise.find` only
    /// searches the fixed catalog, so a custom workout's `"custom-<uuid>"`
    /// id always missed it and silently contributed 0 calories for its
    /// entire duration — a permanent zero, not a truncation artifact. A
    /// custom workout already carries its own MET estimate
    /// (`CustomWorkout.asExercise.met`, derived from the calories/minute the
    /// user set when creating it), so this falls back to that instead of
    /// fabricating a number for an id that still can't be resolved.
    private func metForCalories(exerciseID: String) -> Double? {
        if let known = WorkoutExercise.find(exerciseID) { return known.met }
        guard exerciseID.hasPrefix("custom-"),
              let uuid = UUID(uuidString: String(exerciseID.dropFirst(7))),
              let custom = store.customWorkouts.first(where: { $0.id == uuid }) else { return nil }
        return custom.asExercise.met
    }

    func start() {
        guard !isRunning else { return }
        startedAt = startedAt ?? Date()
        isRunning = true
        isOnBreak = false
        startTicking()
        saveProgress()
        WorkoutRuntime.shared.active = self
    }
    
    func pauseAsBreak() {
        guard isRunning, !isOnBreak else { return }
        isOnBreak = true
        currentBreakStart = Date()
        
        if case var .exercise(ex) = segments.last! {
            ex.end = Date()
            segments[segments.count - 1] = .exercise(ex)
        }
        
        segments.append(.rest(WorkoutRestSegment(start: Date())))
        saveProgress()
    }
    
    func resumeFromBreak() {
        guard isOnBreak else { return }
        if case var .rest(rest) = segments.last! {
            rest.end = Date()
            segments[segments.count - 1] = .rest(rest)
        }
        isOnBreak = false
        currentBreakStart = nil
        segments.append(.exercise(WorkoutExerciseSegment(exerciseID: currentExercise.id)))
        saveProgress()
    }
    
    func switchExercise(to newExercise: WorkoutExercise) {
        // Root cause of the gray/stuck-timer bug: this only ever closed the
        // last segment when it was `.exercise`. Called while resting (last
        // segment `.rest`, isOnBreak true — the real "play a different
        // exercise while rest is active" flow), the `if case .exercise`
        // check silently failed, so the rest segment was NEVER finalized
        // and isOnBreak/currentBreakStart were NEVER cleared: the open
        // rest segment kept growing forever, and the UI stayed in its
        // resting/gray presentation even though a new exercise segment
        // was ticking underneath it. Ending rest and clearing that state
        // atomically here is exactly OBJ-003/WU-003's "play during rest
        // must itself end rest and transition directly to the new
        // exercise, in one action" requirement.
        if isOnBreak, case var .rest(rest) = segments.last! {
            rest.end = Date()
            segments[segments.count - 1] = .rest(rest)
            isOnBreak = false
            currentBreakStart = nil
        } else if case var .exercise(ex) = segments.last! {
            ex.end = Date()
            segments[segments.count - 1] = .exercise(ex)
        }
        currentExercise = newExercise
        segments.append(.exercise(WorkoutExerciseSegment(exerciseID: newExercise.id)))
        saveProgress()
    }
    
    func addSet(reps: Int, weightKg: Double?) {
        guard reps > 0 else { return }
        if case var .exercise(ex) = segments.last! {
            let newSet = WorkoutSet(reps: reps, weightKg: weightKg)
            ex.sets.append(newSet)
            segments[segments.count - 1] = .exercise(ex)
            loggedSets.append(newSet)
        }
        saveProgress()
    }
    
    func removeSet(_ set: WorkoutSet) {
        // Find and remove set from correct segment
        for (index, segment) in segments.enumerated() {
            if case var .exercise(ex) = segment {
                if ex.sets.contains(where: { $0.id == set.id }) {
                    ex.sets.removeAll { $0.id == set.id }
                    segments[index] = .exercise(ex)
                    break
                }
            }
        }
        loggedSets.removeAll { $0.id == set.id }
        saveProgress()
    }
    
    private func startTicking() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.workoutElapsed = Date().timeIntervalSince(startedAt)
            if self.isOnBreak, let breakStart = self.currentBreakStart {
                self.breakElapsed = Date().timeIntervalSince(breakStart)
            }
            if Date().timeIntervalSince(self.lastAutosaveAt) >= 5 {
                self.lastAutosaveAt = Date()
                self.saveProgress()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    func stop(weightKg: Double) {
        timer?.invalidate()
        timer = nil
        guard let startedAt else { return }
        
        let endedAt = Date()
        
        // Finalize last segment
        if case var .exercise(ex) = segments.last! {
            ex.end = endedAt
            segments[segments.count - 1] = .exercise(ex)
        } else if case var .rest(rest) = segments.last! {
            rest.end = endedAt
            segments[segments.count - 1] = .rest(rest)
        }
        
        var finalSession = self.session
        finalSession.endedAt = endedAt
        finalSession.caloriesBurned = currentCalories(weightKg: weightKg)
        finalSession.segments = segments
        
        store.upsertWorkoutSession(finalSession)
        completedSession = finalSession
        
        isRunning = false
        isOnBreak = false
        if WorkoutRuntime.shared.active === self { WorkoutRuntime.shared.active = nil }
    }
    
    private func saveProgress() {
        guard let startedAt else { return }
        
        var progressSession = self.session
        progressSession.endedAt = Date()
        progressSession.caloriesBurned = currentCalories(weightKg: store.healthProfile.weightKg)
        progressSession.segments = segments
        
        store.upsertWorkoutSession(progressSession)
    }
    
    func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

