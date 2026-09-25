import Foundation

enum WorkoutDifficulty: String, Codable, CaseIterable {
    case beginner, intermediate, advanced
}

/// The fixed exercise catalog. MET (Metabolic Equivalent of Task) values are
/// standard, published approximations for bodyweight calisthenics — not
/// clinically precise for any individual, which is why `CalorieCalculator`
/// labels its output as an estimate, matching "Estimate automatically."
struct WorkoutExercise: Identifiable, Equatable {
    let id: String  // stable slug, used as the identifier everywhere
    let name: String
    let targetMuscles: [String]
    let instructions: String
    let correctPosture: String
    let difficulty: WorkoutDifficulty
    let met: Double
    let recommendedDurationMinutes: Int

    static let all: [WorkoutExercise] = [
        .init(id: "situp", name: "Sit Up", targetMuscles: ["Abs", "Hip Flexors"],
              instructions: "Lie on your back, knees bent, feet flat. Curl your torso up toward your knees, then lower with control.",
              correctPosture: "Keep your lower back from arching; avoid pulling on your neck.",
              difficulty: .beginner, met: 8.0, recommendedDurationMinutes: 3),
        .init(id: "legraises", name: "Leg Raises", targetMuscles: ["Lower Abs", "Hip Flexors"],
              instructions: "Lie flat, legs straight. Raise both legs to vertical, then lower slowly without touching the floor.",
              correctPosture: "Press your lower back into the floor throughout.",
              difficulty: .intermediate, met: 3.5, recommendedDurationMinutes: 3),
        .init(id: "plank", name: "Plank", targetMuscles: ["Core", "Shoulders"],
              instructions: "Hold a straight line from head to heels, supported on forearms and toes.",
              correctPosture: "Don't let your hips sag or pike up.",
              difficulty: .beginner, met: 4.0, recommendedDurationMinutes: 2),
        .init(id: "sideplank", name: "Side Plank", targetMuscles: ["Obliques", "Shoulders"],
              instructions: "Support your body on one forearm and the side of one foot, hips lifted in a straight line.",
              correctPosture: "Stack hips and shoulders vertically; don't rotate forward.",
              difficulty: .intermediate, met: 4.0, recommendedDurationMinutes: 2),
        .init(id: "deadbug", name: "Dead Bug", targetMuscles: ["Core", "Hip Flexors"],
              instructions: "Lying on your back, extend opposite arm and leg while keeping your lower back flat.",
              correctPosture: "Move slowly; keep your ribs down and lower back pressed to the floor.",
              difficulty: .beginner, met: 3.0, recommendedDurationMinutes: 3),
        .init(id: "glutebridge", name: "Glute Bridge", targetMuscles: ["Glutes", "Hamstrings"],
              instructions: "Lie on your back, knees bent. Drive through your heels to lift your hips.",
              correctPosture: "Squeeze glutes at the top; avoid overarching your lower back.",
              difficulty: .beginner, met: 3.5, recommendedDurationMinutes: 3),
        .init(id: "wallslides", name: "Wall Slides", targetMuscles: ["Shoulders", "Upper Back"],
              instructions: "Back against a wall, arms in a goalpost position. Slide arms up and down keeping contact with the wall.",
              correctPosture: "Keep lower back, head, and arms in contact with the wall throughout.",
              difficulty: .beginner, met: 2.5, recommendedDurationMinutes: 2),
        .init(id: "superman", name: "Superman", targetMuscles: ["Lower Back", "Glutes"],
              instructions: "Lying face down, simultaneously lift arms, chest, and legs off the floor.",
              correctPosture: "Lift through the whole body evenly; avoid jerking.",
              difficulty: .beginner, met: 3.0, recommendedDurationMinutes: 2),
        .init(id: "birddog", name: "Bird Dog", targetMuscles: ["Core", "Lower Back"],
              instructions: "On hands and knees, extend opposite arm and leg while keeping your back flat.",
              correctPosture: "Keep hips level — don't let them rotate open.",
              difficulty: .beginner, met: 3.0, recommendedDurationMinutes: 3),
        .init(id: "proneyraise", name: "Prone Y Raise", targetMuscles: ["Lower Traps", "Shoulders"],
              instructions: "Face down, arms extended overhead in a Y. Lift arms slightly off the floor.",
              correctPosture: "Lead with the thumbs up; keep neck neutral.",
              difficulty: .intermediate, met: 2.5, recommendedDurationMinutes: 2),
        .init(id: "proneTraise", name: "Prone T Raise", targetMuscles: ["Mid Traps", "Rear Delts"],
              instructions: "Face down, arms out to the sides in a T. Lift arms slightly off the floor.",
              correctPosture: "Squeeze shoulder blades together at the top.",
              difficulty: .intermediate, met: 2.5, recommendedDurationMinutes: 2),
        .init(id: "proneWraise", name: "Prone W Raise", targetMuscles: ["Rear Delts", "Rotator Cuff"],
              instructions: "Face down, elbows bent in a W shape. Lift arms, rotating shoulders externally.",
              correctPosture: "Keep elbows close to your sides as you lift.",
              difficulty: .intermediate, met: 2.5, recommendedDurationMinutes: 2),
        .init(id: "swimmer", name: "Swimmer", targetMuscles: ["Lower Back", "Glutes", "Shoulders"],
              instructions: "Face down, alternately lift opposite arm and leg in a fluttering, swimming motion.",
              correctPosture: "Keep the motion small and controlled, not a big kick.",
              difficulty: .intermediate, met: 3.5, recommendedDurationMinutes: 2),
        .init(id: "cobrahold", name: "Cobra Hold", targetMuscles: ["Lower Back", "Chest"],
              instructions: "Face down, press through your hands to lift your chest, hips staying on the floor.",
              correctPosture: "Keep shoulders down away from your ears.",
              difficulty: .beginner, met: 2.5, recommendedDurationMinutes: 2),
        .init(id: "reverseplank", name: "Reverse Plank", targetMuscles: ["Glutes", "Lower Back", "Shoulders"],
              instructions: "Sit with legs extended, hands behind you. Lift hips so your body forms a straight line.",
              correctPosture: "Point fingers toward your feet; keep hips lifted throughout.",
              difficulty: .advanced, met: 4.0, recommendedDurationMinutes: 2),
        .init(id: "floorbackext", name: "Floor Back Extension", targetMuscles: ["Lower Back"],
              instructions: "Face down, hands behind head or extended. Lift chest off the floor.",
              correctPosture: "Lift with your back muscles, not by yanking your neck.",
              difficulty: .beginner, met: 3.5, recommendedDurationMinutes: 2),
        .init(id: "pushups", name: "Pushups", targetMuscles: ["Chest", "Triceps", "Shoulders"],
              instructions: "Hands shoulder-width apart, lower your chest to the floor, then press back up.",
              correctPosture: "Keep your body in a straight line, core braced.",
              difficulty: .intermediate, met: 8.0, recommendedDurationMinutes: 3),
        .init(id: "pullups", name: "Pull Ups", targetMuscles: ["Back", "Biceps"],
              instructions: "Hang from a bar, pull your chin above the bar, then lower with control.",
              correctPosture: "Avoid kipping/swinging; control the descent.",
              difficulty: .advanced, met: 8.0, recommendedDurationMinutes: 3),
    ]

