import Foundation
import SwiftData
import Testing
@testable import SoapWiz

@MainActor
@Suite
struct CSVImportFlowViewModelTests {
    private struct PickerFailure: Error {}

    private let locale = Locale(identifier: "en_US_POSIX")
    private let calendar = Calendar(identifier: .gregorian)

    private func makeSUT() -> CSVImportFlowViewModel {
        CSVImportFlowViewModel(locale: locale, calendar: calendar)
    }

    private func withTempFile<T>(_ data: Data, _ body: (URL) async throws -> T) async throws -> T {
        let url = FileManager.default.temporaryDirectory.appending(path: "csv-flow-\(UUID().uuidString).csv")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }

    private func openMapping(_ data: Data, on sut: CSVImportFlowViewModel) async throws -> CSVMappingViewModel {
        try await withTempFile(data) { url in
            await sut.open(.success(url))
        }
        guard case .mapping(let mapping) = sut.phase else {
            throw FlowError.notMapping
        }
        return mapping
    }

    private enum FlowError: Error {
        case notMapping
        case notReview
    }

    private func nameCell(of mapping: CSVMappingViewModel) -> String? {
        mapping.columns.first.flatMap(\.samples.first)
    }

    private let csv = "Name,Quantity\nManteiga de Karité,500 g\nZzyzx Butter,200 g\n"

    // MARK: - Reading

    @Test func open_Utf8WithBom_ReachesMapping() async throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)

        let mapping = try await openMapping(data, on: makeSUT())

        #expect(nameCell(of: mapping) == "Manteiga de Karité")
        #expect(mapping.field(for: 0) == .name)
    }

    @Test func open_Windows1252_ReadsAccentedName() async throws {
        let data = try #require(csv.data(using: .windowsCP1252))

        let mapping = try await openMapping(data, on: makeSUT())

        #expect(nameCell(of: mapping) == "Manteiga de Karité")
    }

    @Test func open_Utf16LittleEndianWithBom_ReachesMapping() async throws {
        let data = Data([0xFF, 0xFE]) + (try #require(csv.data(using: .utf16LittleEndian)))

        let mapping = try await openMapping(data, on: makeSUT())

        #expect(nameCell(of: mapping) == "Manteiga de Karité")
    }

    @Test func open_HeaderlessNumericFile_MapsNothing() async throws {
        let mapping = try await openMapping(Data("1,2\n3,4\n".utf8), on: makeSUT())

        #expect(!mapping.hasHeaderRow)
        #expect(mapping.field(for: 0) == nil)
        #expect(!mapping.canContinue)
    }

    @Test func open_EmptyFile_Fails() async throws {
        let sut = makeSUT()

        try await withTempFile(Data()) { url in
            await sut.open(.success(url))
        }

        guard case .failed = sut.phase else {
            Issue.record("Expected .failed")
            return
        }
    }

    @Test func open_OnlyBlankLines_Fails() async throws {
        let sut = makeSUT()

        try await withTempFile(Data("\n\n  \n".utf8)) { url in
            await sut.open(.success(url))
        }

        guard case .failed = sut.phase else {
            Issue.record("Expected .failed")
            return
        }
    }

    @Test func open_MissingFile_Fails() async {
        let sut = makeSUT()
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).csv")

        await sut.open(.success(url))

        guard case .failed = sut.phase else {
            Issue.record("Expected .failed")
            return
        }
    }

    @Test func open_PickerFailure_Fails() async {
        let sut = makeSUT()

        await sut.open(.failure(PickerFailure()))

        guard case .failed = sut.phase else {
            Issue.record("Expected .failed")
            return
        }
    }

    @Test func restart_AfterFailure_ReturnsToStart() async {
        let sut = makeSUT()
        await sut.open(.failure(PickerFailure()))

        sut.restart()

        guard case .start = sut.phase else {
            Issue.record("Expected .start")
            return
        }
        #expect(!sut.isPastStart)
    }

    @Test func isPastStart_TrueOnceAFileIsOpen() async throws {
        let sut = makeSUT()
        #expect(!sut.isPastStart)

        _ = try await openMapping(Data(csv.utf8), on: sut)

        #expect(sut.isPastStart)
    }

    // MARK: - Review

    @Test func continueToReview_HiddenIngredientMatches_StaysHiddenAndOtherRowIsNew() async throws {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [.inMemory(schema)])
        let context = container.mainContext
        let shea = Ingredient(name: "Shea Butter", unit: "g")
        shea.isHidden = true
        context.insert(shea)
        try context.save()
        let ingredientsBefore = try context.fetch(FetchDescriptor<Ingredient>()).count
        let purchasesBefore = try context.fetch(FetchDescriptor<IngredientPurchase>()).count
        let sut = makeSUT()
        _ = try await openMapping(Data("Name,Quantity\nShea Butter,200 g\nZzyzx Butter,300 g\n".utf8), on: sut)

        await sut.continueToReview(inventory: [shea])

        guard case .review(let review) = sut.phase else { throw FlowError.notReview }
        let matched = try #require(review.plan.entries.first { $0.name == "Shea Butter" })
        let created = try #require(review.plan.entries.first { $0.name == "Zzyzx Butter" })
        #expect(!matched.isNew)
        #expect(created.isNew)
        #expect(shea.isHidden)
        #expect(try context.fetch(FetchDescriptor<Ingredient>()).count == ingredientsBefore)
        #expect(try context.fetch(FetchDescriptor<IngredientPurchase>()).count == purchasesBefore)
    }

    @Test func backToMapping_ReturnsSameMappingWithItsFields() async throws {
        let sut = makeSUT()
        let mapping = try await openMapping(Data("Name,Quantity,Notes\nA,1 g,x\n".utf8), on: sut)
        mapping.setField(.supplier, for: 2)
        await sut.continueToReview(inventory: [])

        sut.backToMapping()

        guard case .mapping(let returned) = sut.phase else {
            Issue.record("Expected .mapping")
            return
        }
        #expect(returned === mapping)
        #expect(returned.field(for: 2) == .supplier)
    }

    @Test func finish_MovesToFinishedWithReviewSummary() async throws {
        let sut = makeSUT()
        _ = try await openMapping(Data(csv.utf8), on: sut)
        await sut.continueToReview(inventory: [])
        guard case .review(let review) = sut.phase else { throw FlowError.notReview }
        let result = InventoryImportResult(importedRows: 2, skippedRows: 0, ingredientsCreated: 2, purchasesAdded: 2)

        sut.finish(result)

        guard case .finished(let summary) = sut.phase else {
            Issue.record("Expected .finished")
            return
        }
        #expect(summary == (review.resultSummary ?? ""))
    }

    @Test func finish_OutsideReview_StaysInPhase() {
        let sut = makeSUT()

        sut.finish(InventoryImportResult())

        guard case .start = sut.phase else {
            Issue.record("Expected .start")
            return
        }
    }
}
