import Foundation
import Observation

enum EngineError: LocalizedError {
    case badResponse(String)
    case unpackFailed(String)
    case missingBinary(String)
    case notReady
    case lookupFailed(String)
    case noVideo
    case galleryFailed(String)
    /// Blocked in this country; carries the readable message and where it is available.
    case geoBlocked(String, [String])

    var errorDescription: String? {
        switch self {
        case .badResponse(let name): "Couldn't download \(name). Check your connection and try again."
        case .unpackFailed(let name): "Couldn't unpack \(name)."
        case .missingBinary(let name): "\(name) wasn't found in the downloaded package."
        case .notReady: "Reel is still getting ready."
        case .lookupFailed(let message): message
        case .noVideo: "This post has no video."
        case .galleryFailed(let detail): "Couldn't set up photo downloads. \(detail)"
        case .geoBlocked(let message, _): message
        }
    }
}

/// The external tools Reel keeps its own private, up-to-date copies of.
enum Component: String, CaseIterable, Identifiable {
    // Order matters: uv must exist before the Python tools are installed with it.
    case uv, ffmpeg, ffprobe, deno, ytdlp, gallerydl

    enum Archive { case none, zip, tarGz }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ytdlp: "yt-dlp"
        case .ffmpeg: "FFmpeg"
        case .ffprobe: "FFprobe"
        case .deno: "Deno"
        case .uv: "uv"
        case .gallerydl: "gallery-dl"
        }
    }

    var role: String {
        switch self {
        case .ytdlp: "Finds and downloads videos"
        case .ffmpeg: "Merges and converts media"
        case .ffprobe: "Reads media details"
        case .deno: "Solves YouTube's playback checks"
        case .uv: "Keeps gallery-dl's Python private"
        case .gallerydl: "Saves Instagram and TikTok photos"
        }
    }

    var fileName: String {
        switch self {
        case .ytdlp: "yt-dlp"
        case .ffmpeg: "ffmpeg"
        case .ffprobe: "ffprobe"
        case .deno: "deno"
        case .uv: "uv"
        case .gallerydl: "gallery-dl"
        }
    }

    /// Where to download it from. yt-dlp and gallery-dl are installed by uv into Reel's
    /// private Python environment instead (it starts ~20× faster than the standalone build).
    var source: URL? {
        switch self {
        case .ytdlp: nil
        case .ffmpeg: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")
        case .ffprobe: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffprobe.zip")
        case .deno: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")
        case .uv: URL(string: "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz")
        case .gallerydl: nil
        }
    }

    var archive: Archive {
        switch self {
        case .ytdlp, .gallerydl: .none
        case .uv: .tarGz
        default: .zip
        }
    }

    /// Whether setup can show a percentage (gallery-dl's install is a single step).
    var reportsProgress: Bool { source != nil }

    /// Lives in the Python environment rather than Reel's bin folder.
    var isPython: Bool { self == .ytdlp || self == .gallerydl }
}

@MainActor @Observable
final class Engine {
    enum Phase: Equatable {
        case checking, installing, ready, failed(String)
    }

    var phase: Phase = .checking
    var installQueue: [Component] = []
    var currentComponent: Component?
    var componentProgress: Double = 0
    var installedThisRun: Set<Component> = []
    var versions: [Component: String] = [:]
    var isUpdating = false
    var updateMessage: String?

