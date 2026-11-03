import AppKit
import UniformTypeIdentifiers

/// "Reel" in the Share menu: sends the shared page or link to Reel and closes at once.
final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handOff() }
    }

    private func handOff() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var link: String?

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await Self.loadURL(from: provider) {
                link = url.absoluteString
                break
            }
        }
        if link == nil {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let found = Self.firstLink(in: text) {
                    link = found
                    break
                }
            }
        }

        if let link, ReelLink.send(link) {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            let error = NSError(domain: "Reel", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "There's no web link to send to Reel."])
            extensionContext?.cancelRequest(withError: error)
        }
    }

    /// A shared link can arrive as a URL object, as URL data, or as text, depending on the app.
    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: NSURL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: (object as? NSURL) as URL?)
                }
            }
            if let url { return url }
        }
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        switch item {
        case let url as URL: return url
        case let data as Data:
            return URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap { URL(string: $0) }
        case let text as String: return URL(string: text)
        default: return nil
        }
    }

    private static func firstLink(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url?.absoluteString
    }
}
