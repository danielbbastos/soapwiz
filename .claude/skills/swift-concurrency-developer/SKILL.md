---
name: swift-concurrency-developer
description: Swift concurrency — actors, actor isolation, Sendable, TaskGroup, nonisolated, async let, @MainActor. Use when fixing data-race warnings, actor-isolation errors, "non-Sendable type crossing actor boundary", Swift 6 strict-concurrency migration, or deciding where an isolation boundary belongs.
---

# Swift Concurrency Developer (Smart Router)

## Purpose
Expert guidance on Swift's concurrency system using the "Office Building" mental model from [Fucking Approachable Swift Concurrency](https://fuckingapproachableswiftconcurrency.com), combined with comprehensive reference material from [Swift Concurrency Course](https://www.swiftconcurrencycourse.com).

## When Auto-Activated
- Working with actors, isolation, Sendable, TaskGroups
- Keywords: `actor`, `isolation`, `Sendable`, `TaskGroup`, `nonisolated`, `async let`
- Fixing concurrency warnings or data race issues

## Agent Behavior Contract (Follow These Rules)

1. Analyze the project build settings to confirm the Swift language mode and concurrency settings before giving migration-sensitive advice.
2. Before proposing fixes, identify the isolation boundary: `@MainActor`, custom actor, actor instance isolation, or nonisolated.
3. Do not recommend `@MainActor` as a blanket fix. Justify why main-actor isolation is correct for the code.
4. Prefer structured concurrency (child tasks, task groups) over unstructured tasks. Use `Task.detached` only with a clear reason.
5. If recommending `@preconcurrency`, `@unchecked Sendable`, or `nonisolated(unsafe)`, require:
   - a documented safety invariant
   - a follow-up ticket to remove or migrate it
6. For migration work, optimize for minimal blast radius (small, reviewable changes) and add verification steps.
7. Course references are for deeper learning only. Use them sparingly and only when they clearly help answer the developer's question.
8. **Never use GCD (`DispatchQueue`).** Always use Swift Concurrency equivalents:
   - `DispatchQueue.main.async { }` → `Task { }` (already on `@MainActor`)
   - `DispatchQueue.main.asyncAfter(deadline: .now() + n) { }` → `Task { try? await Task.sleep(for: .seconds(n)); ... }`
   - `DispatchQueue.global().async { }` → `Task.detached { }` (with justification per rule 4)
   - `DispatchQueue.main.sync { }` → refactor to avoid; sync dispatch onto main from main deadlocks

## Project Settings (SoapWiz Baseline)

| Setting | Value | Notes |
|---------|-------|-------|
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | All types are `@MainActor` by default |
| Swift version | iOS 26+ | Swift 6 strict concurrency in effect |
| SwiftData | `@MainActor` | All `ModelContext` operations must stay on main actor |

**Confirm these before interpreting diagnostics.** Read `SoapWiz.xcodeproj` if unsure.

## Core Mental Model: The Office Building

Think of your app as an office building where **isolation domains** are private offices with locks:

| Concept | Office Analogy | Swift |
|---------|----------------|-------|
| **MainActor** | Front desk (handles all UI) | `@MainActor` |
| **actor** | Department offices (Accounting, Legal) | `actor BankAccount { }` |
| **nonisolated** | Hallways (shared space) | `nonisolated func name()` |
| **Sendable** | Photocopies (safe to share) | `struct User: Sendable` |
| **Non-Sendable** | Original documents (stay in one office) | `class Counter { }` |

**Key insight**: You can't barge into someone's office. You knock (`await`) and wait.

## Quick Decision Tree

When a developer needs concurrency guidance:

1. **Starting fresh with async code?**
   - Read `references/async-await-basics.md` for foundational patterns
   - For parallel operations → `references/tasks.md` (async let, task groups)

2. **Protecting shared mutable state?**
   - Need to protect class-based state → `references/actors.md` (actors, @MainActor)
   - Need thread-safe value passing → `references/sendable.md` (Sendable conformance)

3. **Managing async operations?**
   - Structured async work → `references/tasks.md` (Task, child tasks, cancellation)
   - Streaming data → `references/async-sequences.md` (AsyncSequence, AsyncStream)

