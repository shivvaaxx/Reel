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

    var thumbnailURL: URL? { thumbnail.flatMap(URL.init(string:)) }
}

@MainActor @Observable
final class Subscriptions {
    private(set) var items: [Subscription] = []
    private(set) var checking: Set<UUID> = []
    private static let file = "subscriptions.json"
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private let queue: DownloadQueue

    /// How many of the newest entries are looked at each check.
    static let window = 30

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

    /// Subscribes; `downloadLatest` grabs the newest N right away, the rest are marked as seen.
    func add(link: String, quality: Quality, downloadLatest: Int) async throws {
        var candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        // A bare YouTube channel page lists tabs, not videos; point it at the uploads.
        if let url = URL(string: candidate), Prefs.site(for: candidate) == .youtube,
           url.path.hasPrefix("/@") || url.path.hasPrefix("/channel/") || url.path.hasPrefix("/c/"),
           url.pathComponents.count == 2 {
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/videos"
        }
        guard !items.contains(where: { $0.link == candidate }) else { throw AddError.alreadySubscribed }
        let info = try await engine.probe(candidate, latest: Self.window)
        guard info.isPlaylist else { throw AddError.notAList }

        var sub = Subscription(link: candidate, title: Self.cleanTitle(info.title), thumbnail: info.thumbnail?.absoluteString,
                               quality: quality.rawValue)
        sub.knownIDs = Set(info.entries.map(\.id))
        sub.lastChecked = Date()
        let latest = info.entries.prefix(max(downloadLatest, 0))
        for entry in latest.reversed() where queue.library.existing(for: entry.url) == nil {
            queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality)
            sub.downloadedCount += 1
        }
        items.insert(sub, at: 0)
        save()
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
            let info = try await engine.probe(sub.link, latest: Self.window)
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            let quality = Quality(rawValue: items[i].quality) ?? Prefs.defaultQuality
            let fresh = info.entries.filter { !items[i].knownIDs.contains($0.id) }
            for entry in fresh.reversed() where queue.library.existing(for: entry.url) == nil {
                queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality)
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
