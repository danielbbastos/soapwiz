import Foundation

/// Reads a payload back, and refuses the ones it must not read.
///
/// Two entry points because the two transports fail differently. A file the user
/// deliberately picked has no fallback — if it can't be read they need to be
/// told why. Pasted text that merely looks like a payload is better ignored
/// than reported: it goes on to be read as a recipe like any other text.
enum RecipeTransferDecoder {

    /// Decodes a `.soapwizrecipe` file, throwing what went wrong.
    static func payload(fromFile data: Data) throws -> RecipeTransferData {
        guard let payload = try? RecipeTransferCoding.decoder.decode(RecipeTransferData.self, from: data) else {
            throw RecipeTransferError.malformedFile
        }
        try validate(payload)
        return payload
    }

    /// Reads a `.soapwizrecipe` file pasted as text.
    ///
    /// The share sheet's Copy puts the *file* on the pasteboard, and since the
    /// type conforms to `public.json` — and so to `public.text` — pasting it
    /// yields the bare JSON. Refusing that would mean the app writing something
    /// it then can't read back, from a button sitting right next to Save to
    /// Files. Anything that isn't our payload shape simply fails to decode and
    /// goes on to `RecipeTextExportReader` or the language model.
    static func scan(text: String) -> RecipeTransferScan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let json = trimmed.data(using: .utf8) else { return .none }
        return scan(json)
    }

    /// Decodes payload JSON without throwing, for the clipboard path.
    static func scan(_ json: Data) -> RecipeTransferScan {
        do {
            return .payload(try payload(fromFile: json))
        } catch let error as RecipeTransferError {
            switch error {
            case .unsupportedVersion:
                // Worth interrupting for. The user has a real recipe in hand and
                // needs to know an app update is what stands between them.
                return .rejected(error)
            case .malformedFile:
                // Not worth interrupting for. Fall through to the text path.
                return .none
            }
        } catch {
            return .none
        }
    }

    /// Rejects a payload this build must not read.
    ///
    /// A newer format is refused outright rather than read in part. Decoding
    /// would otherwise succeed by ignoring keys it doesn't recognise — and a
    /// recipe silently missing whichever field a later version added would
    /// calculate a different lye weight without ever saying so.
    private static func validate(_ payload: RecipeTransferData) throws {
        guard payload.version <= RecipeTransferData.currentVersion else {
            throw RecipeTransferError.unsupportedVersion(
                found: payload.version,
                supported: RecipeTransferData.currentVersion
            )
        }
        guard payload.version > 0, payload.hasResolvableIngredientIndices else {
            throw RecipeTransferError.malformedFile
        }
    }
}

/// What pasted text turned out to hold.
enum RecipeTransferScan: Equatable {
    case none
    case payload(RecipeTransferData)

    /// A payload this build must not read, such as one from a newer version.
    case rejected(RecipeTransferError)
}
