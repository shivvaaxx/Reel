import Foundation

enum Quality: String, CaseIterable, Identifiable {
    case best, p2160, p1440, p1080, p720, p480, audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .best: "Best Available"
        case .p2160: "4K"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .audio: "Audio Only"
        }
    }

    var maxHeight: Int? {
        switch self {
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        case .best, .audio: nil
        }
    }
}

enum AudioFormat: String, CaseIterable, Identifiable {
    case m4a, mp3
    var id: String { rawValue }
    var label: String { self == .m4a ? "AAC (.m4a)" : "MP3" }
}

/// A snapshot of settings taken when a download is queued.
struct DownloadOptions {
    var quality: Quality
    var audioFormat: AudioFormat
    var folder: URL
    var compatible: Bool
    var embedDetails: Bool
    var subtitles: Bool
    var subtitleLanguage: String
    /// Simultaneous connections per download (1 = accelerator off).
    var connections: Int
    /// Optional section of the video to download, in seconds.
    var clipStart: Double? = nil
    var clipEnd: Double? = nil

    var isClip: Bool { clipStart != nil || clipEnd != nil }

    static func current(quality: Quality) -> DownloadOptions {
        let d = UserDefaults.standard
        return DownloadOptions(
            quality: quality,
            audioFormat: AudioFormat(rawValue: d.string(forKey: "audioFormat") ?? "") ?? .m4a,
            folder: Prefs.downloadFolder,
            compatible: d.object(forKey: "compatible") as? Bool ?? true,
            embedDetails: d.object(forKey: "embedDetails") as? Bool ?? true,
            subtitles: d.bool(forKey: "subtitles"),
            subtitleLanguage: d.string(forKey: "subtitleLanguage") ?? "en",
            connections: d.object(forKey: "connections") as? Int ?? 8
        )
    }

    /// gallery-dl arguments for photo posts.
    func galleryArguments(for link: String) -> [String] {
        // @@G reports "item n of count" before each file, for progress.
        var args = ["-D", folder.path, "--Print", "prepare:@@G {num}|{count:?//}"]
        switch Prefs.site(for: link) {
        case .instagram:
            args += ["-f", "{username} {shortcode}{num:? //>02}.{extension}"]
        case .tiktok:
            // Readable names instead of TikTok's internal file IDs.
            args += ["-f", "{user} {title[b:120]}{num:? //>02}.{extension}"]
        default:
            break
        }
        args += Prefs.cookieArguments(for: link) + Prefs.proxyArguments
        args += ["--", link]
        return args
    }

    /// yt-dlp arguments for a full download. With `infoFile`, yt-dlp resumes from a plan the
    /// accelerator already fetched, finding the streams on disk and only merging/tagging.
    func videoArguments(for link: String, infoFile: URL? = nil) -> [String] {
        var args = [
            "--newline", "--no-colors", "--progress", "--no-simulate", "--no-mtime",
            "--progress-template", "download:@@P %(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.format_id)s",
            "--progress-template", "postprocess:@@PP %(progress.postprocessor)s",
            "--print", "before_dl:@@T %(title)s",
            "--print", "before_dl:@@S %(filesize,filesize_approx)s",
            "--print", "before_dl:@@I %(thumbnail)s",
            "--print", "before_dl:@@N %(filename)s",
            "--print", "after_move:@@F %(filepath)s",
            // Streaming (HLS/DASH) formats fetch their fragments in parallel too.
            "--concurrent-fragments", "\(max(1, connections))",
        ]
        args += selectionArguments(for: link, includeCookies: false)
        if quality != .audio && subtitles {
            let lang = subtitleLanguage.trimmingCharacters(in: .whitespaces)
            args += ["--embed-subs", "--sub-langs", "\(lang.isEmpty ? "en" : lang).*"]
        }
        if embedDetails {
            args += ["--embed-metadata", "--embed-thumbnail", "--embed-chapters"]
        }
        args += Prefs.cookieArguments(for: link)
        if let infoFile {
            args += ["--load-info-json", infoFile.path]
        } else {
            args += ["--", link]
        }
        return args
    }

    /// Format choice, output naming and conversion: shared by the accelerator's plan and the
    /// download itself so both pick exactly the same streams and file names.
    func selectionArguments(for link: String, includeCookies: Bool = true) -> [String] {
        var args = ["--no-playlist", "-P", folder.path]
        if isClip {
            let start = clipStart ?? 0
            let end = clipEnd.map { String(format: "%.2f", $0) } ?? "inf"
            args += ["--download-sections", String(format: "*%.2f-", start) + end,
                     "-o", "%(title).160B (\(Self.clock(start))–\(clipEnd.map(Self.clock) ?? "end")).%(ext)s"]
        } else {
            args += ["-o", "%(title).180B.%(ext)s"]
        }

        switch quality {
        case .audio:
            args += ["-f", "ba/b", "-x", "--audio-format", audioFormat.rawValue, "--audio-quality", "0"]
        default:
            // Video-only streams merged with the best audio; combined streams are only a fallback,
            // so old low-resolution combined formats never win.
            let cap = quality.maxHeight.map { "[height<=\($0)]" } ?? ""
            let softCap = quality.maxHeight.map { "[height<=?\($0)]" } ?? ""
            let wantsCompatible = compatible || Prefs.site(for: link) == .tiktok
            if wantsCompatible {
                // Ask for H.264 explicitly. Instagram only offers VP9 as separate video (QuickTime
                // can't play it) but has unlabelled H.264 progressive files, tried before VP9.
                args += ["-f", [
                    "bv\(cap)[vcodec^=avc]+ba",
                    "b\(cap)[vcodec^=avc]",
                    "b\(softCap)[vcodec!^=?vp][vcodec!^=?av01]",
                    "bv\(cap)+ba",
                    "b\(cap)",
                    "b",
                ].joined(separator: "/")]
            } else {
                args += ["-f", "bv\(cap)+ba/b\(cap)/b"]
            }
            if wantsCompatible {
                // H.264 + AAC plays everywhere on Apple devices. TikTok also offers ByteDance's
                // own codec, which nothing on a Mac can play, so it always gets this sort.
                args += ["-S", "vcodec:h264,res,acodec:m4a", "--merge-output-format", "mp4"]
            } else {
                args += ["--merge-output-format", "mp4/mkv"]
            }
        }
        if includeCookies { args += Prefs.cookieArguments(for: link) }
        return args
    }

