import AppIntents
import ExtensionFoundation
import Foundation

/// Shortcuts actions for Reel, shipped as an App Intents extension.
@main
struct ReelIntentsExtension: AppIntentsExtension {}

enum DownloadQuality: String, AppEnum {
    case best, p2160, p1440, p1080, p720, p480, audio

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quality"
    static let caseDisplayRepresentations: [DownloadQuality: DisplayRepresentation] = [
        .best: "Best Available", .p2160: "4K", .p1440: "1440p", .p1080: "1080p",
        .p720: "720p", .p480: "480p", .audio: "Audio Only",
    ]
}

struct DownloadWithReel: AppIntent {
    static let title: LocalizedStringResource = "Download with Reel"
    static let description = IntentDescription(
        "Downloads a video, playlist or photo post with Reel. Works with YouTube, Instagram, TikTok and over a thousand other sites.",
        categoryName: "Downloads")

    @Parameter(title: "Link", description: "The page or video to download.")
    var link: URL

    @Parameter(title: "Quality", default: .best)
    var quality: DownloadQuality

    static var parameterSummary: some ParameterSummary {
        Summary("Download \(\.$link) with Reel") {
            \.$quality
        }
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard ["http", "https"].contains(link.scheme?.lowercased() ?? "") else {
            throw $link.needsValueError("That isn't a web link. Which page should Reel download?")
        }
        var components = URLComponents()
        components.scheme = "reel"
        components.host = "download"
        components.queryItems = [URLQueryItem(name: "url", value: link.absoluteString),
                                 URLQueryItem(name: "quality", value: quality.rawValue)]
        guard let reel = components.url else { return .result(opensIntent: OpenURLIntent(link)) }
        return .result(opensIntent: OpenURLIntent(reel))
    }
}

struct OpenReel: AppIntent {
    static let title: LocalizedStringResource = "Open Reel"
    static let description = IntentDescription("Opens Reel's window.", categoryName: "Downloads")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "reel://open")!))
    }
}

struct ReelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenReel(), phrases: ["Open \(.applicationName)"],
                    shortTitle: "Open Reel", systemImageName: "arrow.down.circle")
    }
}
