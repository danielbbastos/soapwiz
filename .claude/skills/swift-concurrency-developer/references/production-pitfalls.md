# Production Concurrency Pitfalls

Real-world Swift Concurrency mistakes that cause data loss, App Store rejections, battery drain, migration nightmares, and duplicate work.

---

## 1. Async For Loops Silently Losing Data

### The Problem

When you iterate over items in an async loop and use `try?` or empty `catch {}`, failures are swallowed silently. Users lose data with zero indication. This is especially dangerous in batch operations like saves, sync tasks, or cache warming.

### Wrong

```swift
for item in items {
    try? await service.save(item)  // Failure = silent data loss
}

for item in items {
    do {
        try await service.process(item)
    } catch {}  // Swallowed - no logging, no retry, no user feedback
}
```

### Correct

```swift
// Option A: Collect errors, report at end
var failures: [(Item, Error)] = []
for item in items {
    do {
        try await service.save(item)
    } catch {
        failures.append((item, error))
        assertionFailure("Save failed for \(item.id): \(error)")
    }
}
if !failures.isEmpty {
    // Show user feedback, retry, or log
}

// Option B: Use TaskGroup for parallel processing with error collection
try await withThrowingTaskGroup(of: Void.self) { group in
    for item in items {
        group.addTask { try await service.save(item) }
    }
    try await group.waitForAll()  // Propagates first error
}
```

### When Empty Catch Is Acceptable

- **Cache warming / prefetching** — Best-effort, user has fallback path
- **Analytics events** — Non-critical, shouldn't block user flow
- **Cancellation cleanup** — `try? await service.cancel(...)` during teardown

### When Empty Catch Is Dangerous

- **Saves / sync** — Users expect all items to persist
- **Data migration** — Partial migration = corrupted state
- **Critical operations** — Silent failure = data loss

### Detection

```bash
# Empty catch blocks in async code
rg "catch\s*\{\s*\}" --type swift .

# try? in async calls (review candidates, not all are bugs)
rg "try\? await" --type swift .
```

---

## 2. Assuming async = Background Thread

### The Problem

`async` does NOT mean "runs on a background thread." An `async` function inherits its caller's isolation. If called from `@MainActor` context, it runs on the main thread. Heavy computation in an async function on MainActor blocks the UI, causing:
- App Store rejection ("app became unresponsive")
- Janky scrolling and frozen UI
- Watchdog kills on older devices

### Wrong

```swift
@MainActor
final class SearchViewModel: Observable {
    func search(_ query: String) async {
        // WRONG: This runs on the main thread!
        let results = items.filter { $0.matches(query) }  // Heavy computation
        let sorted = results.sorted(by: complexSort)       // Still main thread
        self.results = sorted
    }
}
```

### Correct

```swift
@MainActor
final class SearchViewModel: Observable {
    func search(_ query: String) async {
        // Offload heavy work explicitly
        let results = await Task.detached(priority: .userInitiated) {
            let filtered = items.filter { $0.matches(query) }
            return filtered.sorted(by: complexSort)
        }.value
        self.results = results  // Back on MainActor for UI update
    }
}

// Even better: Use an actor for the heavy work
actor SearchEngine {
    func search(_ query: String, in items: [Item]) -> [Item] {
        items.filter { $0.matches(query) }.sorted(by: complexSort)
    }
}
```

### Key Insight

The `async` keyword means "this function can suspend." It does NOT mean "this function runs on a background thread." Where code runs depends entirely on isolation context:

| Context | Where it runs |
|---------|---------------|
| `@MainActor` function | Main thread |
| Custom `actor` function | Cooperative thread pool |
| `nonisolated async` function | Cooperative thread pool |
| `Task.detached { }` | Cooperative thread pool (no inherited context) |
| `Task { }` inside `@MainActor` | Main thread (inherits isolation) |

### Detection

```bash
# Find @MainActor classes doing heavy work in async methods
# Look for sort, filter, map, reduce, compactMap in @MainActor ViewModels
rg "@MainActor" -A 20 --type swift . | grep -E "\.(sort|filter|map|reduce|compactMap)\("
```

---

## 3. Ignoring Task Cancellation

### The Problem

When a SwiftUI view disappears, `.task {}` cancels its task. But `for await` loops and long-running operations don't automatically stop unless you check for cancellation. This leads to:
- Wasted CPU/network after the user navigates away
- Battery drain from orphaned background work
- Potential crashes updating deallocated views

### Wrong

```swift
func processLargeDataset() async {
    for item in hugeArray {
        await process(item)  // Continues even after task is cancelled!
    }
}

// No cancellation check in manual polling
func pollForUpdates() async {
    while true {
        let update = await fetchUpdate()
        handleUpdate(update)
        try? await Task.sleep(for: .seconds(5))  // try? swallows CancellationError!
    }
}
```

### Correct

```swift
func processLargeDataset() async throws {
    for item in hugeArray {
        try Task.checkCancellation()  // Throws if cancelled
        await process(item)
    }
}

// Proper cancellation in polling
func pollForUpdates() async {
    while !Task.isCancelled {
        let update = await fetchUpdate()
        handleUpdate(update)
        try? await Task.sleep(for: .seconds(5))
    }
}
```

### When You Need Explicit Cancellation Checks