    static func find(_ id: String) -> WorkoutExercise? { all.first { $0.id == id } }
}

/// User-created workout cards. The video is an imported media track, so the
/// file remains in one library and is not copied again for every workout.
struct CustomWorkout: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var thumbnailSymbol: String
    var thumbnailFileName: String?
    var videoTrackID: UUID?
    var targetDurationMinutes: Int
    /// User-selected estimate at a 70 kg reference weight. The live estimate
    /// still adjusts for the weight entered in Workout settings.
    var caloriesPerMinute: Double?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, thumbnailSymbol: String = "figure.strengthtraining.functional", thumbnailFileName: String? = nil, videoTrackID: UUID? = nil, targetDurationMinutes: Int = 15, caloriesPerMinute: Double? = 5, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.thumbnailSymbol = thumbnailSymbol
        self.thumbnailFileName = thumbnailFileName
        self.videoTrackID = videoTrackID
        self.targetDurationMinutes = targetDurationMinutes
        self.caloriesPerMinute = caloriesPerMinute
        self.createdAt = createdAt
    }

    var asExercise: WorkoutExercise {
        WorkoutExercise(
            id: "custom-\(id.uuidString)", name: name, targetMuscles: ["Custom workout"],
            instructions: "Follow your chosen workout plan and stop the session when you are finished.",
            correctPosture: "Use controlled movement and stop if you feel pain.",
            difficulty: .beginner, met: max(1, (caloriesPerMinute ?? 5) * 60 / 70), recommendedDurationMinutes: targetDurationMinutes
        )
    }
}

struct WorkoutBreak: Identifiable, Codable, Equatable {
    let id: UUID
    let start: Date
    var end: Date?
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }

    init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}

enum WorkoutActivityType: String, Codable {
    case exercise
    case rest
}

