# Code Review — Modern SwiftUI & Apple API Modernization

Reviewed 2026-04-07. Target: macOS 26.2.

---

## 1. `ObservableObject` → `@Observable` (biggest win)

All four manager classes (`AppSettings`, `GitLabAuthManager`, `ProjectManager`, `TrackingManager`) use the old `ObservableObject` + `@Published` pattern. Since macOS 14+, `@Observable` is the modern replacement — it's cleaner and more performant (fine-grained observation, only re-renders views that read changed properties).

| Old | New |
|-----|-----|
| `class Foo: ObservableObject` | `@Observable class Foo` |
| `@Published var x` | `var x` (plain property) |
| `@Published private(set) var y` | `private(set) var y` |
| `@StateObject private var foo` | `@State private var foo` |
| `@ObservedObject var foo` | `var foo` (or `@Bindable var foo` if you need `$foo` bindings) |
| Combine `$property.sink` for observation | SwiftUI `onChange(of:)` or `withObservationTracking` |

`AppSettings` needs `@Bindable` in `SettingsView` since it uses `$settings.gitLabBaseURL` etc.

**Files affected:** Every Swift file.

---

## 2. Replace `MenuBarLabelClock` with `TimelineView`

`MenuBarLabelClock` (MenuBarViews.swift:16-45) is a 30-line `ObservableObject` with a manual `Timer` just to trigger 1-second re-renders. `TimelineView(.periodic(from: .now, by: 1))` is already used in `trackingOverviewSection` for the same purpose. The label view should do the same:

```swift
// Before: 30-line class + @StateObject + manual timer management
struct MenuBarLabelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var tracker: TrackingManager
    @StateObject private var clock = MenuBarLabelClock()
    // ... onChange handlers to start/stop clock
}

// After: just wrap in TimelineView
struct MenuBarLabelView: View {
    var settings: AppSettings
    var tracker: TrackingManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                Image(systemName: statusSymbolName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(statusColor, statusColor.opacity(1.0))
                    .font(.system(size: 20, weight: .bold))
                Text(statusLabel)
            }
        }
    }
}
```

Eliminates the entire `MenuBarLabelClock` class and all the `onChange` + `updateClockState()` wiring.

---

## 3. `Task.sleep(nanoseconds:)` → `Task.sleep(for:)`

Two places use the old nanoseconds API:

- **TrackingManager.swift:260** — `try await Task.sleep(nanoseconds: nanoseconds)`
- **NotificationCoordinator.swift:82** — `try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))`

```swift
// Before
try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

// After
try await Task.sleep(for: .seconds(interval))
```

---

## 4. `NSWorkspace.shared.open()` → `@Environment(\.openURL)`

Five places call `NSWorkspace.shared.open(url)` directly from SwiftUI views (MenuBarViews.swift lines 239, 634, 746). The SwiftUI-native equivalent:

```swift
@Environment(\.openURL) private var openURL

// Then:
openURL(issue.webURL)  // instead of NSWorkspace.shared.open(issue.webURL)
```

---

## 5. Replace Combine subscriptions with `onChange` / async

With `@Observable`, Combine subscriptions for property observation become unnecessary:

**ProjectManager.swift:31-37** — subscribes to `authManager.$currentUser`:

```swift
// Before: Combine sink
authManager.$currentUser
    .sink { [weak self] currentUser in ... }
    .store(in: &cancellables)

// After: observation happens automatically through property access,
// or use .onChange(of: authManager.currentUser) at the view level.
```

**AppSettings.swift:84-88** — iCloud change notification. This stays as `NotificationCenter` since it's a system notification, but consider the async sequence API:

```swift
// Before
NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
    .sink { [weak self] notification in
        self?.handleCloudStoreChange(notification)
    }
    .store(in: &cancellables)

// After
for await notification in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
    handleCloudStoreChange(notification)
}
```

---

## 6. `Color(NSColor.*)` → SwiftUI equivalents

Several places use `Color(NSColor.controlBackgroundColor)` and `Color(NSColor.windowBackgroundColor)`. Prefer:

- `Color(nsColor: .controlBackgroundColor)` (the non-deprecated initializer)
- Or `.background(.regularMaterial)` / `.background(.thickMaterial)` for adaptive backgrounds

---

## 7. Minor style issues

- **MenuBarViews.swift:55** — `HStack()` → `HStack` (empty parens not needed).
- **GitLabAPI.swift:199** — `_ = try validate(...)` — adding `@discardableResult` to `validate()` removes the need for `_ =`.
- **NotificationCoordinator.swift:88** — `await MainActor.run { self.sendCheckpointNotification(...) }` is redundant since the class is already `@MainActor`. `await self?.sendCheckpointNotification(...)` works directly.

---

## Priority

| # | Change | Impact |
|---|--------|--------|
| 1 | Migrate to `@Observable` | Removes ~50 lines of boilerplate, cleaner view code, better perf |
| 2 | Replace `MenuBarLabelClock` with `TimelineView` | Removes entire class (~30 lines) + wiring |
| 3 | `Task.sleep(for:)` | 2 call sites, trivial but clearer |
| 4 | `@Environment(\.openURL)` | 3-5 call sites, more SwiftUI-idiomatic |
| 5 | Drop Combine where possible | Removes `import Combine` from most files |
| 6 | Minor style fixes | Polish |
