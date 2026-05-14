# Reference Index

Quick navigation for Swift Concurrency topics.

## Fundamentals

| File | Description |
|------|-------------|
| `async-await-basics.md` | Core async/await patterns, execution order, async let |
| `tasks.md` | Task lifecycle, cancellation, priorities, task groups |
| `glossary.md` | Term definitions for quick lookup |

## Thread Safety & Isolation

| File | Description |
|------|-------------|
| `actors.md` | Actor isolation, @MainActor, global actors, reentrancy |
| `sendable.md` | Sendable conformance, value/reference types, @unchecked |
| `threading.md` | Thread/task relationship, suspension points, isolation domains |

## Advanced Patterns

| File | Description |
|------|-------------|
| `async-sequences.md` | AsyncSequence, AsyncStream, bridging callbacks |
| `memory-management.md` | Retain cycles in tasks, cleanup patterns |
| `task-local-values.md` | Task-local context propagation, tracing patterns |
| `performance.md` | Profiling with Instruments, optimization strategies |

## SwiftUI & SwiftData

| File | Description |
|------|-------------|
| `swiftui-concurrency-tour.md` | SwiftUI-specific concurrency, Sendable closures, .task modifier |
| `swiftdata.md` | ModelContext isolation, PersistentIdentifier, @Query placement |

## Integration & Migration

| File | Description |
|------|-------------|
| `migration.md` | Swift 6 migration strategy, @preconcurrency |
| `testing.md` | Swift Testing async patterns, XCTest, flaky test fixes |
| `linting.md` | SwiftLint rules, warning suppression strategies |
| `production-pitfalls.md` | Silent data loss, cancellation gaps, .task vs onAppear |

## Swift 6.2+

| File | Description |
|------|-------------|
| `swift-6-2-concurrency.md` | Philosophy change, isolated conformances, main-actor-by-default |
| `approachable-concurrency.md` | Approachable concurrency mode quick guide |

## Quick Links by Problem

| Problem | File |
|---------|------|
| Concurrency warning I don't understand | `threading.md`, `actors.md` |
| Sendable error | `sendable.md` |
| SwiftData crash or race | `swiftdata.md` |
| Task not cancelling | `tasks.md`, `production-pitfalls.md` |
| Memory leak with async | `memory-management.md` |
| Test is flaky or hangs | `testing.md` |
| Migrating to Swift 6 | `migration.md` |
| UI is janky / hangs | `performance.md`, `production-pitfalls.md` |
| async != background thread | `production-pitfalls.md` section 2 |