4. **Working with SwiftData?**
   - `ModelContext` isolation and actor boundaries → `references/swiftdata.md`

5. **Performance or debugging issues?**
   - Slow async code → `references/performance.md` (profiling, suspension points)
   - Testing concerns → `references/testing.md` (Swift Testing, XCTest)

6. **Understanding threading behavior?**
   - Read `references/threading.md` for thread/task relationship and isolation

7. **Memory issues with tasks?**
   - Read `references/memory-management.md` for retain cycle prevention

## Triage-First Playbook (Common Errors → Next Best Move)

- **SwiftLint concurrency-related warnings**
  - Use `references/linting.md` for rule intent and preferred fixes; avoid dummy awaits as "fixes".
- **"Sending value of non-Sendable type ... risks causing data races"**
  - First: identify where the value crosses an isolation boundary
  - Then: use `references/sendable.md` and `references/threading.md`
- **"Main actor-isolated ... cannot be used from a nonisolated context"**
  - First: decide if it truly belongs on `@MainActor`
  - Then: use `references/actors.md` (global actors, `nonisolated`, isolated parameters)
- **XCTest async errors like "wait(...) is unavailable from asynchronous contexts"**
  - Use `references/testing.md` (`await fulfillment(of:)` and Swift Testing patterns)
- **SwiftData concurrency warnings/errors**
  - Use `references/swiftdata.md` (ModelContext on @MainActor, PersistentIdentifier patterns)

## Quick Patterns

### Async/Await
```swift
func fetchUser(id: Int) async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}
```

### Parallel Work with async let
```swift
async let avatar = fetchImage("avatar.jpg")
async let banner = fetchImage("banner.jpg")
return Profile(avatar: try await avatar, banner: try await banner)
```

### Tasks
```swift
// SwiftUI - cancels when view disappears
.task { avatar = await downloadAvatar() }

// Manual task (inherits actor context)
Task { await saveProfile() }
```

### Task Entry Isolation (Swift 6.2)

Match a `Task`'s entry isolation to its **synchronous prefix** — everything from `{` to the first `await`. Whatever runs in that prefix executes on the inherited actor.

- If the prefix needs `@MainActor` (touches UI state, mutates `self.isLoading`, etc.), keep the inherited start.
- If the prefix has nothing main-actor-bound, prefer `Task { @concurrent in ... }` and hop back via `MainActor.run { ... }` only for the UI mutation.
- A trivial non-main statement (e.g. `print`) followed by main-actor work is **not** a reason to switch to `@concurrent` — the cheap line rides along.

```swift
// ❌ Called from @MainActor; fetchData() is nonisolated, task starts on main then hops away
Task {
    await fetchData()  // nonisolated async
}

// ✅ Start off the main actor, hop back only for UI work
Task { @concurrent in
    let data = try await fetchData()
    await MainActor.run { self.items = data }
}

// ✅ Prefix DOES need main actor — keep inheritance
Task {
    self.isLoading = true       // needs @MainActor, before any await
    await fetchData()
    self.isLoading = false
}
```

### TaskGroup for Dynamic Parallel Work
```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { avatar = try await downloadAvatar() }
    group.addTask { bio = try await fetchBio() }
    try await group.waitForAll()
}
```

### Actors
```swift
actor BankAccount {
    var balance: Double = 0
    func deposit(_ amount: Double) { balance += amount }
    nonisolated func bankName() -> String { "Acme Bank" }
}

await account.deposit(100)  // Must await from outside
let name = account.bankName()  // No await needed
```

### Sendable Types
```swift
// Automatically Sendable - value type
struct User: Sendable {
    let id: Int
    let name: String
}

// Thread-safe class with internal synchronization
final class ThreadSafeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
}
```

## SwiftData + Concurrency

- All `ModelContext` operations must run on `@MainActor` — this is already the default in SoapWiz
- Never pass `@Model` instances across actor boundaries — pass `PersistentIdentifier` and re-fetch in the target context
- `@Query` macro handles observation automatically; don't replicate it with manual `Task` polling
- See `references/swiftdata.md` for detailed patterns

## Common Mistakes

