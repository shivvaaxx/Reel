import AppKit

/// Clipboard access that respects macOS's paste privacy: Reel only asks *whether* a
/// web link was copied (which shows no prompt) and reads it when you choose to use it.
enum Clipboard {
    /// Increments whenever anything new is copied; lets Reel avoid re-checking.
    static var changeCount: Int { NSPasteboard.general.changeCount }

    // AppKit's pattern detection isn't safe to run twice at once (it crashed when the window
    // and the menu bar panel asked together), so every caller shares one request, and the
    // answer is reused until something new is copied.
    @MainActor private static var inFlight: (count: Int, task: Task<Bool, Never>)?
    @MainActor private static var cached: (count: Int, hasLink: Bool)?

    @MainActor
    static func containsWebLink() async -> Bool {
        let count = changeCount
        if let cached, cached.count == count { return cached.hasLink }
        if let inFlight, inFlight.count == count { return await inFlight.task.value }
        let task = Task { @MainActor () -> Bool in
            let wanted: Set<PartialKeyPath<NSPasteboard.DetectedValues>> = [\.probableWebURL]
            guard let found = try? await NSPasteboard.general.detectedPatterns(for: wanted) else { return false }
            return found.contains(\.probableWebURL)
        }
        inFlight = (count, task)
        let result = await task.value
        if inFlight?.count == count { inFlight = nil }
        cached = (count, result)
        return result
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
