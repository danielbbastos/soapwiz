import Foundation
import SwiftData
@testable import SoapWiz

/// Counts the fetches the batch rows make, and fails them on demand.
@MainActor
final class BatchFetchCounter {
    struct Failure: Error {}

    private(set) var count = 0
    var shouldFail = false

    func fetch(_ context: ModelContext) throws -> [Batch] {
        count += 1
        if shouldFail { throw Failure() }
        return try BatchRows.fetchAll(in: context)
    }
}
