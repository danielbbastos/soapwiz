import Foundation
import Observation

/// Why a picked file can't be turned into rows.
nonisolated enum CSVFileError: Error {
    case unreadable
    case empty

    var message: String {
        switch self {
        case .unreadable: String(localized: "Couldn’t open that file.")
        case .empty: String(localized: "This file is empty.")
        }
    }
}

enum CSVImportPhase {
    case start
    case reading
    case mapping(CSVMappingViewModel)
    case building
    case review(InventoryImportReviewViewModel)
    case finished(summary: String)
    case failed(String)
}

/// Walks a spreadsheet import from the file picker to its result: read the
/// file, map its columns, check the rows, and report what was imported.
///
/// Nothing is written until the review screen confirms, so every phase before
/// `.finished` can be left without a trace.
@MainActor
@Observable
final class CSVImportFlowViewModel {
    private(set) var phase: CSVImportPhase = .start

    private let locale: Locale
    private let calendar: Calendar
    private var mapping: CSVMappingViewModel?

    init(locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) {
        self.locale = locale
        self.calendar = calendar
    }

    /// Whether leaving now would throw away work: a dismiss gesture is
    /// refused from the moment a file is open.
    var isPastStart: Bool {
        switch phase {
        case .start, .failed: false
        case .reading, .mapping, .building, .review, .finished: true
        }
    }

    func open(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else {
            phase = .failed(CSVFileError.unreadable.message)
            return
        }
        phase = .reading
        do {
            let rows = try await Self.readRows(at: url)
            let model = CSVMappingViewModel(rows: rows, locale: locale, calendar: calendar)
            mapping = model
            phase = .mapping(model)
        } catch {
            phase = .failed((error as? CSVFileError ?? .unreadable).message)
        }
    }

    func continueToReview(inventory: [Ingredient]) async {
        guard let mapping else { return }
        phase = .building
        let rows = await Self.buildRows(from: mapping.rowInput)
        let plan = InventoryImportMatcher.plan(for: rows, inventory: inventory)
        phase = .review(InventoryImportReviewViewModel(plan: plan))
    }

    func backToMapping() {
        guard let mapping else { return }
        phase = .mapping(mapping)
    }

    func finish() {
        guard case .review(let review) = phase else { return }
        phase = .finished(summary: review.resultSummary ?? "")
    }

    func restart() {
        guard case .failed = phase else { return }
        mapping = nil
        phase = .start
    }

    @concurrent
    private static func readRows(at url: URL) async throws -> [[String]] {
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw CSVFileError.unreadable }
        guard !data.isEmpty else { throw CSVFileError.empty }
        guard let text = CSVTextDecoder.text(from: data) else { throw CSVFileError.unreadable }
        let rows = CSVReader.rows(from: text)
        guard rows.contains(where: { !CSVInventoryRowBuilder.isBlank($0) }) else { throw CSVFileError.empty }
        return rows
    }

    @concurrent
    private static func buildRows(from input: CSVRowInput) async -> [InventoryImportRow] {
        input.rows()
    }
}
