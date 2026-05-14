---
name: tests-developer
description: Smart router to testing patterns and practices. Use when writing unit tests, creating mocks, testing edge cases, or working with Swift Testing and XCTest frameworks.
---

# Tests Developer

Use this when writing or updating tests for SoapWiz. Tests are required for all non-trivial production code.

## Framework

Use **Swift Testing** for all new tests:

```swift
import Testing
@testable import SoapWiz

@Suite
struct IngredientTests {

    private let sut: Ingredient  // System Under Test

    init() {
        self.sut = Ingredient(name: "Lye", category: "Lye", unit: "g")
    }

    @Test func totalRemainingIsZeroWhenNoBatches() {
        #expect(sut.totalRemaining == 0)
    }
}
```

Preserve existing XCTest tests as-is — do not migrate them unless there's a clear reason.

## `@Suite` Variants

```swift
@Suite                     // Parallel execution (default) — prefer this
@Suite(.serialized)        // Sequential — only when tests share mutable state
```

Use `.serialized` when tests within a suite share a `ModelContainer` or other stateful resource that cannot be safely accessed concurrently.

## Structure

- One `@Suite` per model or feature area
- Declare the system under test as a property (`private let sut`), initialized in `init()`
- Test file naming: `<Subject>Tests.swift`
- Location: `SoapWizTests/` target (Xcode auto-includes any Swift file there)

## Test Naming

Use the pattern `testFeature_Condition_ExpectedBehavior`:

```swift
@Test func totalRemaining_NoBatches_ReturnsZero() { ... }
@Test func pricePerUnit_ZeroQuantity_ReturnsZero() { ... }
@Test func remainingAmount_AfterUse_Decrements() { ... }
```

## Required Coverage

When adding or changing code, write tests for:
- Computed properties (`totalRemaining`, `pricePerUnit`)
- Business logic in models
- Edge cases: empty collections, nil optionals, zero/negative quantities, boundary dates
- Deletion and cascade behavior (verify orphaned records don't accumulate)

## Arrange-Act-Assert Pattern

```swift
@Test func pricePerUnit_CalculatesCorrectly() {
    // Arrange
    let batch = IngredientBatch(quantity: 500, totalPrice: 10.0, ...)

    // Act
    let result = batch.pricePerUnit

    // Assert
    #expect(result == 0.02)
}
```

## Assertions Quick Reference

### Swift Testing
```swift
#expect(value == expected)
#expect(value != unexpected)
#expect(result != nil)
#expect(array.isEmpty)
#expect(throws: SomeError.self) { try throwingFunction() }
let value = try #require(optionalValue)  // unwrap or fail — never use !
```

### XCTest (legacy)
```swift
XCTAssertEqual(actual, expected)
XCTAssertNil(value)
XCTAssertNotNil(value)
XCTAssertTrue(condition)
XCTAssertThrowsError(try expression)
let value = try XCTUnwrap(optionalValue)  // never use !
```

## Edge Case Checklist

Always cover:

```swift
@Test func process_EmptyCollection_ReturnsEmpty() {
    #expect(sut.process([]).isEmpty)
}

@Test func process_NilInput_ReturnsNil() {
    #expect(sut.process(nil) == nil)
}

@Test func process_SingleItem_ReturnsSingleResult() {
    let result = sut.process([item])
    #expect(result.count == 1)
}

@Test func process_AtLimit_DoesNotExceedMax() {
    let items = (0..<100).map { makeItem(id: "\($0)") }
    #expect(sut.process(items).count <= 100)
}
```

## SwiftData Testing

Use an in-memory `ModelContainer` — never test against a persisted store:

```swift
@Suite(.serialized)
struct IngredientPersistenceTests {

    private var container: ModelContainer
    private var context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Ingredient.self, IngredientBatch.self, configurations: config)
        context = ModelContext(container)
    }

    @Test func cascadeDelete_RemovesBatches() throws {
        let ingredient = Ingredient(name: "Lye", category: "Lye", unit: "g")
        let batch = IngredientBatch(quantity: 100, ...)
        ingredient.batches.append(batch)
        context.insert(ingredient)
        try context.save()

        context.delete(ingredient)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<IngredientBatch>())
        #expect(remaining.isEmpty)
    }
}
```

## Mock Helpers

Create static `.mock()` factory methods as extensions **at the bottom of the test file** — not in separate mock files:

```swift
// At the bottom of IngredientTests.swift
extension Ingredient {
    static func mock(
        name: String = "Lye",
        category: String = "Lye",
        unit: String = "g"
    ) -> Ingredient {
        Ingredient(name: name, category: category, unit: unit)
    }
}

extension IngredientBatch {
    static func mock(
        quantity: Double = 500,
        totalPrice: Double = 10.0,
        remainingAmount: Double? = nil
    ) -> IngredientBatch {
        let batch = IngredientBatch(quantity: quantity, totalPrice: totalPrice, ...)
        if let remaining = remainingAmount { batch.remainingAmount = remaining }
        return batch
    }
}
```

## When Refactoring Production Code

Before renaming a type, property, or method, find all test references:

```bash
grep -r "OldTypeName" SoapWizTests/ --include="*.swift"
grep -r "oldPropertyName" SoapWizTests/ --include="*.swift"
```

Update every affected test file and mock extension before submitting. Run tests to confirm nothing is broken.

## Rules

- No force unwrapping in tests — use `#require()` (Swift Testing) or `XCTUnwrap` (XCTest)
- Test observable behavior, not internal implementation details
- Prefer real types over mocks; only mock external system boundaries (e.g. network, clock)
- Use `.serialized` only when tests share mutable state — don't use it by default

## Checklist

- [ ] Computed properties tested (`totalRemaining`, `pricePerUnit`)
- [ ] Edge cases covered (nil, empty, zero, single item, boundary)
- [ ] In-memory `ModelContainer` used for SwiftData tests (not persistent)
- [ ] No force unwraps — `#require()` or `XCTUnwrap` instead
- [ ] Descriptive names: `testFeature_Condition_ExpectedBehavior`
- [ ] Mock helpers as static `.mock()` extensions at bottom of test file
- [ ] Tests pass locally before reporting done

## Running Tests

```bash
xcodebuild test \
  -project SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```