    let supportDir: URL
    let binDir: URL
    let galleryDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = support.appendingPathComponent("Reel", isDirectory: true)
        binDir = supportDir.appendingPathComponent("bin", isDirectory: true)
        galleryDir = supportDir.appendingPathComponent("gallery-dl", isDirectory: true)
    }

    func path(_ component: Component) -> URL {
        if component.isPython { return galleryDir.appendingPathComponent("bin/\(component.fileName)") }
        return binDir.appendingPathComponent(component.fileName)
    }

    var isReady: Bool { phase == .ready }

    var missing: [Component] {
        Component.allCases.filter { !FileManager.default.isExecutableFile(atPath: path($0).path) }
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = binDir.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    private var uvEnvironment: [String: String] {
        var env = environment
        env["UV_PYTHON_INSTALL_DIR"] = supportDir.appendingPathComponent("python").path
        env["UV_CACHE_DIR"] = supportDir.appendingPathComponent("uv-cache").path
        env["UV_PYTHON_PREFERENCE"] = "only-managed"
        env["UV_NO_CONFIG"] = "1"
        return env
    }

    /// Arguments every yt-dlp call gets, pointing it at Reel's own tools.
    var baseArguments: [String] {
        ["--ffmpeg-location", binDir.path,
         "--js-runtimes", "deno:" + path(.deno).path,
         "--no-update"] + Prefs.proxyArguments
    }

    // MARK: Setup

    func prepare() async {
        guard phase == .checking || phase.isFailure else { return }
        let needed = missing
        if needed.isEmpty {
            phase = .ready
            await refreshVersions()
            await updateIfDue()
        } else {
            await install(needed, blocking: true)
        }
    }

    /// Downloads and places components. When `blocking`, the app shows setup progress;
    /// otherwise it refreshes quietly in the background.
    func install(_ components: [Component], blocking: Bool) async {
        if blocking {
            phase = .installing
            installQueue = components
            installedThisRun = []
        }
        do {
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            for component in components {
                if blocking {
                    currentComponent = component
                    componentProgress = 0
                }
                if component.isPython {
                    // One step installs both; the gallery-dl step is skipped if yt-dlp's did it.
                    if component == .ytdlp || !FileManager.default.isExecutableFile(atPath: path(component).path) {
                        try await installGallery(fresh: !FileManager.default.isExecutableFile(atPath: galleryDir.appendingPathComponent("bin/python").path))
                    }
                } else if let source = component.source {
                    let file = try await Downloader.fetch(source) { [weak self] fraction in
                        Task { @MainActor in
                            guard let self, blocking else { return }
                            self.componentProgress = fraction
                        }
                    }
                    try await place(file, as: component)
                }
                if blocking { installedThisRun.insert(component) }
            }
            currentComponent = nil
            UserDefaults.standard.set(Date(), forKey: "lastComponentRefresh")
            UserDefaults.standard.set(Date(), forKey: "lastEngineUpdate")
            if blocking { phase = .ready }
            await refreshVersions()
        } catch {
            currentComponent = nil
            if blocking { phase = .failed(error.localizedDescription) }
            else { updateMessage = error.localizedDescription }
        }
    }

    private func place(_ file: URL, as component: Component) async throws {
        let fm = FileManager.default
        let destination = path(component)
        defer { try? fm.removeItem(at: file) }

        var binary = file
        var unpackDir: URL?
        if component.archive != .none {
            let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            unpackDir = dir
            let result: ShellResult
            if component.archive == .zip {
                result = try await Shell.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", file.path, dir.path])
            } else {
                result = try await Shell.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", file.path, "-C", dir.path])
            }
            guard result.status == 0 else { throw EngineError.unpackFailed(component.displayName) }
            let items = fm.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            guard let found = items.first(where: { $0.lastPathComponent == component.fileName }) else {
                throw EngineError.missingBinary(component.displayName)
            }
            binary = found
        }
        defer { if let unpackDir { try? fm.removeItem(at: unpackDir) } }

        // Swap in atomically so a running download never sees a half-written file.
        let staged = binDir.appendingPathComponent(".\(component.fileName).new")
        try? fm.removeItem(at: staged)
        try fm.moveItem(at: binary, to: staged)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        _ = try? await Shell.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-d", "com.apple.quarantine", staged.path])
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
    }

    /// Creates (or upgrades) gallery-dl in its own Python environment. yt-dlp is installed
    /// alongside it so gallery-dl can fetch Instagram videos at full quality.
    private func installGallery(fresh: Bool) async throws {
        let fm = FileManager.default
        let python = galleryDir.appendingPathComponent("bin/python")
        if fresh || !fm.isExecutableFile(atPath: python.path) {
            try? fm.removeItem(at: galleryDir)
            let venv = try await Shell.run(path(.uv), ["venv", galleryDir.path, "--python", "3.13"],
                                           environment: uvEnvironment)
            guard venv.status == 0 else { throw EngineError.galleryFailed(Engine.lastLine(venv.stderr)) }
        }
        let install = try await Shell.run(
            path(.uv),
            ["pip", "install", "--upgrade", "--python", python.path, "gallery-dl", "yt-dlp[default,curl-cffi]"],
            environment: uvEnvironment
        )
        guard install.status == 0 else { throw EngineError.galleryFailed(Engine.lastLine(install.stderr)) }
    }

    // MARK: Versions & updates

    func refreshVersions() async {
        var found: [Component: String] = [:]
        for component in Component.allCases {
            let args = (component == .ffmpeg || component == .ffprobe) ? ["-version"] : ["--version"]
            guard let result = try? await Shell.run(path(component), args, environment: environment),
                  result.status == 0 else { continue }
            let firstLine = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
            let words = firstLine.split(separator: " ").map(String.init)
            switch component {
            case .ytdlp, .gallerydl: found[component] = firstLine.trimmingCharacters(in: .whitespaces)
            case .deno, .uv: found[component] = words.count > 1 ? words[1] : firstLine
            case .ffmpeg, .ffprobe: found[component] = words.count > 2 ? words[2] : firstLine
            }
        }
        versions = found
    }

    var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
    }

    /// yt-dlp and gallery-dl are checked daily (sites change often); the rest monthly.
    func updateIfDue() async {
        guard autoUpdateEnabled else { return }
        let defaults = UserDefaults.standard
        let lastUpdate = defaults.object(forKey: "lastEngineUpdate") as? Date ?? .distantPast
        if Date().timeIntervalSince(lastUpdate) > 20 * 3600 {
            await updateTools()
        }
        let lastRefresh = defaults.object(forKey: "lastComponentRefresh") as? Date ?? .distantPast
        if Date().timeIntervalSince(lastRefresh) > 30 * 24 * 3600 {
            await install([.ffmpeg, .ffprobe, .deno, .uv], blocking: false)
        }
    }

    func updateTools() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        var notes: [String] = []
        do {
            // yt-dlp and gallery-dl are upgraded together in the Python environment.
            let before = versions
            try await installGallery(fresh: false)
            await refreshVersions()
            if let old = before[.ytdlp], versions[.ytdlp] != old { notes.append("yt-dlp updated to \(versions[.ytdlp] ?? "?")") }
            if let old = before[.gallerydl], versions[.gallerydl] != old { notes.append("gallery-dl updated to \(versions[.gallerydl] ?? "?")") }
            UserDefaults.standard.set(Date(), forKey: "lastEngineUpdate")
            updateMessage = notes.isEmpty ? "Everything is up to date." : notes.joined(separator: ", ") + "."
        } catch {
            updateMessage = error.localizedDescription
        }
    }

    func reinstallAll() async {
        await install(Component.allCases, blocking: true)
    }

    // MARK: Look up

    func probe(_ link: String) async throws -> MediaInfo {
        while phase == .installing || phase == .checking {
            try await Task.sleep(for: .milliseconds(300))
        }
        guard isReady else { throw EngineError.notReady }
        let result = try await Shell.run(
            path(.ytdlp),
            baseArguments + Prefs.cookieArguments(for: link) + ["-J", "--flat-playlist", "--no-warnings", "--", link],
            environment: environment
        )
        guard result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else {
            let lower = result.stderr.lowercased()
            if lower.contains("there is no video in this post") || lower.contains("no video formats found") {
                throw EngineError.noVideo
            }
            if let countries = Engine.geoRestriction(in: result.stderr) {
                throw EngineError.geoBlocked(Engine.readableError(result.stderr, fallback: ""), countries)
            }
            throw EngineError.lookupFailed(Engine.readableError(result.stderr, fallback: "Reel couldn't find a video at that link."))
        }
        return MediaInfo(json: json, link: link)
    }

    static func lastLine(_ text: String) -> String {
        text.split(separator: "\n").last.map(String.init) ?? ""
    }

    /// If the output reports a geo-block, the countries the video *is* available in
    /// (empty when the site doesn't say). nil when it isn't a geo-block.
    nonisolated static func geoRestriction(in output: String) -> [String]? {
        let lower = output.lowercased()
        guard lower.contains("geo restriction") || lower.contains("available in your country")
                || lower.contains("not available from your location") || lower.contains("in your region") else { return nil }
        let marker = "This video is available in "
        guard let line = output.split(separator: "\n").first(where: { $0.contains(marker) }),
              let range = line.range(of: marker) else { return [] }
        var list = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if list.hasSuffix(".") { list.removeLast() }
        return list.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The person's own country name, for "not available in Singapore".
    nonisolated static var currentCountryName: String? {
        guard let code = Locale.current.region?.identifier else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
    }

    /// Turns yt-dlp's or gallery-dl's last error line into something a person can read.
    nonisolated static func readableError(_ output: String, fallback: String) -> String {
        if let countries = geoRestriction(in: output) {
            let here = currentCountryName.map { "in \($0)" } ?? "in your country"
            guard !countries.isEmpty else {
                return "This video isn't available \(here). A VPN or a proxy (Settings › Downloads) may help."
            }
            let shown = countries.count <= 4 ? countries.joined(separator: ", ")
                : countries.prefix(3).joined(separator: ", ") + " and \(countries.count - 3) more"
            return "Not available \(here). It's available in \(shown)."
        }
        let lower = output.lowercased()
        if lower.contains("operation not permitted") && lower.contains("cookies") {
            return "Reel needs Full Disk Access to use Safari's sign-in. Turn it on in System Settings › Privacy & Security › Full Disk Access."
        }
        if lower.contains("login") || lower.contains("log in") || lower.contains("logged-in")
            || lower.contains("checkpoint") || lower.contains("rate-limit") || lower.contains("requested content is not available") {
            if Prefs.cookieBrowser == "none" {
                return "This site wants you to be signed in. In Reel's Settings › Accounts, choose the browser you use it in."
            }
            return "This site refused the request even with your browser's sign-in. Make sure you're signed in there, then try again."
        }
        guard let line = output.split(separator: "\n").last(where: {
            $0.hasPrefix("ERROR:") || $0.contains("][error]")
        }) else { return fallback }

        var message = String(line)
        if message.hasPrefix("ERROR:") { message = String(message.dropFirst("ERROR:".count)) }
        message = message.trimmingCharacters(in: .whitespaces)
        // Strip "[extractor] id:" or "[site][error]" prefixes.
        while message.hasPrefix("["), let close = message.firstIndex(of: "]") {
            message = String(message[message.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        if let colon = message.firstIndex(of: ":"), message.distance(from: message.startIndex, to: colon) < 24,
           !message[..<colon].contains(" ") {
            message = String(message[message.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if message.lowercased().contains("unsupported url") { return "That site or link isn't supported." }
        if message.lowercased().contains("private video") { return "This video is private." }
        if message.lowercased().contains("sign in to confirm") { return "YouTube wants a sign-in to confirm your age or that you're not a bot." }
        return message.isEmpty ? fallback : message
    }
}

extension Engine.Phase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}
