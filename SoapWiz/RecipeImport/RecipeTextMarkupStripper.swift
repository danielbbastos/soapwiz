import Foundation

/// Reduces a paste to plain prose: HTML and Markdown markup out, entities
/// decoded, page furniture dropped.
///
/// A recipe copied from a browser rarely arrives clean — it brings tags,
/// entities, table pipes, share buttons and a comment section. All of that
/// costs tokens against a 4,096-token window that has to hold the instructions,
/// the schema, the recipe and the answer, so removing it is what makes a real
/// blog post fit at all.
enum RecipeTextMarkupStripper {
    static func stripMarkup(_ raw: String) -> String {
        var text = raw
        text = removeAll(in: text, pattern: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>")
        text = removeAll(in: text, pattern: "<!--[\\s\\S]*?-->")
        text = replaceAll(in: text, pattern: "<(br|hr)\\s*/?>", with: "\n")
        text = replaceAll(in: text, pattern: "</(p|div|li|ul|ol|tr|table|h[1-6]|section|article)\\s*>", with: "\n")
        text = replaceAll(in: text, pattern: "</(td|th)\\s*>", with: " ")
        text = removeAll(in: text, pattern: "<[^>]+>")
        text = decodeEntities(text)
        text = stripMarkdown(text)
        return text
    }

    /// Markdown arrives whenever a recipe is copied out of Reddit, a forum or a
    /// notes app. Table pipes and heading hashes carry no meaning here, and the
    /// pipes in particular glue numbers to units in a way that reads badly.
    static func stripMarkdown(_ raw: String) -> String {
        var text = raw
        text = removeAll(in: text, pattern: "!\\[[^\\]]*\\]\\([^)]*\\)")
        text = replaceAll(in: text, pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1")
        text = removeAll(in: text, pattern: "(?m)^\\s*\\|?[\\s:-]*\\|[\\s|:-]*$")
        text = replaceAll(in: text, pattern: "\\|", with: " ")
        text = removeAll(in: text, pattern: "(?m)^\\s{0,3}#{1,6}\\s+")
        text = removeAll(in: text, pattern: "(\\*\\*|__|`)")
        return text
    }

    static func decodeEntities(_ raw: String) -> String {
        guard raw.contains("&") else { return raw }
        var text = raw
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = replaceNumericEntities(in: text)
        return text
    }

    /// Whole lines that are page furniture rather than recipe. Matched against
    /// the lower-cased, trimmed line, and only when the line is short — "print"
    /// on its own is a button, but a sentence containing it may be a step.
    static func isBoilerplate(_ line: String) -> Bool {
        let lowered = line.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return false }
        if lowered.count <= 40, boilerplatePhrases.contains(where: lowered.contains) { return true }
        if isInterfaceChrome(lowered) { return true }
        return lowered.range(of: "^[^\\p{L}\\p{N}]+$", options: .regularExpression) != nil
    }

    /// Screen furniture that survives OCR of a screenshot: tab bars, nav bars,
    /// the status-bar clock.
    ///
    /// Matched whole-line and exactly, never as a substring. "Save" alone is a
    /// button; "Save 10% for superfat" is a recipe instruction, and a
    /// `contains` check would take both. That distinction is the only thing
    /// keeping this list safe to grow.
    static func isInterfaceChrome(_ loweredLine: String) -> Bool {
        let stripped = loweredLine
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(.whitespaces))
            .trimmingCharacters(in: .whitespaces)
        if chromeWords.contains(stripped) { return true }
        // A bare clock, with or without a meridiem: "9:41", "23:45", "9:41 PM".
        return stripped.range(of: "^[0-9]{1,2}:[0-9]{2}( ?[ap]m)?$", options: .regularExpression) != nil
    }

    static func removeURLs(_ line: String) -> String {
        removeAll(in: line, pattern: "(https?://|www\\.)\\S+")
    }

    // MARK: - Regex helpers

    private static func removeAll(in text: String, pattern: String) -> String {
        replaceAll(in: text, pattern: pattern, with: "")
    }

    private static func replaceAll(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replaceNumericEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let digitsRange = Range(match.range(at: 2), in: result) else { continue }
            let isHex = match.range(at: 1).length > 0
            let digits = String(result[digitsRange])
            guard let value = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }

    // MARK: - Vocabulary

    /// The entities that actually turn up in copied recipes: spacing, quotes,
    /// dashes, degrees and the vulgar fractions bakers and soapers use.
    private static let namedEntities: [(String, String)] = [
        ("&nbsp;", " "), ("&ensp;", " "), ("&emsp;", " "), ("&thinsp;", " "),
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ("&#39;", "'"), ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
        ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"),
        ("&ndash;", "\u{2013}"), ("&mdash;", "\u{2014}"), ("&hellip;", "\u{2026}"),
        ("&deg;", "\u{00B0}"), ("&frac12;", "1/2"), ("&frac14;", "1/4"), ("&frac34;", "3/4"),
        ("&times;", "\u{00D7}"), ("&bull;", "\u{2022}"), ("&amp;", "&")
    ]

    /// Whole-line matches only. Words that could plausibly begin a recipe line
    /// — "water", "oils", "total" — are deliberately absent.
    private static let chromeWords: Set<String> = [
        "home", "menu", "search", "back", "next", "previous", "close", "done", "cancel",
        "edit", "delete", "share", "save", "print", "more", "show more", "load more",
        "read more", "see all", "view all", "follow", "following", "followers",
        "sign in", "sign up", "log in", "log out", "register", "account", "profile",
        "settings", "notifications", "messages", "cart", "checkout", "shop", "store",
        "explore", "discover", "library", "saved", "help", "support", "about",
        "contact", "faq", "blog", "recipes", "reviews", "rating", "ratings",
        "like", "likes", "reply", "replies", "views", "comments", "share this",
        "skip", "skip to content", "accept", "accept all", "reject", "reject all",
        "allow", "got it", "ok", "okay", "continue", "learn more", "advertisement",
        "sponsored", "ad", "top", "back to top", "aa", "done editing"
    ]

    private static let boilerplatePhrases = [
        "share this", "share on", "print recipe", "pin it", "pin this", "save recipe",
        "jump to recipe", "leave a comment", "leave a reply", "comments", "related posts",
        "you may also like", "you might also like", "subscribe", "newsletter", "advertisement",
        "cookie", "privacy policy", "terms of use", "all rights reserved", "copyright",
        "posted on", "filed under", "tagged with", "read more", "continue reading",
        "previous post", "next post", "add to cart", "log in", "sign up", "rate this",
        "affiliate", "follow us", "skip to content", "back to top"
    ]
}
