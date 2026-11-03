import AppKit
import Foundation
import Observation

/// Small JSON files in ~/Library/Application Support/Reel.
enum Persistence {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

/// One identity per piece of media, whatever form the link takes
/// (youtu.be, Shorts, extra tracking parameters, m. hosts…).
enum LinkKey {
    static func key(for link: String) -> String {
        guard let url = URL(string: link), var host = url.host?.lowercased() else { return link }
        for prefix in ["www.", "m.", "music.", "vm."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        let parts = url.path.split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if host == "youtu.be", let id = parts.first { return "youtube:\(id)" }
        if host.hasSuffix("youtube.com") {
            if let v = query.first(where: { $0.name == "v" })?.value { return "youtube:\(v)" }
            if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) { return "youtube:\(parts[1])" }
            if let list = query.first(where: { $0.name == "list" })?.value { return "youtube-list:\(list)" }
        }
        if host.hasSuffix("instagram.com"), parts.count >= 2, ["p", "reel", "reels", "tv"].contains(parts[0]) {
            return "instagram:\(parts[1])"
        }
        if host.hasSuffix("tiktok.com"), let index = parts.firstIndex(where: { $0 == "video" || $0 == "photo" }),
           index + 1 < parts.count {
            return "tiktok:\(parts[index + 1])"
        }
        return host + "/" + parts.joined(separator: "/")
    }
}

// MARK: - Library

struct LibraryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var key: String
    var link: String
    var title: String
    var site: String
    var thumbnail: String?
    var files: [String]
    var size: Double?
    var date: Date
    var isGallery: Bool
    var quality: String

    var fileURLs: [URL] { files.map { URL(fileURLWithPath: $0) } }
    var existingFiles: [URL] { fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) } }
    var isAvailable: Bool { !existingFiles.isEmpty }

    var thumbnailURL: URL? {
        guard let thumbnail else { return nil }
        return thumbnail.hasPrefix("/") ? URL(fileURLWithPath: thumbnail) : URL(string: thumbnail)
    }

    func open() {
        if let first = existingFiles.first { NSWorkspace.shared.open(first) }
    }

    func reveal() {
        let files = existingFiles
        if files.isEmpty { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }
}

/// Everything Reel has downloaded, kept even after the downloads list is cleared.
@MainActor @Observable
final class Library {
    private(set) var items: [LibraryItem] = []
    private static let file = "library.json"

    init() {
        items = Persistence.load([LibraryItem].self, from: Self.file) ?? []
    }

    func record(_ job: DownloadJob) {
        let files = job.kind == .gallery ? job.galleryFiles : [job.fileURL].compactMap { $0 }
        guard !files.isEmpty else { return }
        let key = LinkKey.key(for: job.link)
        items.removeAll { $0.key == key && !$0.isAvailable }
        items.insert(LibraryItem(
            id: job.id, key: key, link: job.link, title: job.title,
            site: Prefs.siteName(for: job.link),
            thumbnail: job.thumbnail.map { $0.isFileURL ? $0.path : $0.absoluteString },
            files: files.map(\.path), size: job.fileSize, date: Date(),
            isGallery: job.kind == .gallery, quality: job.options.quality.rawValue
        ), at: 0)
        save()
    }

    /// Adds a file found on disk (downloaded before, or by another app) unless the Library
    /// already has this video. Returns whether it was added.
    @discardableResult
    func importExisting(link: String, title: String, thumbnail: URL?, file: URL, quality: String) -> Bool {
        let key = LinkKey.key(for: link)
        if items.contains(where: { $0.key == key && $0.isAvailable }) { return false }
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        items.removeAll { $0.key == key && !$0.isAvailable }
        items.insert(LibraryItem(
            id: UUID(), key: key, link: link, title: title, site: Prefs.siteName(for: link),
            thumbnail: thumbnail?.absoluteString, files: [file.path], size: values?.fileSize.map(Double.init),
            date: values?.creationDate ?? Date(), isGallery: false, quality: quality
        ), at: 0)
        save()
        return true
    }

    /// A previous download of the same media whose files are still on disk.
    func existing(for link: String) -> LibraryItem? {
        let key = LinkKey.key(for: link)
        return items.first { $0.key == key && $0.isAvailable }
    }

    func remove(_ ids: Set<LibraryItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func removeMissing() {
        items.removeAll { !$0.isAvailable }
        save()
    }

    private func save() {
        Persistence.save(items, to: Self.file)
    }
}

// MARK: - Saved downloads list

/// The downloads list as saved between launches.
struct JobRecord: Codable {
    var id: UUID
    var link: String
    var isGallery: Bool
    var title: String
    var thumbnail: String?
    var quality: String
    var clipStart: Double?
    var clipEnd: Double?
    /// "queued", "paused", "finished", "failed", "cancelled" or "duplicate"
    var state: String
    var message: String?
    var file: String?
    var galleryFiles: [String]
    var fileSize: Double?
    var downloadedBytes: Double
    var expectedBytes: Double?
    var addedAt: Date
}
