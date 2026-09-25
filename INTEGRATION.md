# Integration guide

## 1. Add the core
Copy `Sources/WorkoutActivityCore/*.swift` into your app target (or add this repo as a local Swift package; types are `internal`, so copying is simplest).

## 2. Add the UI you want
Copy from `UI/`:
- `Support/DesignSystem.swift` (needed by every view) 
- `Support/ReferenceHost.swift` **or** your own store exposing the members below
- any of the views/view models in the matrix

## 3. Host contract (`AppStore`)

| Member | Used by |
|---|---|
| `workoutSessions: [WorkoutSession]` (`@Published`) | history, stats, HIIT |
| `customWorkouts: [CustomWorkout]` | breakdown, session VM |
| `func upsertWorkoutSession(_:)` (insert or replace by `id`, then persist) | session VM, HIIT |
| `settings.workoutCalorieMultiplier: Double` | session VM, HIIT |
| `healthProfile.weightKg: Double` | session VM, HIIT, dashboard VM |

Views read it as `@EnvironmentObject var store: AppStore` (history, stats) or `AppStore.shared`. Inject with `.environmentObject(store)`.

## 4. Info.plist
`NSLocationWhenInUseUsageDescription` (for HIIT/Walking).

## 5. Minimal example
```swift
import SwiftUI

@main struct DemoApp: App {
    @StateObject private var store = AppStore.shared
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("Walking") { HIITWorkoutView(weightKg: 70, walkingOnly: true) }
                    NavigationLink("HIIT") { HIITWorkoutView(weightKg: 70) }
                    NavigationLink("Stats") { WorkoutStatsView() }
                }
            }
            .environmentObject(store)
        }
    }
}
```
(The example type-checks against the iOS 18.2 SDK; it has not been run.)

## Dependency matrix

| File | Purpose | Depends on | Notes |
|---|---|---|---|
| `Sources/.../WorkoutModels.swift` | Exercise catalog, sessions, segments, integrity repair, `CalorieCalculator` | Foundation | none |
| `Sources/.../WorkoutStatsService.swift` | Range filter, summary, streaks | `WorkoutSession`, `WorkoutExercise` | none |
| `UI/ViewModels/WorkoutSessionViewModel.swift` | Live session engine (`WorkoutRuntime`) | models, `AppStore` | host store |
| `UI/ViewModels/WorkoutDashboardViewModel.swift` | Dashboard state | `AppStore`, stats | host store |
| `UI/Views/HIITWorkoutView.swift` | HIIT + Walking screens, `HIITRuntime`, GPS | `AppStore`, `Theme`, CoreLocation, AVFoundation | needs Location permission |
| `UI/Views/WorkoutHistoryView.swift` | History list/detail | `AppStore`, stats, breakdown | |
| `UI/Views/WorkoutBreakdownView.swift` | Per-session breakdown | `AppStore`, `Theme` | |
| `UI/Views/WorkoutStatsView.swift` | Stats screen | `AppStore`, stats | |
| `UI/Support/DesignSystem.swift` | `Theme` tokens and small components | SwiftUI | |
| `UI/Support/ReferenceHost.swift` | In-memory store (new, not from the original) | Combine | replace |

Unresolved parent-app dependencies: none for the included files. Excluded on purpose: see README "Not included".
