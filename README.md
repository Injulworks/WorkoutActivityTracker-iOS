# WorkoutActivityTracker-iOS

SwiftUI workout, HIIT and walking tracker code for iOS: session models, MET-based calorie estimates, streak and range statistics, and live GPS interval (walk/jog) tracking.

## Project type

**Feature source bundle** with a **compiled and tested Swift package core**.

| Folder | What it is | Verified |
|---|---|---|
| `Sources/WorkoutActivityCore/` | Models + statistics (Foundation only) | `swift test` on macOS: 9/9 pass |
| `UI/` | SwiftUI screens, view models, design tokens, reference host store | Type-checks against the iOS 18.2 SDK with `-target arm64-apple-ios16.0-simulator`. **Not run** on a device or simulator from this repo |

This is not a runnable app. Copy the files you need into your own app (see [INTEGRATION.md](INTEGRATION.md)).

## Features (all present in the source)

- Workout sessions built from exercise and rest segments, with breaks and sets/reps
- A catalog of 18 bodyweight exercises with target muscles, posture notes and MET values (`WorkoutExercise.all`)
- Support for user-created exercises (`CustomWorkout`, mapped to a `WorkoutExercise`; no personal ones ship here)
- Start / pause / resume / end for the live session view model
- Active time, break time, longest/shortest/average break
- Calorie **estimates** = MET × weight (kg) × hours × multiplier. They are approximations, not measurements
- HIIT (alternating walking/jogging laps with configurable lap targets), separate Walking mode, GPS distance, average speed, lap history, voice prompts
- Statistics for today / last 7 days / last 30 days / last 365 days / lifetime: session count, active minutes, calories, average and longest session, favourite exercise, current and best streak, consistency %
- Session history list and detail, and a per-session "breakdown" (exercise/rest rows)
- Recovery: orphaned open segments left by a killed app are closed at the last autosave time (`WorkoutSessionIntegrity`); older JSON without newer optional fields still decodes

Definitions used by the code (unchanged from the original):
- **Streak**: consecutive calendar days, ending today, with at least one session. It is 0 if there is no session today. Best streak is the longest run over all sessions.
- **Consistency**: days in the range with a session ÷ days in the range (lifetime: ÷ distinct active days).
- **Range windows**: week = today and the 6 days before; month = 30 days; year = 365 days.

## Not included / scope notes

- Personal or custom exercises, history, routines, body measurements, GPS routes: none are included.
- **Daily workout goal**: the goal value lives in the original app's settings, not in these files, so it is not exported. `WorkoutStatsService` returns minutes; compare them with your own goal.
- **Five-day summary, monthly/yearly *charts* beyond what `WorkoutStatsView` draws, walking *daily* targets**: no separate implementation of a "five-day summary" was found in the workout source, so none is claimed. The "Walking target" in HIIT is a per-lap duration stepper.
- **Exercise detail screen and Workout home** (`WorkoutSessionView`, `WorkoutView`) are not included: they depend on the original app's imported-media library and HealthKit reads. `WorkoutSessionViewModel` (session engine) is included.
- The original app's Personal OS / activity-ledger sync (`WorkoutActivityBridge`) is excluded.
- Apple Health is not used by the included files.

## Requirements

- iOS 16.0+ (as configured in the source project), Swift 5, Xcode 16-era toolchain. Verified with Xcode's iOS 18.2 SDK and Swift 6.0.3 in Swift 5 mode.
- Frameworks: Foundation, SwiftUI, Combine, CoreLocation, AVFoundation, UIKit. No third-party libraries.
- Permission: Location When In Use (`NSLocationWhenInUseUsageDescription`) for HIIT/Walking distance.

## Installation

```bash
git clone https://github.com/Injulworks/WorkoutActivityTracker-iOS.git
cd WorkoutActivityTracker-iOS
swift test        # core package tests (macOS)
```

Then follow [INTEGRATION.md](INTEGRATION.md) to add files to your app.

## Persistence

The core types are `Codable`; the original app stores `[WorkoutSession]` and `[CustomWorkout]` as JSON files. The bundle contains **no persistence code**: `UI/Support/ReferenceHost.swift` keeps them in memory with a `TODO` where you persist. Older stored sessions decode because newer fields are optional.

## Permissions and privacy

- Location is used only while a HIIT/Walking session runs, to compute distance and speed. Without permission the screen shows a message and time/laps still work; distance stays 0.
- Nothing in these files makes a network call. Session data stays in whatever storage *you* add.

## Limitations

- UI files use `AppStore.shared`; replace the reference host with your own store, or keep the same member names.
- `HIITRuntime` reconciles background time only if your app calls its checkpoint (the original did it from its root view).
- Pure-model tests only; the original app's UI/integration tests are not exported.
- `Theme` is a small design-token enum; restyle freely.

## Testing

```bash
swift test
```
Result on 2026-09-25: 9 tests, 0 failures. Fixtures are synthetic.

## Roadmap (not implemented)

Optional HealthKit export; a store protocol instead of the reference host; a runnable demo app.

## Contributing

Issues and pull requests are welcome. Keep changes small, add a test for core changes, and run `swift test`.

## License

[MIT](LICENSE)
