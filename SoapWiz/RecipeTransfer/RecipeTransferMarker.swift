import Foundation

/// The clipboard envelope: how a `RecipeTransferData` rides on the end of the
/// human-readable text "Copy Recipe" produces.
///
/// "Copy Recipe" serves two audiences with one action. A person pastes it into
/// a message or a forum post and reads it; SoapWiz pastes it into the importer
/// and decodes it. So the readable text is left exactly as it was and the
/// payload becomes one final line:
///
///     SOAPWIZ-RECIPE-V1:<base64url of deflated JSON>
///
/// One line rather than embedded JSON because messaging apps reflow paragraphs
/// and would break a multi-line block apart. base64url rather than base64
/// because `+` and `/` get percent-escaped by some clients and `=` padding gets
/// stripped by others; the alphabet here survives a URL, a chat bubble and a
/// forum's markdown intact.
///
/// The file transport carries the same payload as plain JSON — nothing reads a
/// file by eye, so it has no reason to be compressed or armoured.
enum RecipeTransferMarker {
    /// The envelope version, distinct from `RecipeTransferData.version`. This
    /// one describes how the bytes are wrapped — the compression and the
    /// alphabet — so a future change to the wrapping can be rejected cleanly by
    /// a build that only understands this one. The payload's own version
    /// describes what the JSON contains.
    static let currentEnvelopeVersion = 1

    static let prefix = "SOAPWIZ-RECIPE-V"

    /// The alphabet a blob may use. Anything else means the line was mangled in
    /// transit — a client that wrapped it, or a forum that linkified it.
    private static let blobCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    // MARK: - Encoding

    /// Wraps a payload as the marker line, or `nil` if it can't be encoded.
    ///
    /// Returning `nil` rather than throwing keeps the caller honest about what
    /// failure means here: "Copy Recipe" still has a perfectly good recipe to
    /// put on the clipboard, and a person reading it loses nothing. Only the
    /// exact round trip is unavailable.
    static func line(for payload: RecipeTransferData) -> String? {
        guard let json = try? RecipeTransferCoding.encoder.encode(payload),
              let compressed = try? (json as NSData).compressed(using: .zlib) else { return nil }
        return "\(prefix)\(currentEnvelopeVersion):\(base64url(from: compressed as Data))"
    }

    // MARK: - Decoding

    /// Finds and unwraps a marker in pasted text.
    ///
    /// The last marker wins. Text accumulates as it is forwarded — a reply
    /// quoting the original leaves two markers in the box — and the one nearest
    /// the bottom belongs to the message the user is actually importing.
    static func scan(_ text: String) -> RecipeTransferScan {
        guard let marker = markers(in: text).last else { return .none }

        guard marker.envelopeVersion == currentEnvelopeVersion else {
            guard marker.envelopeVersion > currentEnvelopeVersion else { return .none }
            return .rejected(.unsupportedVersion(
                found: marker.envelopeVersion,
                supported: currentEnvelopeVersion
            ))
        }

        // A blob that won't decode is treated as no marker at all, so the
        // caller falls through to reading the text with the language model. A
        // recipe mangled in transit should still import approximately rather
        // than not at all — the readable text above the marker is intact.
        guard let compressed = data(fromBase64url: marker.blob),
              let json = try? (compressed as NSData).decompressed(using: .zlib) else { return .none }

        return RecipeTransferDecoder.scan(json as Data)
    }

    /// Whether a line is a marker, whatever its version and whatever state its
    /// blob is in. Used to keep the marker out of text bound for the language
    /// model, where it would only eat the character budget.
    static func isMarkerLine(_ line: String) -> Bool {
        parse(line: line) != nil
    }

    private static func markers(in text: String) -> [RecipeTransferMarkerLine] {
        text.components(separatedBy: .newlines).compactMap(parse(line:))
    }

    /// Reads one line as a marker, or returns `nil` if it isn't one.
    ///
    /// Whole-line only. A marker quoted mid-sentence in prose is someone talking
    /// about the format, not offering a payload, and reading it would import a
    /// recipe the user never asked for.
    private static func parse(line: String) -> RecipeTransferMarkerLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix) else { return nil }

        let remainder = trimmed.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }

        let digits = remainder[remainder.startIndex..<separator]
        let blob = remainder[remainder.index(after: separator)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let version = Int(digits) else { return nil }
        guard !blob.isEmpty, blob.allSatisfy(blobCharacters.contains) else { return nil }

        return RecipeTransferMarkerLine(envelopeVersion: version, blob: String(blob))
    }

    // MARK: - base64url

    private static func base64url(from data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64url encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // The padding was stripped on the way out because some clients eat a
        // trailing `=`; `Data(base64Encoded:)` requires it back.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

/// A marker line taken apart into its version and its blob, before either has
/// been judged.
private struct RecipeTransferMarkerLine {
    let envelopeVersion: Int
    let blob: String
}

/// What a scan of pasted text found.
enum RecipeTransferScan: Equatable {
    /// No marker, or one too damaged to read. The caller reads the text
    /// with the language model instead.
    case none
    case payload(RecipeTransferData)

    /// A marker this build must not read, rather than one it failed to read.
    case rejected(RecipeTransferError)
}
