# Tests Developer

Use this when writing or updating tests for SoapWiz. Tests are required for all non-trivial production code.

## Framework

Use **Swift Testing** for all new tests:

```swift
import Testing
@testable import SoapWiz

@Suite
struct IngredientTests {
    @Test func totalRemainingIsZeroWhenNoBatches() {
        let ingredient = Ingredient(name: "Lye", category: "Lye", unit: "g")
        #expect(ingredient.totalRemaining == 0)
    }
}
```

Preserve existing XCTest tests as-is — do not migrate them unless there's a clear reason.

## Structure

- One `@Suite` per model or feature area
- Test file naming: `<Subject>Tests.swift`
- Location: `SoapWizTests/` target (Xcode will auto-include any Swift file there)

## Required Coverage

When adding or changing code, write tests for:
- Computed properties (e.g., `totalRemaining`, `pricePerUnit`)
- Business logic in models
- Edge cases: empty collections, nil optionals, zero/negative quantities, boundary dates
- Deletion and cascade behavior (verify orphaned records don't accumulate)

## Arrange-Act-Assert Pattern

```swift
@Test func pricePerUnitCalculatesCorrectly() {
    // Arrange
    let batch = IngredientBatch(quantity: 500, totalPrice: 10.0, ...)

    // Act
    let result = batch.pricePerUnit

    // Assert
    #expect(result == 0.02)
}
```

## Mocking and Dependencies

- For SwiftData models: create an in-memory `ModelContainer` in test setup
- Use `ModelConfiguration(isStoredInMemoryOnly: true)` — never test against a persisted store
- Prefer real types over mocks; only mock external system boundaries

```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Ingredient.self, IngredientBatch.self, configurations: config)
}
```

## Rules

- No force unwrapping in tests — use `#require()` (Swift Testing) or `XCTUnwrap` (XCTest)
- Test the actual computed result, not an internal implementation detail
- When refactoring production code, update any tests that reference renamed symbols before submitting
- Run tests before reporting a task complete: `xcodebuild test -scheme SoapWiz -destination 'platform=iOS Simulator,name=iPhone 16'`

## Checklist

- [ ] New model properties have tests for computed values
- [ ] Edge cases covered (nil, empty, zero)
- [ ] In-memory `ModelContainer` used (not persistent)
- [ ] No force unwraps
- [ ] Tests pass locally before reporting done
