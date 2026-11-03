import Foundation
import Observation

/// A channel or playlist Reel checks for new uploads.
struct Subscription: Codable, Identifiable, Hashable {
    var id = UUID()
    var link: String
    var title: String
    var thumbnail: String?
    var quality: String
    var enabled = true
    /// IDs already seen, so only uploads after subscribing are downloaded.
    var knownIDs: Set<String> = []
    var lastChecked: Date?
    var lastError: String?
    var addedAt = Date()
    var downloadedCount = 0
    /// Where this subscription saves; nil = Reel's download folder. Reel checks this folder
    /// for videos already there (even ones moved in by hand) before downloading.
    var folder: String?

    var thumbnailURL: URL? { thumbnail.flatMap(URL.init(string:)) }
    var folderURL: URL? { folder.map { URL(fileURLWithPath: $0, isDirectory: true) } }
}

@MainActor @Observable
final class Subscriptions {
    private(set) var items: [Subscription] = []
    private(set) var checking: Set<UUID> = []
    private static let file = "subscriptions.json"
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private let queue: DownloadQueue

    /// How many of the newest entries are looked at each check of a channel.
    static let window = 30

    /// `downloadLatest` value meaning "everything already in the playlist".
    static let everything = Int.max

    /// Where subscriptions save unless they have their own folder (unset = Reel's download folder).
    static let defaultFolderKey = "subscriptionDefaultFolder"

    static var defaultFolder: URL {
        guard let path = UserDefaults.standard.string(forKey: defaultFolderKey), !path.isEmpty else {
            return Prefs.downloadFolder
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The folder a subscription actually saves to: its own, or the default.
    static func folder(for sub: Subscription) -> URL { sub.folderURL ?? defaultFolder }

    /// Channels list newest first, so their newest uploads are enough. Playlists usually add
    /// videos at the end, so they're read in full (flat listings are quick).
    static func lookupWindow(for link: String) -> Int? {
        guard let url = URL(string: link), Prefs.site(for: link) == .youtube else { return window }
        let path = url.path
        let isChannel = ["/@", "/channel/", "/c/", "/user/"].contains { path.hasPrefix($0) }
        return isChannel ? window : nil
    }

    static var intervalHours: Double {
        let value = UserDefaults.standard.double(forKey: "subscriptionHours")
        return value > 0 ? value : 6
    }

    init(engine: Engine, queue: DownloadQueue) {
        self.engine = engine
        self.queue = queue
        items = Persistence.load([Subscription].self, from: Self.file) ?? []
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDue() }
        }
    }

    private func save() { Persistence.save(items, to: Self.file) }

    // MARK: Managing

    enum AddError: LocalizedError {
        case notAList, alreadySubscribed
        var errorDescription: String? {
            switch self {
            case .notAList: "That link is a single video. Subscribe to a channel or playlist instead."
            case .alreadySubscribed: "You're already subscribed to this."
            }
        }
    }

    /// Reads a subscription's folder and returns the link keys of what's there. Files that
    /// match one of its videos, by source link, video ID or title, are tagged with that video
    /// and added to the Library, so earlier downloads (from Reel or other apps) show up there.
    @discardableResult
    private func syncFolder(for sub: Subscription, entries: [MediaInfo.Entry]) async -> Set<String> {
        let folder = Self.folder(for: sub)
        let ffprobe = engine.path(.ffprobe)
        let environment = engine.environment
        let found = await Task.detached(priority: .utility) {
            await FolderIndex.scan(folder, ffprobe: FileManager.default.isExecutableFile(atPath: ffprobe.path) ? ffprobe : nil,
                                   environment: environment)
        }.value

        var keys = Set(found.compactMap(\.key))
        var byKey: [String: URL] = [:]
        var byTitle: [String: URL] = [:]
        for item in found {
            if let key = item.key {
                byKey[key] = byKey[key] ?? item.file
            } else {
                let title = FolderIndex.titleKey(item.name)
                if !title.isEmpty { byTitle[title] = byTitle[title] ?? item.file }
            }
        }
        let quality = Quality(rawValue: sub.quality) ?? Prefs.defaultQuality
        for entry in entries {
            let key = LinkKey.key(for: entry.url)
            var file = byKey[key]
            if file == nil, let match = byTitle[FolderIndex.titleKey(entry.title)] {
                SourceTag.stamp(match, link: entry.url)   // recognised instantly next time
                byTitle[FolderIndex.titleKey(entry.title)] = nil
                keys.insert(key)
                file = match
            }
            if let file {
                queue.library.importExisting(link: entry.url, title: entry.title, thumbnail: entry.thumbnail,
                                             file: file, quality: quality.rawValue)
            }
        }
        return keys
    }

    /// Re-reads a subscription's folder now (after its folder changes, for example).
    func refreshFolder(_ id: UUID) async {
        guard engine.isReady, !checking.contains(id), let sub = items.first(where: { $0.id == id }) else { return }
        checking.insert(id)
        defer { checking.remove(id) }
        guard let info = try? await engine.probe(sub.link, latest: Self.lookupWindow(for: sub.link)) else { return }
        await syncFolder(for: sub, entries: info.entries)
    }