struct WorkoutActivity: Codable, Identifiable, Equatable {
    let id: UUID
    let type: WorkoutActivityType
    let exerciseID: String?
    let duration: TimeInterval

    init(id: UUID = UUID(), type: WorkoutActivityType, exerciseID: String? = nil, duration: TimeInterval) {
        self.id = id
        self.type = type
        self.exerciseID = exerciseID
        self.duration = duration
    }
}

/// Persisted GPS interval data shared by HIIT and the independent Walking
/// mode. This makes every lap available after the live screen is dismissed.
struct WorkoutLapRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let number: Int
    let isWalking: Bool
    let duration: TimeInterval
    let distanceMeters: Double
    let averageSpeedKmh: Double

    init(id: UUID = UUID(), number: Int, isWalking: Bool, duration: TimeInterval, distanceMeters: Double, averageSpeedKmh: Double) {
        self.id = id
        self.number = number
        self.isWalking = isWalking
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageSpeedKmh = averageSpeedKmh
    }
}

/// One logged set within a WorkoutSession — the only way today's bodyweight,
/// duration-based sessions can also carry strength-progression data
/// (weightKg is optional since bodyweight exercises like Push Ups have none).
struct WorkoutSet: Identifiable, Codable, Equatable {
    let id: UUID
    var reps: Int
    var weightKg: Double?
    var recordedAt: Date
    init(id: UUID = UUID(), reps: Int, weightKg: Double? = nil, recordedAt: Date = Date()) {
        self.id = id; self.reps = reps; self.weightKg = weightKg; self.recordedAt = recordedAt
    }
}

struct WorkoutExerciseSegment: Codable, Identifiable, Equatable {
    let id: UUID
    let exerciseID: String
    let start: Date
    var end: Date?
    var sets: [WorkoutSet]
    
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
    
    init(id: UUID = UUID(), exerciseID: String, start: Date = Date(), end: Date? = nil, sets: [WorkoutSet] = []) {
        self.id = id
        self.exerciseID = exerciseID
        self.start = start
        self.end = end
        self.sets = sets
    }
}

struct WorkoutRestSegment: Codable, Identifiable, Equatable {
    let id: UUID
    let start: Date
    var end: Date?
    
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
    
    init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}

enum WorkoutSegment: Codable, Identifiable, Equatable {
    case exercise(WorkoutExerciseSegment)
    case rest(WorkoutRestSegment)
    
    var id: UUID {
        switch self {
        case .exercise(let s): return s.id
        case .rest(let s): return s.id
        }
    }
}

/// A completed (or in-progress) workout session, tracking active time and
/// break time separately per the spec's explicit "a paused workout is
/// effectively a break, and the dashboard should track it explicitly."
struct WorkoutSession: Identifiable, Codable, Equatable {
    let id: UUID
    // Legacy fields kept for backward compatibility (decoding old JSON)
    let exerciseID: String?
    let startedAt: Date
    var endedAt: Date?
    var breaks: [WorkoutBreak]?
    var caloriesBurned: Double
    
