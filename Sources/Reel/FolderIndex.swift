import Darwin
import Foundation

/// Remembers where a file came from, in extended attributes that travel with the file
/// when it's moved or renamed in Finder (the same "Where from" Safari downloads show).
enum SourceTag {
    static let referrer = "user.xdg.referrer.url"
    static let whereFroms = "com.apple.metadata:kMDItemWhereFroms"

    static func stamp(_ file: URL, link: String) {
        file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let plain = Array(link.utf8)
            _ = setxattr(path, referrer, plain, plain.count, 0, 0)
            if let plist = try? PropertyListSerialization.data(fromPropertyList: [link], format: .binary, options: 0) {
                _ = plist.withUnsafeBytes { setxattr(path, whereFroms, $0.baseAddress, plist.count, 0, 0) }
            }
        }
    }

    /// The page this file was downloaded from, if it was stamped.
    static func read(_ file: URL) -> String? {
        if let data = attribute(referrer, of: file), let text = String(data: data, encoding: .utf8),
           text.hasPrefix("http") {
            return text
        }
        if let data = attribute(whereFroms, of: file),
           let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
            return list.first { $0.hasPrefix("http") }
        }
        return nil
    }

    private static func attribute(_ name: String, of file: URL) -> Data? {
        file.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read == size ? data : nil
        }
    }
}

/// Works out which media a folder already holds, so a subscription only downloads
/// what's missing, even after files were moved there by hand.
enum FolderIndex {
    static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "m4a", "mp3", "opus", "aac", "flac", "wav",
        "jpg", "jpeg", "png", "webp", "heic", "gif",
    ]

    /// Link keys (see `LinkKey`) of everything in `folder` and its subfolders. Each file is
    /// identified by, in order: its "Where from" stamp, the source link yt-dlp embeds in
    /// its metadata (read with ffprobe), or a YouTube ID in its name ("Title [dQw4w9WgXcQ].mp4").
    static func keys(in folder: URL, ffprobe: URL?, environment: [String: String]?) async -> Set<String> {
        let files = mediaFiles(in: folder)
        var keys = Set<String>()
        for file in files {
            if let link = SourceTag.read(file) {
                keys.insert(LinkKey.key(for: link))
            } else if let ffprobe, !isCloudOnly(file), await !ProbeMemory.shared.knownUnlinked(file),
                      let link = await embeddedLink(of: file, ffprobe: ffprobe, environment: environment) {
                keys.insert(LinkKey.key(for: link))
                SourceTag.stamp(file, link: link)   // faster next time
            } else if let id = youTubeID(inName: URL(fileURLWithPath: placeholderName(file.lastPathComponent)
                                                    ?? file.lastPathComponent).deletingPathExtension().lastPathComponent) {
                keys.insert("youtube:\(id)")
            }
        }
        return keys
    }

    static func mediaFiles(in folder: URL) -> [URL] {
        // Hidden files are included only to catch older iCloud placeholders (".Name.mp4.icloud").
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                if url.hasDirectoryPath { walker.skipDescendants(); continue }
                guard let original = placeholderName(name),
                      mediaExtensions.contains((original as NSString).pathExtension.lowercased()) else { continue }
                files.append(url)
            } else if mediaExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    /// ".Episode 1 [abc].mp4.icloud" → "Episode 1 [abc].mp4"
    nonisolated static func placeholderName(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// In iCloud Drive (or another cloud folder) with only a placeholder on this Mac. Reading
    /// such a file would download it, so only its name and "Where from" stamp are used.
    static func isCloudOnly(_ file: URL) -> Bool {
        if placeholderName(file.lastPathComponent) != nil { return true }
        guard let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus else { return false }
        return status != .current
    }

    /// yt-dlp's --embed-metadata stores the page address in the `purl`/`comment` tags.
    private static func embeddedLink(of file: URL, ffprobe: URL, environment: [String: String]?) async -> String? {
        guard let result = try? await Shell.run(ffprobe, [
            "-v", "quiet", "-show_entries", "format_tags=purl,comment", "-of", "default=nw=1:nk=1", file.path,
        ], environment: environment), result.status == 0 else { return nil }
        let link = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
            .first { $0.hasPrefix("http") }
        if link == nil { await ProbeMemory.shared.rememberUnlinked(file) }
        return link
    }
}

/// Files already opened and found to carry no source link (videos from elsewhere), so later
/// checks of a busy folder like Downloads don't open them again. Forgotten if a file changes.
actor ProbeMemory {
    static let shared = ProbeMemory()
    private var unlinked: [String: Date] = [:]

    private static func modified(_ file: URL) -> Date? {
        try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func knownUnlinked(_ file: URL) -> Bool {
        guard let seen = unlinked[file.path] else { return false }
        return seen == Self.modified(file)
    }

    func rememberUnlinked(_ file: URL) {
        unlinked[file.path] = Self.modified(file) ?? .distantPast
    }
}

extension FolderIndex {

    /// "Some Title [dQw4w9WgXcQ]" → "dQw4w9WgXcQ"
    nonisolated static func youTubeID(inName name: String) -> String? {
        guard let open = name.lastIndex(of: "["), name.hasSuffix("]") else { return nil }
        let id = name[name.index(after: open)..<name.index(before: name.endIndex)]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard id.count == 11, id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return String(id)
    }
}
