import AppKit

/// Clipboard access that respects macOS's paste privacy: Reel only asks *whether* a
/// web link was copied (which shows no prompt) and reads it when you choose to use it.
enum Clipboard {
    /// Increments whenever anything new is copied; lets Reel avoid re-checking.
    static var changeCount: Int { NSPasteboard.general.changeCount }

    @MainActor
    static func containsWebLink() async -> Bool {
        let wanted: Set<PartialKeyPath<NSPasteboard.DetectedValues>> = [\.probableWebURL]
        guard let found = try? await NSPasteboard.general.detectedPatterns(for: wanted) else { return false }
        return found.contains(\.probableWebURL)
    }

    /// Reads the copied link. Only call this in response to the user asking for it.
    static func readLink() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !string.contains(" "), !string.contains("\n"),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return string
    }
}

enum Support {
    static let kofi = URL(string: "https://ko-fi.com/shivvaaxx")!
    static let sponsors = URL(string: "https://github.com/sponsors/shivvaaxx")!
    static let repository = URL(string: "https://github.com/shivvaaxx/Reel")!
}