    /// GPS data is optional so every session saved by older app versions
    /// remains decodable without migration.
    var distanceMeters: Double?
    var recordedMovingDuration: TimeInterval?
    var averageSpeedKmh: Double?
    var laps: [WorkoutLapRecord]?
    /// Optional for the same reason as the GPS fields — older saved sessions
    /// decode with no sets rather than failing to decode at all.
    var sets: [WorkoutSet]?
    var activities: [WorkoutActivity]?
    var segments: [WorkoutSegment]?
    var date: Date { Calendar.current.startOfDay(for: startedAt) }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        caloriesBurned: Double = 0,
        segments: [WorkoutSegment]? = nil
    ) {
        self.id = id
        self.exerciseID = nil
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.breaks = []
        self.caloriesBurned = caloriesBurned
        self.segments = segments
    }

    init(
        id: UUID = UUID(),
        exerciseID: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        breaks: [WorkoutBreak]? = nil,
        caloriesBurned: Double = 0,
        distanceMeters: Double? = nil,
        recordedMovingDuration: TimeInterval? = nil,
        averageSpeedKmh: Double? = nil,
        laps: [WorkoutLapRecord]? = nil,
        sets: [WorkoutSet]? = nil,
        activities: [WorkoutActivity]? = nil,
        segments: [WorkoutSegment]? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.breaks = breaks
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
        self.recordedMovingDuration = recordedMovingDuration
        self.averageSpeedKmh = averageSpeedKmh
        self.laps = laps
        self.sets = sets
        self.activities = activities
        self.segments = segments
    }

    var totalDuration: TimeInterval {
        guard let endedAt else { return Date().timeIntervalSince(startedAt) }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
    
    var activeSegments: [WorkoutExerciseSegment] {
        segments?.compactMap {
            if case let .exercise(ex) = $0 { return ex }
            return nil
        } ?? []
    }
    
    var restSegments: [WorkoutRestSegment] {
        segments?.compactMap {
            if case let .rest(rest) = $0 { return rest }
            return nil
        } ?? []
    }

    var activeDuration: TimeInterval {
        if !activeSegments.isEmpty {
            return activeSegments.reduce(0) { $0 + $1.duration }
        }
        if let recordedMovingDuration {
            return recordedMovingDuration
        }
        // `segments == nil` means segment tracking never ran for this session
        // at all — a legacy session predating the segments model, built with
        // only the old exerciseID/breaks fields (as several tests, and any
        // hand-built fixture, do). Falls back to the pre-segments computation
        // (total minus recorded breaks) instead of silently reading as zero
        // active time for a session that plainly had some.
        // `segments == []` (present, explicitly empty) means tracking DID
        // run and genuinely recorded no activity — 0 is the honest answer
        // there, not an assumed full duration.
        guard segments != nil else {
            return max(0, totalDuration - totalBreakDuration)
        }
        return 0
    }
    
    var totalBreakDuration: TimeInterval {
        restSegments.reduce(0) { $0 + $1.duration } + (breaks?.reduce(0) { $0 + $1.duration } ?? 0)
    }

    var breakCount: Int {
        restSegments.count + (breaks?.count ?? 0)
    }
    var averageBreakDuration: TimeInterval {
        breakCount > 0 ? totalBreakDuration / Double(breakCount) : 0
    }
    var longestBreak: TimeInterval {
        let restDurations = restSegments.map(\.duration)
        let breakDurations = breaks?.map(\.duration) ?? []
        return (restDurations + breakDurations).max() ?? 0
    }
    var shortestBreak: TimeInterval {
        let restDurations = restSegments.map(\.duration)
        let breakDurations = breaks?.map(\.duration) ?? []
        return (restDurations + breakDurations).min() ?? 0
    }
}

/// Repairs sessions left with an open segment (`end == nil`) by a workout
/// that was never finalized via `stop()` — the app was killed, crashed, or
/// relaunched mid-workout. WorkoutExerciseSegment/WorkoutRestSegment.duration
/// falls back to `Date() - start` for any open segment, and
/// WorkoutStatsService aggregates every persisted session regardless of
/// completion state (intentional — it's how "today" updates live while a
/// workout is genuinely in progress). An open segment on a session found at
/// app-launch time is provably orphaned: WorkoutRuntime.shared.active always
/// starts nil for a fresh process and is never reconstructed from persisted
/// state, so nothing will ever call stop() on that session again — its
/// reported duration would otherwise grow without bound, forever, every time
/// stats are recomputed.
///
/// A pure function (no singletons, no disk I/O) so both AppStore and tests
/// can exercise the exact repair logic deterministically.
enum WorkoutSessionIntegrity {
    /// Closes every open segment using the session's own `endedAt` — the
    /// timestamp of its last periodic autosave, and the latest moment there
    /// is real evidence the segment was still open. Never uses `Date()`, so
    /// the repaired duration is fixed once and never changes on a later read.
    /// Sessions with no open segment are returned unchanged.
    static func finalizingOrphanedSegments(in sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.map { original in
            guard let segs = original.segments, segs.contains(where: isOpen) else { return original }
            var session = original
            let cutoff = original.endedAt ?? original.startedAt
            session.segments = segs.map { seg in
                switch seg {
                case .exercise(var ex):
                    if ex.end == nil { ex.end = max(cutoff, ex.start) }
                    return .exercise(ex)
                case .rest(var rest):
                    if rest.end == nil { rest.end = max(cutoff, rest.start) }
                    return .rest(rest)
                }
            }
            return session
        }
    }

    private static func isOpen(_ segment: WorkoutSegment) -> Bool {
        switch segment {
        case .exercise(let ex): return ex.end == nil
        case .rest(let rest): return rest.end == nil
        }
    }
}

/// Standard MET-based estimate: calories = MET × weight(kg) × duration(hours).
/// This is the widely-used approximation (the same one fitness trackers use
/// without a heart-rate sensor) — not a clinical measurement, which is why
/// it's presented as an estimate everywhere in the UI.
enum CalorieCalculator {
    static func estimate(met: Double, weightKg: Double, activeSeconds: TimeInterval, multiplier: Double = 1) -> Double {
        let hours = activeSeconds / 3600
        return met * weightKg * hours * multiplier
    }
}
