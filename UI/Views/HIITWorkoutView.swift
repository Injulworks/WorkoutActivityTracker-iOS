import SwiftUI
import Combine
import CoreLocation
import UIKit
import AVFoundation

/// Real elapsed time since the last tick, uncapped (clamped only against a
/// negative gap, e.g. a backward clock adjustment).
///
/// Root cause: the ticker driving `HIITWorkoutView.updateTimes`
/// (0.25s) and the one driving `HIITRuntime.checkpointIfNeeded` (1s, in
/// `RootView`) are both main-RunLoop `Timer.publish` instances — they stop
/// firing the instant iOS suspends the app (lock screen, home button, a
/// brief app switch), and the host app's `scenePhase` handling never
/// reconciles the gap on return. `updateTimes` used to compute this same
/// delta but capped it at `min(2, ...)` seconds, so on the very next tick
/// after any background gap, moving time / lap time / calories / the
/// persisted `recordedMovingDuration` all silently lost almost the entire
/// backgrounded duration — while `elapsed` (plain wall-clock) and GPS
/// distance (tracked independently via `didUpdateLocations`, which keeps
/// running in the background) stayed correct. That mismatch is why a walk
/// could show correct total time and distance but implausibly low moving
/// time/calories. `restoreLiveSessionIfNeeded` and `checkpointIfNeeded`
/// already computed this same gap uncapped — this shared helper makes every
/// caller agree instead of `updateTimes` being the one inconsistent path.
func activeTimeDelta(since lastTick: Date?, at now: Date) -> TimeInterval {
    max(0, now.timeIntervalSince(lastTick ?? now))
}

/// Confirmed on-device bug (distinct from the time-gap issue above, same
/// family): a crash/relaunch mid-session restored distance frozen at
/// whatever the last checkpoint captured (e.g. 0.7 km after 25 real
/// minutes) while `activeTimeDelta` correctly caught time up to the wall
/// clock — calories looked right, distance didn't. `HIITLocationService`'s
/// live GPS accumulator only exists in-memory; once the process actually
/// dies, the real path during the gap is gone and can't be recovered
/// exactly. Estimating it from this session's own already-observed average
/// pace (distance so far / moving time so far) is far more honest than
/// silently freezing distance while time keeps moving. Returns 0 (no
/// adjustment) when there's no gap or no basis yet for a pace estimate.
func estimatedGapDistanceMeters(observedDistanceMeters: Double, observedMovingSeconds: TimeInterval, gapSeconds: TimeInterval) -> Double {
    guard gapSeconds > 0, observedMovingSeconds > 0, observedDistanceMeters > 0 else { return 0 }
    let averageSpeedMetersPerSecond = observedDistanceMeters / observedMovingSeconds
    return averageSpeedMetersPerSecond * gapSeconds
}

/// GPS HIIT tracker. Timers are derived from wall-clock dates rather than
/// incremented once per Timer event, so a busy UI cannot make them run slow.
struct HIITWorkoutView: View {
    let weightKg: Double
    let walkingOnly: Bool
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var location = HIITLocationService.shared
    @ObservedObject private var runtime = HIITRuntime.shared
    @State private var startsWalking = true
    @State private var isRunning = false
    @State private var isWalking = true
    @State private var elapsed: TimeInterval = 0
    @State private var movingElapsed: TimeInterval = 0
    @State private var lapElapsed: TimeInterval = 0
    @State private var sessionStartedAt: Date?
    @State private var lapStartedAt: Date?
    @State private var lapHistory: [HIITLap] = []
    @State private var completedSummary: HIITSummary?
    @State private var sessionID = UUID()
    @State private var lastTickAt: Date?
    @State private var lastAutosaveAt: Date?
    @State private var breaks: [WorkoutBreak] = []
    @State private var walkingLapSeconds = 60.0
    @State private var joggingLapSeconds = 60.0
    @State private var announcedLapTarget = false
    @State private var showingPauseConfirmation = false
    @State private var showingEndConfirmation = false
    @Environment(\.dismiss) private var dismiss
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(weightKg: Double, walkingOnly: Bool = false) {
        self.weightKg = weightKg
        self.walkingOnly = walkingOnly
        _startsWalking = State(initialValue: true)
        _isWalking = State(initialValue: true)
    }

