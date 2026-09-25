import SwiftUI

// MARK: - Projection (pure, testable)

/// A read-only projection of a completed `WorkoutSession` into an ordered list
/// of display rows for the "Workout Complete" screen.
///
/// Problem 1 is a projection/UI change, not a data change: `WorkoutSession`
/// already persists the full chronological breakdown in `segments`
/// (`.exercise` / `.rest`, each with its own start/end/duration, and exercise
/// segments carrying `sets`). This type does not persist anything, does not
/// recompute session rollups (Duration / Active Time / Break Time / …), and
/// does not create a second model — it only *reads* `session.segments` in
/// order. The session remains the source of truth.
///
/// Kept as a plain value type with an injected name resolver so the ordering,
/// numbering, set-preservation and name-fallback rules can be unit-tested
/// without SwiftUI.
struct WorkoutBreakdown: Equatable {

    struct SetLine: Equatable, Identifiable {
        let id: UUID
        /// 1-based position within its exercise.
        let index: Int
        let reps: Int
        /// `nil` for bodyweight exercises — never rendered as "0 kg".
        let weightKg: Double?
    }

    struct ExerciseRow: Equatable, Identifiable {
        /// The underlying `WorkoutExerciseSegment.id` — stable, so SwiftUI
        /// diffing and tests can address a specific row.
        let id: UUID
        /// 1-based, counting exercise segments only (rests are not numbered).
        let number: Int
        let name: String
        let duration: TimeInterval
        /// Only the sets actually recorded in the session. Empty ⇒ the row
        /// shows just "Active", never a fabricated "3 × 10".
        let sets: [SetLine]
    }

    struct RestRow: Equatable, Identifiable {
        let id: UUID
        let duration: TimeInterval
    }

    enum Row: Equatable, Identifiable {
        case exercise(ExerciseRow)
        case rest(RestRow)

        var id: UUID {
            switch self {
            case .exercise(let e): return e.id
            case .rest(let r): return r.id
            }
        }
    }

    /// Every segment, in the exact order it was persisted.
    let rows: [Row]
    /// Count of exercise segments.
    let exerciseCount: Int
    /// Count of rest segments (does not include the legacy `breaks` array —
    /// the summary card above the breakdown still reports `session.breakCount`
    /// for that).
    let restCount: Int

    /// - Parameter resolveName: maps a `WorkoutExerciseSegment.exerciseID` to a
    ///   user-facing name. Injected so an unresolved id can never crash the
    ///   Complete screen (see `resolveExerciseName`).
    init(session: WorkoutSession, resolveName: (String) -> String) {
        var built: [Row] = []
        var exerciseNumber = 0
        var restNumber = 0

        for segment in session.segments ?? [] {
            switch segment {
            case .exercise(let ex):
                exerciseNumber += 1
                let sets = ex.sets.enumerated().map { offset, set in
                    SetLine(id: set.id, index: offset + 1, reps: set.reps, weightKg: set.weightKg)
                }
                built.append(.exercise(ExerciseRow(
                    id: ex.id,
                    number: exerciseNumber,
                    name: resolveName(ex.exerciseID),
                    duration: ex.duration,
                    sets: sets
                )))
            case .rest(let rest):
                restNumber += 1
                built.append(.rest(RestRow(id: rest.id, duration: rest.duration)))
            }
        }

        self.rows = built
        self.exerciseCount = exerciseNumber
        self.restCount = restNumber
    }

    var isEmpty: Bool { rows.isEmpty }
}

extension WorkoutBreakdown {
    /// Convenience projection that resolves names against the app's exercise
    /// catalog and the user's custom workouts.
    init(session: WorkoutSession, store: AppStore) {
        self.init(session: session) { Self.resolveExerciseName($0, store: store) }
    }

    /// Name resolution per the PRD:
    ///   1. the fixed catalog (`WorkoutExercise.all`),
    ///   2. a stored custom workout's name (`custom-<uuid>` ids),
    ///   3. the literal fallback `"Custom Exercise"`.
    /// `WorkoutExercise.find` returns `nil` (never throws) for an unknown id,
    /// so an orphaned segment renders with the fallback rather than crashing.
    static func resolveExerciseName(_ exerciseID: String, store: AppStore) -> String {
        if let known = WorkoutExercise.find(exerciseID) { return known.name }
        if exerciseID.hasPrefix("custom-"),
           let uuid = UUID(uuidString: String(exerciseID.dropFirst(7))),
           let custom = store.customWorkouts.first(where: { $0.id == uuid }) {
            return custom.name
        }
        return "Custom Exercise"
    }
}