| Pattern | Needs explicit check? | Why |
|---------|----------------------|-----|
| `for await` under `.task` modifier | No | Structured concurrency propagates cancellation |
| `for await` under stored `Task { }` | Yes | Unstructured, won't auto-cancel |
| `while` loop with `Task.sleep` | Yes | Sleep alone isn't enough if `try?` swallows error |
| Heavy computation loop | Yes | No suspension points to check cancellation |
| `Task.detached { }` | Yes | Fully unstructured, no parent to cancel it |

### Detection

```bash
# for-await loops in ViewModels (review: are they under .task or stored Task?)
rg "for await" --type swift .

# while loops without cancellation checks
rg "while true|while !Task" --type swift .

# Stored tasks (potential unstructured tasks needing manual cancellation)
rg "private var.*Task<" --type swift .
```

---

## 4. Manual Migration Pitfalls (@preconcurrency and DispatchQueue+async mixing)

### The Problem

During incremental Swift 6 migration, codebases accumulate `@preconcurrency`, `nonisolated(unsafe)`, and bridge patterns mixing `DispatchQueue` with `async/await`. These are necessary escape hatches, but they:
- Hide real data races behind compiler silencing
- Create confusing execution contexts (which thread am I on?)
- Make future migration harder as debt compounds
- Can cause subtle ordering bugs at DispatchQueue/async boundaries

### Wrong

```swift
// Silencing the compiler without understanding the race
@preconcurrency import SomeFramework
nonisolated(unsafe) var sharedState: [String] = []  // "Trust me" = famous last words

// Mixing dispatch and async without clear boundaries
func doWork() {
    DispatchQueue.main.async {
        Task {
            await self.asyncWork()
            DispatchQueue.global().async {
                // What thread are we on? Nobody knows.
                self.processResult()
            }
        }
    }
}
```

### Correct

```swift
// Document WHY @preconcurrency is needed and plan removal
@preconcurrency import LegacyFramework  // TODO: SW-XX - Remove when LegacyFramework adds Sendable
// Safety invariant: sharedState is only accessed from MainActor context
nonisolated(unsafe) var sharedState: [String] = []

// Clean bridge: one direction, clear boundary
func doWork() async {
    let result = await asyncWork()
    await MainActor.run {
        processResult(result)
    }
}
```

### Migration Tracking Checklist

When reviewing code with these patterns:

1. **`@preconcurrency import`** — Is the imported framework now Sendable-compliant? If yes, remove.
2. **`nonisolated(unsafe)`** — Is there a documented safety invariant? Is the invariant still true?
3. **`DispatchQueue` inside `Task`** — Can this be replaced with `await MainActor.run { }`?
4. **Completion handler + Task** — Can the entire call chain become async?

### Detection

```bash
# @preconcurrency imports (should decrease over time)
rg "@preconcurrency import" --type swift .

# nonisolated(unsafe) usage
rg "nonisolated\(unsafe\)" --type swift .

# DispatchQueue usage inside async contexts
rg "DispatchQueue\." --type swift .
```

---

## 5. Task Inside onAppear vs .task Modifier

### The Problem

Creating a `Task { }` inside `.onAppear` is an unstructured task that:
- Is NOT cancelled when the view disappears (memory leak, wasted work)
- Can fire multiple times if the view re-appears (duplicate API calls)
- Has no parent task for structured cancellation propagation

The `.task` modifier is purpose-built for SwiftUI:
- Automatically cancelled on view disappear
- Runs once per view lifetime (or per `id` change with `.task(id:)`)
- Supports structured concurrency

### Wrong

```swift
struct ProfileView: View {
    var body: some View {
        content
            .onAppear {
                Task {
                    await model.loadProfile()  // Leaked task, fires on every appear
                }
            }
    }
}
```

### Correct

```swift
struct ProfileView: View {
    var body: some View {
        content
            .task {
                await model.loadProfile()  // Cancelled on disappear, runs once
            }
    }
}

// For work that should re-run when a value changes:
struct DetailView: View {
    var body: some View {
        content
            .task(id: selectedId) {
                await model.loadDetail(id: selectedId)  // Re-runs when id changes
            }
    }
}
```

### When onAppear Is Correct

```swift
// Synchronous setup - no async work
.onAppear {
    model.onAppear()  // Sync method, not async
}
```

### Quick Decision Guide

| Need | Use |
|------|-----|
| Run async work tied to view lifecycle | `.task { }` |
| Run async work when a value changes | `.task(id: value) { }` |
| Synchronous setup on appear | `.onAppear { }` |

### Detection

```bash
# Task inside onAppear (review candidates)
rg "\.onAppear" -A 5 --type swift . | grep "Task {"

# Verify .task usage (should be more common than Task-in-onAppear)
rg "\.task\s*\{" --type swift . -c
```

---

## Summary

| Pitfall | Production Impact | Severity |
|---------|------------------|----------|
| Silent error swallowing in async loops | Data loss, incomplete operations | High |
| async != background thread | App Store rejection, frozen UI | Critical |
| Ignoring task cancellation | Battery drain, wasted resources | Medium-High |
| Migration debt accumulation | Hidden data races, harder future migration | Medium |
| Task in onAppear vs .task | Duplicate calls, memory leaks | Medium |