    private var walkingSeconds: TimeInterval { lapHistory.filter(\.isWalking).reduce(0) { $0 + $1.duration } + (isWalking ? lapElapsed : 0) }
    private var joggingSeconds: TimeInterval { lapHistory.filter { !$0.isWalking }.reduce(0) { $0 + $1.duration } + (!isWalking ? lapElapsed : 0) }
    private var calories: Double { CalorieCalculator.estimate(met: 3.5, weightKg: weightKg, activeSeconds: walkingSeconds, multiplier: store.settings.workoutCalorieMultiplier) + CalorieCalculator.estimate(met: 7, weightKg: weightKg, activeSeconds: joggingSeconds, multiplier: store.settings.workoutCalorieMultiplier) }
    private var averageSpeedKmh: Double { movingElapsed > 0 ? location.distanceMeters / movingElapsed * 3.6 : 0 }
    private var currentPace: String { pace(for: location.speedKmh) }
    private var averagePace: String { pace(for: averageSpeedKmh) }

    var body: some View {
        ScrollView { VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: 8) {
                Text(isRunning ? (isWalking ? "WALKING · CURRENT LAP" : "JOGGING · CURRENT LAP") : (walkingOnly ? "WALKING GPS TRACKER" : "HIIT GPS TRACKER")).font(.system(size: 15, weight: .bold)).foregroundStyle(isWalking ? Theme.accent : .orange)
                Text(time(elapsed)).font(.system(size: 62, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.primaryText)
                Text("TOTAL TIME").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                Text("CURRENT \(isWalking ? "WALKING" : "JOGGING") LAP · \(time(lapElapsed))")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(isWalking ? Theme.accent : .orange)
                Divider().padding(.vertical, Theme.Spacing.s)
                Text(String(format: "%.2f", location.distanceMeters / 1000)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.primaryText)
                Text("KILOMETRES").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
            }.padding(.vertical, Theme.Spacing.l)
            HStack(spacing: 0) { bigMetric(currentPace, "CURRENT PACE"); Divider().frame(height: 86); bigMetric(averagePace, "AVERAGE PACE") }
            HStack(spacing: Theme.Spacing.m) { stat("Current speed", speedText(location.speedKmh)); stat("Average speed", speedText(averageSpeedKmh)); stat("Calories", "\(Int(calories)) kcal") }
            HStack(spacing: Theme.Spacing.m) { stat("Moving time", time(movingElapsed)); stat("Paused time", time(max(0, elapsed - movingElapsed))); stat("GPS accuracy", location.accuracyText) }
            GlassCard { VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if !walkingOnly { Picker("Start with", selection: $startsWalking) { Text("Walking").tag(true); Text("Jogging").tag(false) }.disabled(elapsed > 0) }
                intervalStepper(title: "Walking target", seconds: $walkingLapSeconds, color: Theme.accent)
                if !walkingOnly { intervalStepper(title: "Jogging target", seconds: $joggingLapSeconds, color: .orange) }
                Text(walkingOnly ? "Separate in-app walking session. It is recorded separately from HIIT sessions." : "Tap Next Lap whenever you change from walking to jogging or jogging to walking.").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                HStack { Label("GPS", systemImage: "location.fill"); Spacer(); Text(location.statusMessage ?? "Connected") }.font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                if location.statusMessage != nil { Button("Open Location Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(Theme.Font.caption).foregroundStyle(Theme.accent) }
            } }
            if !lapHistory.isEmpty { GlassCard { VStack(alignment: .leading, spacing: Theme.Spacing.s) { Text("Lap history").font(Theme.Font.cardTitle).foregroundStyle(Theme.primaryText); ForEach(lapHistory.reversed()) { lap in HStack { Text("Lap \(lap.number) · \(lap.isWalking ? "Walking" : "Jogging")").foregroundStyle(lap.isWalking ? Theme.accent : .orange); Spacer(); Text("\(time(lap.duration)) · \(speedText(lap.averageSpeedKmh))") }.font(Theme.Font.caption) } } } }
        }.padding() }
        .background(Theme.background).navigationTitle(walkingOnly ? "Walking" : "HIIT")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(sessionStartedAt == nil ? "Close" : "Minimize") { if sessionStartedAt != nil { saveCheckpoint(at: Date()); syncLiveSession() }; dismiss() } }
            ToolbarItem(placement: .navigationBarTrailing) { NavigationLink { HIITTrackerView(exerciseID: walkingOnly ? "walking" : "hiit", title: walkingOnly ? "Walking Stats" : "HIIT Stats") } label: { Image(systemName: "chart.xyaxis.line") } }
        }
        .onReceive(ticker) { now in updateTimes(now) }
        .onAppear { runtime.isPresented = true; restoreLiveSessionIfNeeded() }
        .safeAreaInset(edge: .bottom) { stickyControls }
        .onDisappear {
            runtime.isPresented = false
            // Never lose a 20–50 minute HIIT workout just because the user
            // navigates back. The same session ID is updated, not duplicated.
            if elapsed > 0 { saveCheckpoint(at: Date()) }
            // Keep the shared Core Location manager alive. The user can move
            // to Meditation/another tab and return through the floating bar.
            syncLiveSession()
        }
        .interactiveDismissDisabled(sessionStartedAt != nil)
        .confirmationDialog("Pause this session?", isPresented: $showingPauseConfirmation, titleVisibility: .visible) {
            Button("Pause") { pauseSession(at: Date(), spoken: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Time, calories and lap progress will be saved. You can resume later.") }
        .confirmationDialog("End this session?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End & Save", role: .destructive) { finish() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This saves your time, distance, laps and calories to Workout statistics.") }
        .sheet(item: $completedSummary, onDismiss: { if !runtime.isActive { dismiss() } }) { summary in HIITSummaryView(summary: summary) }
    }

    private var stickyControls: some View {
        VStack(spacing: 8) {
            if isRunning && !walkingOnly {
                Button { finishLapAndSwitch() } label: {
                    Label("NEXT LAP · \(isWalking ? "JOGGING" : "WALKING")", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.black)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    if isRunning { showingPauseConfirmation = true }
                    else { toggleRunning() }
                } label: {
                    Label(isRunning ? "PAUSE" : (elapsed == 0 ? (walkingOnly ? "START WALKING" : "START HIIT") : "RESUME"), systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.black)
                        .background(Theme.primaryText, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                if elapsed > 0 {
                    Button { showingEndConfirmation = true } label: {
                        Label(walkingOnly ? "END WALK" : "END HIIT", systemImage: "stop.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Theme.destructive, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(Theme.cardBorder) }
    }

    private func updateTimes(_ now: Date) {
        guard let sessionStartedAt else { return }
        elapsed = now.timeIntervalSince(sessionStartedAt)
        defer { lastTickAt = now }
        guard isRunning else { return }
        let delta = activeTimeDelta(since: lastTickAt, at: now)
        movingElapsed += delta
        lapElapsed += delta
        let target = isWalking ? walkingLapSeconds : joggingLapSeconds
        if !announcedLapTarget, lapElapsed >= target {
            announcedLapTarget = true
            HIITVoiceCoach.shared.say("\(isWalking ? "Walking" : "Jogging") lap target reached")
        }
        // Never stop a HIIT/walking session because GPS reports low motion.
        // GPS drift and poor points are filtered by HIITLocationService, but
        // only the user may pause or end an active session.
        if now.timeIntervalSince(lastAutosaveAt ?? .distantPast) >= 5 {
            lastAutosaveAt = now
            saveCheckpoint(at: now)
        }
        syncLiveSession()
    }
    private func toggleRunning() {
        if elapsed == 0 {
            // A fresh start must always begin at exactly 0.00 km. GPS's first
            // coordinate only establishes the baseline and is never counted.
            location.reset()
            isWalking = startsWalking
            announcedLapTarget = false
            sessionStartedAt = Date()
            lapStartedAt = Date()
            lastTickAt = Date()
            lastAutosaveAt = Date()
            isRunning = true
            location.start()
            syncLiveSession()
            HIITVoiceCoach.shared.say(isWalking ? "Walking started" : "Jogging started")
        }
        else if isRunning { pauseSession(at: Date(), spoken: false) }
        else { resumeSession(at: Date()) }
    }
    private func pauseSession(at date: Date, spoken: Bool) {
        guard isRunning else { return }
        isRunning = false
        breaks.append(WorkoutBreak(start: date))
        location.stop()
        saveCheckpoint(at: date)
        syncLiveSession()
        if spoken { HIITVoiceCoach.shared.say(walkingOnly ? "Walking session paused" : "HIIT session paused") }
    }
    private func resumeSession(at date: Date) {
        if let index = breaks.indices.last, breaks[index].end == nil { breaks[index].end = date }
        lastTickAt = date
        location.clearAutoPause()
        isRunning = true
        location.start()
        HIITVoiceCoach.shared.say(walkingOnly ? "Walking resumed" : "HIIT session resumed")
        syncLiveSession()
    }
    private func finishLapAndSwitch() { guard lapElapsed > 0 else { return }; lapHistory.append(HIITLap(number: lapHistory.count + 1, isWalking: isWalking, duration: lapElapsed, distanceMeters: location.lapDistanceMeters, averageSpeedKmh: lapElapsed > 0 ? location.lapDistanceMeters / lapElapsed * 3.6 : 0)); isWalking.toggle(); lapStartedAt = Date(); lapElapsed = 0; announcedLapTarget = false; location.beginLap(); HIITVoiceCoach.shared.say(isWalking ? "Walking lap started" : "Jogging lap started") }
    private func finish() {
        guard elapsed > 0 else { return }
        // Finishing must record the last lap without toggling to a new lap or
        // announcing “Walking lap started” after the workout has ended.
        if lapElapsed > 0 {
            lapHistory.append(HIITLap(number: lapHistory.count + 1, isWalking: isWalking, duration: lapElapsed, distanceMeters: location.lapDistanceMeters, averageSpeedKmh: lapElapsed > 0 ? location.lapDistanceMeters / lapElapsed * 3.6 : 0))
        }
        if isRunning { pauseSession(at: Date(), spoken: false) }
        if let index = breaks.indices.last, breaks[index].end == nil { breaks[index].end = Date() }
        isRunning = false; location.stop()
        let summary = HIITSummary(walkingOnly: walkingOnly, duration: elapsed, distanceMeters: location.distanceMeters, laps: lapHistory.count, calories: calories)
        // This is a normal completed WorkoutSession, so it is included in
        // the main Workout dashboard and weekly/monthly workout statistics.
        let started = sessionStartedAt ?? Date().addingTimeInterval(-elapsed)
        store.upsertWorkoutSession(makeWorkoutSession(startedAt: started, endedAt: Date()))
        completedSummary = summary
        HIITVoiceCoach.shared.say(walkingOnly ? "Walking stopped." : "HIIT session ended.")
        elapsed = 0; movingElapsed = 0; lapElapsed = 0; sessionStartedAt = nil; lapStartedAt = nil; lapHistory = []; isWalking = startsWalking; announcedLapTarget = false; lastTickAt = nil; lastAutosaveAt = nil; breaks = []; sessionID = UUID(); location.reset(); runtime.clear()
    }
    private func saveCheckpoint(at date: Date) {
        guard let started = sessionStartedAt, elapsed > 0 else { return }
        // Same stable ID is overwritten every five minutes, not duplicated.
        // The checkpoint is completed so the main dashboard immediately shows it.
        store.upsertWorkoutSession(makeWorkoutSession(startedAt: started, endedAt: date))
    }
    private func syncLiveSession() {
        runtime.isActive = sessionStartedAt != nil
        runtime.isRunning = isRunning
        runtime.walkingOnly = walkingOnly
        runtime.isWalking = isWalking
        runtime.startedAt = sessionStartedAt
        runtime.lapStartedAt = lapStartedAt
        runtime.sessionID = sessionID
        runtime.movingElapsed = movingElapsed
        runtime.lapElapsed = lapElapsed
        runtime.breaks = breaks
        runtime.startsWalking = startsWalking
        runtime.walkingLapSeconds = walkingLapSeconds
        runtime.joggingLapSeconds = joggingLapSeconds
        runtime.lapHistory = lapHistory
        runtime.announcedLapTarget = announcedLapTarget
        runtime.lastTickAt = lastTickAt
        runtime.distanceMeters = location.distanceMeters
        runtime.lapDistanceMeters = location.lapDistanceMeters
        runtime.persist()
    }
    private func restoreLiveSessionIfNeeded() {
        guard runtime.isActive, runtime.walkingOnly == walkingOnly, let started = runtime.startedAt else { return }
        sessionStartedAt = started
        lapStartedAt = runtime.lapStartedAt ?? started
        sessionID = runtime.sessionID
        isRunning = runtime.isRunning
        isWalking = runtime.isWalking
        movingElapsed = runtime.movingElapsed
        lapElapsed = runtime.lapElapsed
        breaks = runtime.breaks
        startsWalking = runtime.startsWalking
        walkingLapSeconds = runtime.walkingLapSeconds
        joggingLapSeconds = runtime.joggingLapSeconds
        lapHistory = runtime.lapHistory
        announcedLapTarget = runtime.announcedLapTarget
        elapsed = Date().timeIntervalSince(started)
        let now = Date()
        var gap: TimeInterval = 0
        if isRunning {
            gap = activeTimeDelta(since: runtime.lastTickAt, at: now)
            movingElapsed += gap
            lapElapsed += gap
        }
        // See estimatedGapDistanceMeters's own doc comment for why this
        // exists — distance must be reconciled for the same gap time above
        // is reconciled for, not left frozen at the stale checkpoint value.
        let estimatedGapDistance = estimatedGapDistanceMeters(observedDistanceMeters: runtime.distanceMeters, observedMovingSeconds: runtime.movingElapsed, gapSeconds: gap)
        location.restore(distanceMeters: runtime.distanceMeters + estimatedGapDistance, lapDistanceMeters: runtime.lapDistanceMeters + estimatedGapDistance)
        lastTickAt = now
        if isRunning { location.start() }
    }
    private func makeWorkoutSession(startedAt: Date, endedAt: Date) -> WorkoutSession {
        var records = lapHistory.map(\.workoutRecord)
        if lapElapsed > 0 {
            records.append(WorkoutLapRecord(number: records.count + 1, isWalking: isWalking, duration: lapElapsed, distanceMeters: location.lapDistanceMeters, averageSpeedKmh: lapElapsed > 0 ? location.lapDistanceMeters / lapElapsed * 3.6 : 0))
        }
        return WorkoutSession(
            id: sessionID,
            exerciseID: walkingOnly ? "walking" : "hiit",
            startedAt: startedAt,
            endedAt: endedAt,
            breaks: breaks,
            caloriesBurned: calories,
            distanceMeters: location.distanceMeters,
            recordedMovingDuration: movingElapsed,
            averageSpeedKmh: averageSpeedKmh,
            laps: records
        )
    }
    private func bigMetric(_ value: String, _ title: String) -> some View { VStack(spacing: 6) { Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.primaryText); Text(title).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText) }.frame(maxWidth: .infinity) }
    private func stat(_ title: String, _ value: String) -> some View { GlassCard { VStack(spacing: 5) { Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.primaryText); Text(title).font(Theme.Font.caption).multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText) }.frame(maxWidth: .infinity) } }
    private func time(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func speedText(_ speed: Double) -> String { speed > 0 ? String(format: "%.1f km/h", speed) : (location.horizontalAccuracy >= 0 ? "0.0 km/h" : "Waiting for GPS") }
    private func pace(for speed: Double) -> String { guard speed > 0.1 else { return "—" }; let seconds = Int(3600 / speed); return String(format: "%d:%02d/km", seconds / 60, seconds % 60) }
    private func intervalStepper(title: String, seconds: Binding<Double>, color: Color) -> some View {
        HStack {
            Text("\(title): \(time(seconds.wrappedValue))").font(Theme.Font.body).foregroundStyle(Theme.primaryText)
            Spacer()
            Button { seconds.wrappedValue = max(5, seconds.wrappedValue - 5) } label: { Label("Minus 5 seconds", systemImage: "minus.circle.fill").font(.title2) }.foregroundStyle(color)
            Button { seconds.wrappedValue = min(3600, seconds.wrappedValue + 5) } label: { Label("Plus 5 seconds", systemImage: "plus.circle.fill").font(.title2) }.foregroundStyle(color)
        }
        .padding(.vertical, 6)
    }
}

struct HIITLap: Identifiable, Codable, Equatable {
    let id: UUID
    let number: Int
    let isWalking: Bool
    let duration: TimeInterval
    let distanceMeters: Double
    let averageSpeedKmh: Double
    init(id: UUID = UUID(), number: Int, isWalking: Bool, duration: TimeInterval, distanceMeters: Double, averageSpeedKmh: Double) {
        self.id = id; self.number = number; self.isWalking = isWalking; self.duration = duration
        self.distanceMeters = distanceMeters; self.averageSpeedKmh = averageSpeedKmh
    }
    var workoutRecord: WorkoutLapRecord { WorkoutLapRecord(id: id, number: number, isWalking: isWalking, duration: duration, distanceMeters: distanceMeters, averageSpeedKmh: averageSpeedKmh) }
}

private struct HIITSummary: Identifiable { let id = UUID(); let walkingOnly: Bool; let duration: TimeInterval; let distanceMeters: Double; let laps: Int; let calories: Double }
private struct HIITTrackerView: View {
    @EnvironmentObject private var store: AppStore
    let exerciseID: String
    let title: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var days: [Date] { let calendar = Calendar.current; return (0..<35).compactMap { calendar.date(byAdding: .day, value: -34 + $0, to: calendar.startOfDay(for: Date())) } }
    private func minutes(_ day: Date) -> Int { Int(store.workoutSessions.filter { $0.exerciseID == exerciseID && Calendar.current.isDate($0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.activeDuration } / 60) }
    private var sessions: [WorkoutSession] { store.workoutSessions.filter { $0.exerciseID == exerciseID }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(title).font(Theme.Font.sectionTitle).foregroundStyle(Theme.primaryText)
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Last 35 days").font(Theme.Font.cardTitle).foregroundStyle(Theme.primaryText)
                        LazyVGrid(columns: columns, spacing: 5) {
                            ForEach(days, id: \.self) { day in
                                let value = minutes(day)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(value == 0 ? Theme.cardBorder : Theme.accent.opacity(min(1, 0.3 + Double(value) / 30)))
                                    .frame(height: 32)
                                    .overlay(Text(value == 0 ? "" : "\(value)m").font(.caption2).foregroundStyle(.white))
                            }
                        }
                        Text("Each square is one day. Brighter means more \(exerciseID == "walking" ? "walking" : "HIIT") minutes.").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exerciseID == "walking" ? "Total Walking" : "Total HIIT").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                        Text("\(Int(sessions.reduce(0.0) { $0 + $1.activeDuration } / 60)) minutes").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.primaryText)
                        Text(String(format: "%.2f km saved", sessions.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) } / 1000)).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Text("Saved sessions").font(Theme.Font.cardTitle).foregroundStyle(Theme.primaryText)
                if sessions.isEmpty {
                    Text("No completed sessions yet.").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                }
                ForEach(Array(sessions.prefix(20))) { session in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(Theme.Font.body).foregroundStyle(Theme.primaryText); Spacer(); Text("\(Int(session.activeDuration / 60)) min").foregroundStyle(Theme.accent) }
                            Text(sessionLine(session)).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                            if let laps = session.laps, !laps.isEmpty {
                                Divider()
                                ForEach(laps) { lap in
                                    HStack {
                                        Text("Lap \(lap.number) · \(lap.isWalking ? "Walking" : "Jogging")")
                                        Spacer()
                                        Text("\(time(lap.duration)) · \(String(format: "%.1f km/h", lap.averageSpeedKmh))")
                                    }.font(.caption2).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }
            }.padding(Theme.Spacing.l)
        }.background(Theme.background).navigationTitle(title)
    }
    private func sessionLine(_ session: WorkoutSession) -> String {
        var values = [String(format: "%.2f km", (session.distanceMeters ?? 0) / 1000), "\(Int(session.caloriesBurned)) kcal"]
        if let speed = session.averageSpeedKmh { values.append(String(format: "%.1f km/h avg", speed)) }
        return values.joined(separator: " · ")
    }
    private func time(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
private struct HIITSummaryView: View {
    let summary: HIITSummary
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { VStack(spacing: Theme.Spacing.xl) { Spacer(); Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.accent); Text(summary.walkingOnly ? "Walking Saved" : "HIIT Saved").font(Theme.Font.sectionTitle).foregroundStyle(Theme.primaryText); GlassCard { VStack(spacing: Theme.Spacing.m) { row("Total time", time(summary.duration)); row("Distance", String(format: "%.2f km", summary.distanceMeters / 1000)); row("Laps", "\(summary.laps)"); row("Calories", "\(Int(summary.calories)) kcal") } }.padding(.horizontal, Theme.Spacing.l); Text(summary.walkingOnly ? "Saved to separate Walking statistics and overall Workout statistics." : "Added to your overall Workout statistics.").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText); Spacer(); PrimaryButton(title: "Done") { dismiss() }.padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xl) }.background(Theme.background).navigationBarHidden(true) } }
    private func row(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(Theme.secondaryText); Spacer(); Text(value).foregroundStyle(Theme.primaryText) } }
    private func time(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

final class HIITRuntime: ObservableObject {
    static let shared = HIITRuntime()
    @Published var isActive = false
    @Published var isRunning = false
    @Published var walkingOnly = false
    @Published var isWalking = true
    @Published var startedAt: Date?
    @Published var lapStartedAt: Date?
    var sessionID = UUID()
    var movingElapsed: TimeInterval = 0
    var lapElapsed: TimeInterval = 0
    var breaks: [WorkoutBreak] = []
    var startsWalking = true
    var walkingLapSeconds = 60.0
    var joggingLapSeconds = 60.0
    var lapHistory: [HIITLap] = []
    var announcedLapTarget = false
    var lastTickAt: Date?
    var distanceMeters: Double = 0
    var lapDistanceMeters: Double = 0
    var isPresented = false
    private var lastCheckpointAt: Date?
    private let persistenceKey = "hiit.runtime.snapshot.v2"
    private init() { restore() }

    private struct Snapshot: Codable {
        let isActive: Bool; let isRunning: Bool; let walkingOnly: Bool; let isWalking: Bool
        let startedAt: Date?; let lapStartedAt: Date?; let sessionID: UUID
        let movingElapsed: TimeInterval; let lapElapsed: TimeInterval; let breaks: [WorkoutBreak]
        let startsWalking: Bool; let walkingLapSeconds: Double; let joggingLapSeconds: Double
        let lapHistory: [HIITLap]; let announcedLapTarget: Bool; let lastTickAt: Date?
        let distanceMeters: Double; let lapDistanceMeters: Double; let lastCheckpointAt: Date?
    }

    func persist() {
        let snapshot = Snapshot(isActive: isActive, isRunning: isRunning, walkingOnly: walkingOnly, isWalking: isWalking, startedAt: startedAt, lapStartedAt: lapStartedAt, sessionID: sessionID, movingElapsed: movingElapsed, lapElapsed: lapElapsed, breaks: breaks, startsWalking: startsWalking, walkingLapSeconds: walkingLapSeconds, joggingLapSeconds: joggingLapSeconds, lapHistory: lapHistory, announcedLapTarget: announcedLapTarget, lastTickAt: lastTickAt, distanceMeters: distanceMeters, lapDistanceMeters: lapDistanceMeters, lastCheckpointAt: lastCheckpointAt)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: persistenceKey) }
    }

    func checkpointIfNeeded(at now: Date) {
        guard isActive, let startedAt else { return }
        distanceMeters = HIITLocationService.shared.distanceMeters
        lapDistanceMeters = HIITLocationService.shared.lapDistanceMeters
        let liveLapDuration = lapElapsed + (isRunning ? activeTimeDelta(since: lastTickAt, at: now) : 0)
        let target = isWalking ? walkingLapSeconds : joggingLapSeconds
        if isRunning, !isPresented, !announcedLapTarget, liveLapDuration >= target {
            announcedLapTarget = true
            HIITVoiceCoach.shared.say("\(isWalking ? "Walking" : "Jogging") lap target reached")
        }
        persist()
        guard now.timeIntervalSince(lastCheckpointAt ?? .distantPast) >= 5 else { return }
        lastCheckpointAt = now
        let total = max(0, now.timeIntervalSince(startedAt))
        let breakTime = breaks.reduce(0) { $0 + $1.duration }
        let active = max(movingElapsed, total - breakTime)
        let settings = AppStore.shared.settings
        let weightKg = AppStore.shared.healthProfile.weightKg
        let walkingSeconds = lapHistory.filter(\.isWalking).reduce(0) { $0 + $1.duration } + ((walkingOnly || isWalking) ? liveLapDuration : 0)
        let joggingSeconds = lapHistory.filter { !$0.isWalking }.reduce(0) { $0 + $1.duration } + (!walkingOnly && !isWalking ? liveLapDuration : 0)
        let calories = CalorieCalculator.estimate(met: 3.5, weightKg: weightKg, activeSeconds: walkingSeconds, multiplier: settings.workoutCalorieMultiplier) + CalorieCalculator.estimate(met: 7, weightKg: weightKg, activeSeconds: joggingSeconds, multiplier: settings.workoutCalorieMultiplier)
        var records = lapHistory.map(\.workoutRecord)
        if liveLapDuration > 0 {
            records.append(WorkoutLapRecord(number: records.count + 1, isWalking: walkingOnly || isWalking, duration: liveLapDuration, distanceMeters: lapDistanceMeters, averageSpeedKmh: liveLapDuration > 0 ? lapDistanceMeters / liveLapDuration * 3.6 : 0))
        }
        AppStore.shared.upsertWorkoutSession(WorkoutSession(id: sessionID, exerciseID: walkingOnly ? "walking" : "hiit", startedAt: startedAt, endedAt: now, breaks: breaks, caloriesBurned: calories, distanceMeters: distanceMeters, recordedMovingDuration: active, averageSpeedKmh: active > 0 ? distanceMeters / active * 3.6 : 0, laps: records))
        persist()
    }

    func clear() {
        isActive = false; isRunning = false; startedAt = nil; lapStartedAt = nil
        movingElapsed = 0; lapElapsed = 0; breaks = []; lapHistory = []
        announcedLapTarget = false; lastTickAt = nil; sessionID = UUID()
        distanceMeters = 0; lapDistanceMeters = 0; lastCheckpointAt = nil
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey), let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isActive = value.isActive; isRunning = value.isRunning; walkingOnly = value.walkingOnly; isWalking = value.isWalking
        startedAt = value.startedAt; lapStartedAt = value.lapStartedAt; sessionID = value.sessionID
        movingElapsed = value.movingElapsed; lapElapsed = value.lapElapsed; breaks = value.breaks
        startsWalking = value.startsWalking; walkingLapSeconds = value.walkingLapSeconds; joggingLapSeconds = value.joggingLapSeconds
        lapHistory = value.lapHistory; announcedLapTarget = value.announcedLapTarget; lastTickAt = value.lastTickAt
        distanceMeters = value.distanceMeters; lapDistanceMeters = value.lapDistanceMeters; lastCheckpointAt = value.lastCheckpointAt
    }
}