    /// 95 → "1.35", 3725 → "1.02.05" (dots, since colons are awkward in file names).
    static func clock(_ seconds: Double) -> String {
        seconds.clockString.replacingOccurrences(of: ":", with: ".")
    }
}

enum DownloadKind { case video, gallery }

enum Prefs {
    enum Site { case youtube, instagram, tiktok, other }

    static var downloadFolder: URL {
        if let path = UserDefaults.standard.string(forKey: "downloadFolder"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    static var defaultQuality: Quality {
        Quality(rawValue: UserDefaults.standard.string(forKey: "defaultQuality") ?? "") ?? .best
    }

    /// Optional proxy for all downloads, e.g. "socks5://127.0.0.1:1080" (Settings › Downloads).
    static var proxyArguments: [String] {
        let proxy = (UserDefaults.standard.string(forKey: "proxy") ?? "").trimmingCharacters(in: .whitespaces)
        return proxy.isEmpty ? [] : ["--proxy", proxy]
    }

    /// "none" or a browser name yt-dlp and gallery-dl understand.
    static var cookieBrowser: String {
        UserDefaults.standard.string(forKey: "cookieBrowser") ?? "none"
    }

    static func site(for link: String) -> Site {
        guard let host = URL(string: link)?.host?.lowercased() else { return .other }
        if host.hasSuffix("instagram.com") { return .instagram }
        if host.hasSuffix("tiktok.com") { return .tiktok }
        if host.hasSuffix("youtube.com") || host == "youtu.be" { return .youtube }
        return .other
    }

    static func siteName(for link: String) -> String {
        switch site(for: link) {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .other: return URL(string: link)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Link"
        }
    }

    /// Sites the browser sign-in is used for, chosen in Settings › Accounts.
    static let signInSiteKeys: [(key: String, name: String)] = [
        ("instagram", "Instagram"), ("tiktok", "TikTok"), ("youtube", "YouTube"), ("other", "Other sites"),
    ]

    static var signInSites: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "signInSites") ?? ["instagram", "tiktok"])
    }

    static func siteKey(for link: String) -> String {
        switch site(for: link) {
        case .instagram: "instagram"
        case .tiktok: "tiktok"
        case .youtube: "youtube"
        case .other: "other"
        }
    }

    /// Browser sign-in is only borrowed for the sites you chose.
    static func cookieArguments(for link: String) -> [String] {
        let browser = cookieBrowser
        guard browser != "none", signInSites.contains(siteKey(for: link)) else { return [] }
        return ["--cookies-from-browser", browser]
    }

    /// Photo posts go to gallery-dl; everything else to yt-dlp.
    static func kind(for link: String) -> DownloadKind {
        guard let url = URL(string: link) else { return .video }
        let path = url.path.lowercased()
        switch site(for: link) {
        case .instagram where path.hasPrefix("/p/"): return .gallery
        case .tiktok where path.contains("/photo/"): return .gallery
        default: return .video
        }
    }
}

/// What yt-dlp reports about a link before downloading.
struct MediaInfo {
    struct Entry: Identifiable, Hashable {
        let id: String
        let title: String
        let url: String
        let duration: Double?
        let thumbnail: URL?
    }

    let link: String
    let title: String
    let uploader: String?
    let duration: Double?
    let thumbnail: URL?
    let entries: [Entry]
    let isLive: Bool

    var isPlaylist: Bool { !entries.isEmpty }

    init(json: [String: Any], link: String) {
        self.link = (json["webpage_url"] as? String) ?? link
        title = (json["title"] as? String) ?? "Untitled"
        uploader = (json["uploader"] as? String) ?? (json["channel"] as? String)
        duration = (json["duration"] as? NSNumber)?.doubleValue
        isLive = (json["is_live"] as? Bool) ?? false

        if (json["_type"] as? String) == "playlist", let raw = json["entries"] as? [[String: Any]] {
            entries = raw.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                let url = (item["url"] as? String) ?? (item["webpage_url"] as? String) ?? id
                return Entry(
                    id: id,
                    title: (item["title"] as? String) ?? "Untitled",
                    url: url,
                    duration: (item["duration"] as? NSNumber)?.doubleValue,
                    thumbnail: MediaInfo.thumbnail(in: item)
                )
            }
            thumbnail = MediaInfo.thumbnail(in: json) ?? entries.first?.thumbnail
        } else {
            entries = []
            thumbnail = MediaInfo.thumbnail(in: json)
        }
    }

    private static func thumbnail(in json: [String: Any]) -> URL? {
        if let s = json["thumbnail"] as? String { return URL(string: s) }
        if let list = json["thumbnails"] as? [[String: Any]], let s = list.last?["url"] as? String {
            return URL(string: s)
        }
        return nil
    }
}

extension Double {
    /// 75.0 → "1:15", 3725.0 → "1:02:05"
    var clockString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var byteString: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
