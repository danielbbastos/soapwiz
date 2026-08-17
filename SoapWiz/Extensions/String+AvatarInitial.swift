import Foundation

extension String {
    /// The character an avatar draws when there is no photo: the first one of the
    /// name, uppercased. Empty for a name that is empty or only whitespace, which
    /// leaves the avatar showing its colour alone rather than a stand-in
    /// character the user never typed.
    ///
    /// Lives here rather than on `Ingredient` because the form needs the same
    /// letter for a name still being typed, before there is any ingredient to
    /// ask.
    var avatarInitial: String {
        guard let first = trimmingCharacters(in: .whitespacesAndNewlines).first else { return "" }
        return String(first).uppercased()
    }
}