### 1. Thinking async = background
```swift
// WRONG: Still blocks main thread!
@MainActor func slowFunction() async {
    let result = expensiveCalculation()  // Synchronous = blocking
}

// CORRECT: Use detached task for CPU-heavy work
Task.detached(priority: .userInitiated) {
    let result = expensiveCalculation()
    await MainActor.run { updateUI(result) }
}
```

### 2. Creating too many actors
Most things can live on MainActor. Only create actors when you have shared mutable state that can't be on MainActor.

### 3. Using MainActor.run unnecessarily
```swift
// WRONG
await MainActor.run { self.data = data }

// CORRECT - annotate the function
@MainActor func loadData() async { self.data = await fetchData() }
```

### 4. Blocking the cooperative thread pool (violates runtime contract)
Never use `DispatchSemaphore`, `DispatchGroup.wait()`, or condition variables in async code.

```swift
// ❌ DANGEROUS: Can deadlock the cooperative pool
let semaphore = DispatchSemaphore(value: 0)
Task {
    await doWork()
    semaphore.signal()
}
semaphore.wait()  // Thread blocked, runtime unaware

// ✅ Use async/await instead
let result = await doWork()
```

**Debug tip**: Set `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` to catch blocking calls during development.

### 5. Creating unnecessary Tasks
```swift
// WRONG - unstructured
Task { await fetchUsers() }
Task { await fetchPosts() }

// CORRECT - structured concurrency
async let users = fetchUsers()
async let posts = fetchPosts()
await (users, posts)
```

### 6. Making everything Sendable
Not everything needs to cross boundaries. Ask if data actually moves between isolation domains.

### 7. Not batching MainActor hops
```swift
// ❌ Multiple context switches
for item in items {
    let processed = await processItem(item)
    await MainActor.run { displayItem(processed) }  // Context switch per item
}

// ✅ Single context switch
let processed = await processAllItems(items)
await MainActor.run {
    for item in processed { displayItem(item) }
}
```

### 8. Async for loops silently losing data
Using `try?` or empty `catch {}` in async loops swallows failures. Users lose data with zero indication. Acceptable for fire-and-forget (cache warming, analytics), dangerous for saves/sync/migration. See `references/production-pitfalls.md` section 1.

### 9. Ignoring Task cancellation in long-running loops
`for await` under `.task` modifier is safe (structured concurrency propagates cancellation). But `for await` or `while` loops in stored `Task { }` properties need explicit `Task.isCancelled` checks. See `references/production-pitfalls.md` section 3.

### 10. Manual migration pitfalls (@preconcurrency + DispatchQueue mixing)
`@preconcurrency` and `nonisolated(unsafe)` hide real data races. Always document safety invariants and plan removal. See `references/production-pitfalls.md` section 4.

### 11. Task inside onAppear instead of .task modifier
`Task { }` in `.onAppear` is unstructured: not cancelled on disappear, fires on every re-appear. Use `.task { }` for async work tied to view lifecycle, `.onAppear` for sync-only setup. See `references/production-pitfalls.md` section 5.

## Quick Reference

| Keyword | Purpose |
|---------|---------|
| `async` | Function can pause |
| `await` | Pause here until done |
| `Task { }` | Start async work, inherits context |
| `Task.detached { }` | Start async work, no context |
| `@MainActor` | Runs on main thread |
| `actor` | Type with isolated mutable state |
| `nonisolated` | Opts out of actor isolation |
| `Sendable` | Safe to pass between isolation domains |
| `@unchecked Sendable` | Trust me, it's thread-safe |
| `async let` | Start parallel work |
| `TaskGroup` | Dynamic parallel work |

## When the Compiler Complains

Trace the isolation: Where did it come from? Where is code trying to run? What data crosses a boundary?

The answer is usually obvious once you ask the right question.

## Reference Files

Load these files as needed for specific topics:

### Foundational Concepts
- **`async-await-basics.md`** - async/await syntax, execution order, async let, URLSession patterns
- **`tasks.md`** - Task lifecycle, cancellation, priorities, task groups, structured vs unstructured
- **`threading.md`** - Thread/task relationship, suspension points, isolation domains, nonisolated
- **`glossary.md`** - Quick definitions of core concurrency terms

