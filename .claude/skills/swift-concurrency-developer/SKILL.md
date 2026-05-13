---
name: swift-concurrency-developer
description: Swift concurrency specialist. Use when writing async/await code, working with actors, or resolving concurrency warnings in SoapWiz.
---

# Swift Concurrency Developer

Use this when writing or reviewing async/await code, actors, or fixing concurrency warnings in SoapWiz.

## Project Baseline

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set globally — all types are `@MainActor` by default
- Swift 6 strict concurrency is in effect
- SwiftData models must stay on `@MainActor` at all times

## Mental Model: Isolation Domains

Think of isolation domains as private offices. Code inside the same actor can run freely; crossing into another actor requires `await`. The main actor is the front desk — UI work always happens there.

## Decision Tree

**Starting a background task?**
→ Use `Task { }` (inherits current actor context) or `Task.detached { }` (no actor — use only when you explicitly need off-main work and the closure captures only `Sendable` values)

**Protecting shared mutable state?**
→ Use an `actor` type

**Calling async API from a sync context?**
→ Wrap in `Task { await ... }` inside a `@MainActor` method

**Parallelizing independent work?**
→ Use `async let` or `TaskGroup`

## Key Rules

1. **Check isolation first** — trace where each piece of code runs before adding `await` or `Task`
2. **Don't blanket-`@MainActor` everything** — it's the default here, but understand why you're using it
3. **Prefer structured concurrency** — `async let` and `TaskGroup` over `Task.detached`
4. **Document unsafe escapes** — if you use `@unchecked Sendable`, add a comment explaining why it's safe
5. **Never use `DispatchSemaphore` in async contexts** — it blocks the thread and can deadlock

## Common Pitfalls

| Pitfall | Fix |
|---|---|
| `async` doesn't mean background | It suspends, not offloads — use `Task.detached` + `await` for true background work |
| Too many actors | Most state belongs on `@MainActor`; create actors only for explicitly shared, background-updated state |
| `try?` in async loops | Silent failure swallows errors — use proper `do/catch` or `Result` |
| Unnecessary context switches | Don't hop to background and back for trivial work; batch background operations |

## SwiftData + Concurrency

- All `ModelContext` operations must run on `@MainActor`
- Never pass model objects across actor boundaries — pass IDs instead and re-fetch
- `@Query` macro handles observation automatically; don't replicate it with manual `Task` polling
