import AppKit
import Foundation

/// Ways other apps hand links to Reel:
///  • reel://download?url=<link>[&quality=p1080][&clip=1:20-3:45]  (Safari extension, bookmarklet, scripts)
///  • the "Download with Reel" Services menu item, for selected links or text anywhere
enum Handoff {
    /// Whether links sent from other apps start right away (otherwise they open for preview).
    static var startImmediately: Bool {
        UserDefaults.standard.object(forKey: "handoffStartsImmediately") as? Bool ?? true
    }

    /// The bookmarklet people can drag to any browser's bookmarks bar.
    static let bookmarklet =
        "javascript:location.href='reel://download?url='+encodeURIComponent(location.href)"

    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "reel" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch url.host?.lowercased() {
        case "download":
            let links = items.filter { $0.name == "url" }.compactMap(\.value).filter(isWebLink)
            let quality = value("quality").flatMap(Quality.init(rawValue:))
            let clip = value("clip").flatMap(parseClip)
            send(links, quality: quality, clip: clip)
        case "open", nil:
            Shared.openMainWindow()
        default:
            break
        }
    }

    @MainActor
    static func send(_ links: [String], quality: Quality? = nil, clip: (Double?, Double?)? = nil) {
        guard !links.isEmpty else { return }
        if startImmediately || links.count > 1 {
            for link in links {
                if quality != nil || clip != nil {
                    Shared.queue.enqueue(link: link, title: Prefs.siteName(for: link) + " link", thumbnail: nil,
                                         quality: quality ?? Prefs.defaultQuality, clip: clip)
                } else {
                    Shared.queue.quickAdd(link)
                }
            }
            MenuBarController.shared.flashAccepted()
        } else {
            Shared.openMainWindow()
            NotificationCenter.default.post(name: .reelPreviewLink, object: links[0])
        }
    }

    static func isWebLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    static func parseClip(_ text: String) -> (Double?, Double?)? {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        return (TimeText.seconds(parts[0]), parts[1].isEmpty ? nil : TimeText.seconds(parts[1]))
    }

    /// Links in free text (Services can send a whole selected paragraph).
    static func links(in text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return (detector?.matches(in: text, range: range) ?? [])
            .compactMap { $0.url?.absoluteString }
            .filter(isWebLink)
            .filter { seen.insert($0).inserted }
    }
}

/// Backs the "Download with Reel" item in the Services menu.
final class ServiceProvider: NSObject {
    @objc func downloadLinks(_ pasteboard: NSPasteboard, userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var links: [String] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            links += urls.map(\.absoluteString).filter(Handoff.isWebLink)
        }
        if links.isEmpty, let text = pasteboard.string(forType: .string) {
            links = Handoff.links(in: text)
        }
        guard !links.isEmpty else {
            error.pointee = "Reel couldn't find a link in the selection." as NSString
            return
        }
        MainActor.assumeIsolated { Handoff.send(links) }
    }
}