### Isolation & Safety
- **`actors.md`** - Actor isolation, @MainActor, global actors, reentrancy, custom executors, Mutex
- **`sendable.md`** - Sendable conformance, value/reference types, @unchecked, region isolation
- **`memory-management.md`** - Retain cycles in tasks, memory safety patterns

### Advanced Patterns
- **`async-sequences.md`** - AsyncSequence, AsyncStream, when to use vs regular async methods
- **`task-local-values.md`** - Task-local context propagation, tracing, logging patterns

### SwiftUI & SwiftData
- **`swiftui-concurrency-tour.md`** - SwiftUI-specific concurrency patterns
- **`swiftdata.md`** - SwiftData + concurrency (ModelContext, PersistentIdentifier, @Query)

### Quality & Migration
- **`performance.md`** - Profiling with Instruments, reducing suspension points, execution strategies
- **`testing.md`** - XCTest async patterns, Swift Testing, concurrency testing utilities
- **`migration.md`** - Swift 6 migration strategy, closure-to-async conversion, @preconcurrency
- **`linting.md`** - Concurrency-focused lint rules and SwiftLint async_without_await
- **`production-pitfalls.md`** - Silent data loss, cancellation gaps, migration bridges, .task vs onAppear

### Swift 6.2+
- **`approachable-concurrency.md`** - Approachable concurrency quick guide
- **`swift-6-2-concurrency.md`** - Swift 6.2 concurrency updates

## Best Practices Summary

1. **Prefer structured concurrency** - Use task groups over unstructured tasks when possible
2. **Minimize suspension points** - Keep actor-isolated sections small to reduce context switches
3. **Use @MainActor judiciously** - Only for truly UI-related code (it's the default here — understand why)
4. **Make types Sendable** - Enable safe concurrent access by conforming to Sendable
5. **Handle cancellation** - Check Task.isCancelled in long-running operations
6. **Avoid blocking** - Never use semaphores or locks in async contexts (violates runtime contract)
7. **Test concurrent code** - Use proper async test methods and consider timing issues
8. **Batch MainActor hops** - Group UI updates to minimize context switches to/from main thread
9. **Understand the runtime contract** - Threads must always make forward progress; use safe primitives
10. **Use LIBDISPATCH_COOPERATIVE_POOL_STRICT=1** - Debug environment variable to catch blocking calls

## Verification Checklist (When You Change Concurrency Code)

- Confirm build settings (default isolation, strict concurrency) before interpreting diagnostics.
- After refactors:
  - Run tests, especially concurrency-sensitive ones (see `references/testing.md`).
  - If performance-related, verify with Instruments (see `references/performance.md`).
  - If lifetime-related, verify deinit/cancellation behavior (see `references/memory-management.md`).

### Migration Validation Loop

For Swift 6 / strict-concurrency migration, apply this cycle for each change:

1. **Build** — surface new diagnostics
2. **Fix** — address one category at a time (e.g., all Sendable issues first, then all isolation issues)
3. **Rebuild** — confirm the fix compiles cleanly before moving on
4. **Test** — run the suite to catch regressions
5. **Only then** proceed to the next file/module

Never batch unrelated fixes into one change. Keep commits small and reviewable. See `references/migration.md` for detailed migration steps.

## Further Reading
- [Fucking Approachable Swift Concurrency](https://fuckingapproachableswiftconcurrency.com) - Office Building mental model
- [Swift Concurrency Course](https://www.swiftconcurrencycourse.com) - Comprehensive reference (Antoine van der Lee)
- [WWDC21: Swift Concurrency: Behind the Scenes](https://developer.apple.com/videos/play/wwdc2021/10254/) - Runtime internals, threading model
- [WWDC23: Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/) - Task groups, cancellation handlers
- [Matt Massicotte's Blog](https://www.massicotte.org/) - Deep dives on concurrency
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)

## Related Skills

- **ios-dev-guidelines** → General Swift/iOS patterns, MVVM
- **tests-developer** → Testing async code with Swift Testing framework
- **swiftui-performance-developer** → Performance optimization in SwiftUI views

---
**Navigation**: This skill provides concurrency mental models. For general Swift/iOS patterns, see `ios-dev-guidelines`.

**Attribution**: Office Building mental model from [Dimillian/Skills](https://github.com/Dimillian/Skills). Reference files from [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill).