private final class HIITVoiceCoach {
    static let shared = HIITVoiceCoach()
    private let speech = AVSpeechSynthesizer()
    func say(_ text: String) {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.volume = 1
        speech.speak(utterance)
    }
}

private final class HIITLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = HIITLocationService()
    @Published var speedKmh: Double = 0
    @Published var distanceMeters: CLLocationDistance = 0
    @Published var statusMessage: String?
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy = -1
    @Published private(set) var shouldAutoPause = false
    private let manager = CLLocationManager(); private var previousLocation: CLLocation?; private(set) var lapDistanceMeters: CLLocationDistance = 0; private var lapStartedAt: Date?; private var lowMotionSince: Date?; private var recentSpeeds: [Double] = []; private var wantsUpdates = false
    var accuracyText: String { horizontalAccuracy >= 0 ? "±\(Int(horizontalAccuracy)) m" : "Searching" }
    var lapAverageSpeedKmh: Double { guard let lapStartedAt else { return speedKmh }; let seconds = Date().timeIntervalSince(lapStartedAt); return seconds > 0 ? lapDistanceMeters / seconds * 3.6 : speedKmh }
    override init() { super.init(); manager.delegate = self; manager.activityType = .fitness; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 5; manager.pausesLocationUpdatesAutomatically = false }
    func start() { wantsUpdates = true; guard CLLocationManager.locationServicesEnabled() else { statusMessage = "Turn on Location Services in iPhone Settings."; return }; switch manager.authorizationStatus { case .notDetermined: statusMessage = "Allow Location While Using the App."; manager.requestWhenInUseAuthorization(); case .authorizedWhenInUse, .authorizedAlways: statusMessage = "Waiting for GPS signal…"; manager.allowsBackgroundLocationUpdates = true; manager.startUpdatingLocation(); case .denied, .restricted: statusMessage = "Location permission is off for this app."; @unknown default: statusMessage = "Location unavailable." } }
    func stop() { wantsUpdates = false; manager.stopUpdatingLocation(); previousLocation = nil }
    func beginLap() { lapDistanceMeters = 0; lapStartedAt = Date() }
    func restore(distanceMeters: Double, lapDistanceMeters: Double) { self.distanceMeters = max(0, distanceMeters); self.lapDistanceMeters = max(0, lapDistanceMeters) }
    func clearAutoPause() { shouldAutoPause = false; lowMotionSince = nil }
    func reset() { speedKmh = 0; distanceMeters = 0; previousLocation = nil; lapDistanceMeters = 0; lapStartedAt = nil; statusMessage = nil; horizontalAccuracy = -1; shouldAutoPause = false; lowMotionSince = nil; recentSpeeds = [] }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { guard wantsUpdates else { manager.stopUpdatingLocation(); return }; statusMessage = "Waiting for GPS signal…"; manager.allowsBackgroundLocationUpdates = true; manager.startUpdatingLocation(); beginLap() } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { statusMessage = "Allow Location While Using the App." } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 65 else { return }
        statusMessage = nil
        horizontalAccuracy = location.horizontalAccuracy
        // Smooth the displayed speed over the latest 10 GPS samples; raw
        // CLLocation speed jumps wildly from one second to the next.
        if location.speed >= 0 {
            recentSpeeds.append(location.speed * 3.6)
            recentSpeeds = Array(recentSpeeds.suffix(10))
            speedKmh = recentSpeeds.reduce(0, +) / Double(recentSpeeds.count)
        }
        if let previousLocation {
            let interval = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            let change = location.distance(from: previousLocation)
            // Reject stale points, impossible GPS jumps, and 1–2m GPS drift.
            if interval > 0, interval <= 12, change >= 2, change < 60 {
                distanceMeters += change
                lapDistanceMeters += change
            }
        }
        previousLocation = location
        let moving = location.speed >= 0.7 || speedKmh >= 2.5
        if moving { lowMotionSince = nil; shouldAutoPause = false }
        else if lowMotionSince == nil { lowMotionSince = location.timestamp }
        else if location.timestamp.timeIntervalSince(lowMotionSince ?? location.timestamp) >= 5 { shouldAutoPause = true }
        if lapStartedAt == nil { beginLap() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { statusMessage = error.localizedDescription }
}