    /// Whether an entry is already downloaded or on its way. With its own folder, the folder
    /// decides (so moving files in counts, and moving them out means "download again");
    /// otherwise Reel's library does.
    private func alreadyHave(_ entry: MediaInfo.Entry, in sub: Subscription, folderKeys: Set<String>) -> Bool {
        if queue.isQueued(entry.url) { return true }
        if folderKeys.contains(LinkKey.key(for: entry.url)) { return true }
        guard let existing = queue.library.existing(for: entry.url) else { return false }
        // On the default folder, a copy anywhere counts. With its own folder, only a copy in it does.
        guard sub.folder != nil else { return true }
        let inside = Self.folder(for: sub).standardizedFileURL.path + "/"
        return existing.existingFiles.contains { $0.standardizedFileURL.path.hasPrefix(inside) }
    }

    /// Subscribes; `downloadLatest` grabs the newest N right away, the rest are marked as seen.
    func add(link: String, quality: Quality, downloadLatest: Int, folder: URL? = nil) async throws {
        var candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        // A bare YouTube channel page lists tabs, not videos; point it at the uploads.
        if let url = URL(string: candidate), Prefs.site(for: candidate) == .youtube,
           url.path.hasPrefix("/@") || url.path.hasPrefix("/channel/") || url.path.hasPrefix("/c/"),
           url.pathComponents.count == 2 {
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/videos"
        }
        guard !items.contains(where: { $0.link == candidate }) else { throw AddError.alreadySubscribed }
        let info = try await engine.probe(candidate, latest: downloadLatest == Self.everything ? nil : Self.lookupWindow(for: candidate))
        guard info.isPlaylist else { throw AddError.notAList }

        var sub = Subscription(link: candidate, title: Self.cleanTitle(info.title), thumbnail: info.thumbnail?.absoluteString,
                               quality: quality.rawValue)
        sub.folder = folder?.path
        sub.knownIDs = Set(info.entries.map(\.id))
        sub.lastChecked = Date()
        let latest = info.entries.prefix(max(downloadLatest, 0))
        let onDisk = await syncFolder(for: sub, entries: info.entries)
        for entry in latest.reversed() where !alreadyHave(entry, in: sub, folderKeys: onDisk) {
            queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality,
                          folder: Self.folder(for: sub))
            sub.downloadedCount += 1
        }
        items.insert(sub, at: 0)
        save()
    }

    /// Queues the videos that were already there when subscribing (and anything else
    /// not downloaded yet). Returns how many were queued.
    @discardableResult
    func downloadExisting(_ id: UUID) async throws -> Int {
        guard let sub = items.first(where: { $0.id == id }) else { return 0 }
        checking.insert(id)
        defer { checking.remove(id) }
        let info = try await engine.probe(sub.link)
        let onDisk = await syncFolder(for: sub, entries: info.entries)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return 0 }
        let quality = Quality(rawValue: items[i].quality) ?? Prefs.defaultQuality
        var queued = 0
        for entry in info.entries.reversed() where !alreadyHave(entry, in: items[i], folderKeys: onDisk) {
            queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality,
                          folder: Self.folder(for: items[i]))
            queued += 1
        }
        items[i].downloadedCount += queued
        items[i].knownIDs.formUnion(info.entries.map(\.id))
        save()
        return queued
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = enabled
        save()
    }

    /// nil goes back to Reel's download folder.
    func setFolder(_ id: UUID, _ folder: URL?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].folder = folder?.path
        save()
        Task { await refreshFolder(id) }
    }

    func setQuality(_ id: UUID, _ quality: Quality) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].quality = quality.rawValue
        save()
    }

    /// "NASA - Videos" → "NASA"
    static func cleanTitle(_ title: String) -> String {
        for suffix in [" - Videos", " - Shorts", " - Live", " - Uploads"] where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }

    // MARK: Checking

    func checkDue() {
        let interval = Self.intervalHours * 3600
        for sub in items where sub.enabled {
            if Date().timeIntervalSince(sub.lastChecked ?? .distantPast) >= interval {
                Task { await check(sub.id) }
            }
        }
    }

    func checkAll() {
        for sub in items where sub.enabled { Task { await check(sub.id) } }
    }

    /// Looks for uploads not seen before and queues them.
    func check(_ id: UUID) async {
        guard engine.isReady, !checking.contains(id), let sub = items.first(where: { $0.id == id }) else { return }
        checking.insert(id)
        defer { checking.remove(id) }
        do {
            let info = try await engine.probe(sub.link, latest: Self.lookupWindow(for: sub.link))
            // Every check also reads the folder, so videos moved in by hand reach the Library.
            let onDisk = await syncFolder(for: sub, entries: info.entries)
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            let quality = Quality(rawValue: items[i].quality) ?? Prefs.defaultQuality
            let fresh = info.entries.filter { !items[i].knownIDs.contains($0.id) }
            for entry in fresh.reversed() where !alreadyHave(entry, in: items[i], folderKeys: onDisk) {
                queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality,
                              folder: Self.folder(for: items[i]))
                items[i].downloadedCount += 1
            }
            items[i].knownIDs.formUnion(info.entries.map(\.id))
            items[i].lastChecked = Date()
            items[i].lastError = nil
            if info.title != "Untitled" { items[i].title = Self.cleanTitle(info.title) }
            save()
        } catch {
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            items[i].lastChecked = Date()
            items[i].lastError = error.localizedDescription
            save()
        }
    }
}
