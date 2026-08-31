import Foundation

/// The one JSON configuration both transports use.
///
/// Shared so a file and a clipboard marker can never disagree about how a date
/// or a number is written. Dates are ISO-8601 and keys keep their Swift names:
/// the payload crosses between devices in different locales and time zones, and
/// nothing in it may depend on the sender's.
enum RecipeTransferCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Stable key order, so the same recipe exported twice produces the same
        // bytes. Makes a payload diffable and a test able to compare output
        // rather than having to decode it first.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
