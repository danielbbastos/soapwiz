import Foundation

/// Turns the bytes of a picked CSV file into text.
///
/// Spreadsheet exports come in three encodings: UTF-8 (with or without a byte
/// order mark), UTF-16 (Excel's "Unicode Text", always with a mark), and
/// Windows-1252 from older European Excel installs. A byte order mark decides
/// on its own. Without one the file is read as UTF-8 when it is valid UTF-8,
/// and as Windows-1252 otherwise: Windows-1252 accepts nearly any byte, so it
/// can only be the fallback, never the first guess.
enum CSVTextDecoder {
    /// The text in `data` with any byte order mark removed, or nil when the
    /// data is empty or can't be read in any of the supported encodings.
    static func text(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }
}