/// Shared `mm:ss` (or `h:mm:ss` past an hour) formatter for the breakdown.
/// The existing `WorkoutSummaryView.formatted` is left untouched so the
/// summary card does not change; this one adds hour handling for long
/// workouts, which the breakdown can surface per-exercise.
enum WorkoutBreakdownFormat {
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    static func weight(_ kg: Double) -> String {
        if kg == kg.rounded() {
            return "\(Int(kg)) kg"
        }
        return String(format: "%.1f kg", kg)
    }
}

// MARK: - View

/// The "Workout Breakdown" section shown on the Complete screen, below the
/// existing summary card. Renders `WorkoutBreakdown.rows` in order; scrolling
/// is provided by the parent (`WorkoutSummaryView`'s `ScrollView`).
struct WorkoutBreakdownView: View {
    let session: WorkoutSession
    let breakdown: WorkoutBreakdown

    init(session: WorkoutSession, store: AppStore) {
        self.session = session
        self.breakdown = WorkoutBreakdown(session: session, store: store)
    }

    /// Test/preview seam.
    init(session: WorkoutSession, breakdown: WorkoutBreakdown) {
        self.session = session
        self.breakdown = breakdown
    }

    var body: some View {
        if !breakdown.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workout Breakdown")
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text(countSummary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ForEach(Array(breakdown.rows.enumerated()), id: \.element.id) { pair in
                            switch pair.element {
                            case .exercise(let row):
                                if pair.offset > 0 { Divider().overlay(Theme.cardBorder) }
                                exerciseRow(row)
                            case .rest(let row):
                                restRow(row)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                breakSummary
            }
        }
    }

    // MARK: Rows

    private func exerciseRow(_ row: WorkoutBreakdown.ExerciseRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text("\(row.number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.cardBackground))
                    .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))

                Text(row.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.primaryText)

                Spacer(minLength: Theme.Spacing.s)

                Text(WorkoutBreakdownFormat.duration(row.duration))
                    .font(Theme.Font.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }

            Text(detailLine(for: row))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryText)
                .padding(.leading, 26 + Theme.Spacing.m)

            if !row.sets.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(row.sets) { set in
                        HStack(spacing: Theme.Spacing.m) {
                            Text("Set \(set.index)")
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("\(set.reps) reps")
                                .foregroundStyle(Theme.primaryText)
                            if let weight = set.weightKg {
                                Text(WorkoutBreakdownFormat.weight(weight))
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                        .font(Theme.Font.caption)
                        .monospacedDigit()
                    }
                }
                .padding(.leading, 26 + Theme.Spacing.m)
                .padding(.top, 2)
            }
        }
    }

    private func restRow(_ row: WorkoutBreakdown.RestRow) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("—")
                .foregroundStyle(Theme.secondaryText)
            Text("Rest")
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Theme.Spacing.s)
            Text(WorkoutBreakdownFormat.duration(row.duration))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
        .font(Theme.Font.secondary)
        .padding(.leading, 26 + Theme.Spacing.m)
    }

    private var breakSummary: some View {
        HStack(spacing: Theme.Spacing.m) {
            breakStat("Breaks", "\(session.breakCount)")
            breakStat("Average", session.breakCount > 0
                      ? WorkoutBreakdownFormat.duration(session.averageBreakDuration) : "—")
            breakStat("Longest", session.breakCount > 0
                      ? WorkoutBreakdownFormat.duration(session.longestBreak) : "—")
        }
    }

    private func breakStat(_ title: String, _ value: String) -> some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Copy

    private var countSummary: String {
        let exercises = "\(breakdown.exerciseCount) exercise\(breakdown.exerciseCount == 1 ? "" : "s")"
        guard breakdown.restCount > 0 else { return exercises }
        return exercises + " · \(breakdown.restCount) break\(breakdown.restCount == 1 ? "" : "s")"
    }

    private func detailLine(for row: WorkoutBreakdown.ExerciseRow) -> String {
        guard !row.sets.isEmpty else { return "Active" }
        return "\(row.sets.count) set\(row.sets.count == 1 ? "" : "s") · Active"
    }
}
