import AppKit
import Darwin
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
            // Any web page can open a reel:// link, so it may not reach this Mac or its network.
            let links = items.filter { $0.name == "url" }.compactMap(\.value).filter(isPublicWebLink)
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

    /// A web link whose host isn't this Mac or a private network (router pages, local servers).
    /// Names that resolve to a private address are not caught; this stops the direct cases.
    static func isPublicWebLink(_ text: String) -> Bool {
        guard isWebLink(text), let host = URL(string: text)?.host?.lowercased() else { return false }
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local")
            || name.hasSuffix(".internal") || name.hasSuffix(".lan") || name.hasSuffix(".home.arpa") { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let numeric = labels.allSatisfy { $0.range(of: #"^(0x[0-9a-f]*|[0-9]+)$"#, options: .regularExpression) != nil }
        if numeric {
            // Only plain dotted-decimal addresses pass; hex, octal and shortened forms
            // (0x7f.1, 0177.0.0.1, 127.1) can all mean this Mac.
            let parts = labels.compactMap { Int($0) }
            guard labels.count == 4, parts.count == 4, labels.allSatisfy({ $0 == "0" || !$0.hasPrefix("0") }),
                  parts.allSatisfy({ (0...255).contains($0) }) else { return false }
            let a = parts[0], b = parts[1]
            return !(a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b))
                     || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) || a >= 224)
        }
        if name.contains(":") { return isPublicIPv6(name) }
        // A single-word name ("router", "nas") is looked up on the local network.
        return name.contains(".")
    }

    /// Classifies a parsed IPv6 address; forms that carry an IPv4 address are judged by it.
    private static func isPublicIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text.split(separator: "%").first.map(String.init) ?? text, &address) == 1 else {
            return false
        }
        let b = withUnsafeBytes(of: &address) { Array($0) }
        if b.allSatisfy({ $0 == 0 }) { return false }                                   // ::
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return false }             // ::1
        if b[0] & 0xFE == 0xFC { return false }                                         // fc00::/7 unique local
        if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return false }                         // fe80::/10 link-local
        if b[0] == 0xFE && b[1] & 0xC0 == 0xC0 { return false }                         // fec0::/10 site-local
        if b[0] == 0xFF { return false }                                                // multicast
        let embedded = b[12..<16].map(String.init).joined(separator: ".")
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {         // ::ffff:a.b.c.d
            return isPublicWebLink("http://\(embedded)/")
        }
        if b[0..<12].allSatisfy({ $0 == 0 }) { return isPublicWebLink("http://\(embedded)/") }  // ::a.b.c.d
        if b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xFF && b[3] == 0x9B {               // 64:ff9b:: NAT64
            return isPublicWebLink("http://\(embedded)/")
        }
        return true
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
