import AppKit

/// Builds the reel:// link the extensions use to hand a page to Reel.
enum ReelLink {
    static func download(_ link: String, quality: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "reel"
        components.host = "download"
        var items = [URLQueryItem(name: "url", value: link)]
        if let quality { items.append(URLQueryItem(name: "quality", value: quality)) }
        components.queryItems = items
        return components.url
    }

    /// Opens Reel with the link. Returns false if the link isn't a web page.
    @discardableResult
    static func send(_ link: String, quality: String? = nil) -> Bool {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let reel = download(link, quality: quality) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false   // stay in the app you're in
        NSWorkspace.shared.open(reel, configuration: configuration)
        return true
    }
}
