import AppKit
import Foundation
import Photos

/// Optional hand-offs after a download: photos and videos into Photos, audio into Music.
/// The downloaded files always stay in the downloads folder as well.
enum Integrations {
    enum PhotosMode: String, CaseIterable, Identifiable {
        case off, photos, photosAndVideos
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .photos: "Photos only"
            case .photosAndVideos: "Photos and videos"
            }
        }
    }

    static var photosMode: PhotosMode {
        PhotosMode(rawValue: UserDefaults.standard.string(forKey: "photosMode") ?? "") ?? .off
    }

    static var addAudioToMusic: Bool { UserDefaults.standard.bool(forKey: "addToMusic") }

    private static let photoTypes: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tiff"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v"]
    private static let audioTypes: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff"]

    /// Runs the hand-offs for a finished download; returns a note for the download's log.
    @MainActor
    static func handOff(_ files: [URL]) async -> [String] {
        var notes: [String] = []
        let mode = photosMode
        if mode != .off {
            let wanted = files.filter { file in
                let ext = file.pathExtension.lowercased()
                return photoTypes.contains(ext) || (mode == .photosAndVideos && videoTypes.contains(ext))
            }
            if !wanted.isEmpty {
                do {
                    try await addToPhotos(wanted)
                    notes.append("Added \(wanted.count) item(s) to Photos.")
                } catch {
                    notes.append("Couldn't add to Photos: \(error.localizedDescription)")
                }
            }
        }
        if addAudioToMusic {
            for file in files where audioTypes.contains(file.pathExtension.lowercased()) {
                notes.append(addToMusic(file) ? "Added to Music." : "Couldn't add to Music. Allow Reel to control Music in System Settings › Privacy & Security › Automation.")
            }
        }
        return notes
    }

    enum PhotosError: LocalizedError {
        case notAllowed
        var errorDescription: String? {
            "Reel isn't allowed to add to your Photos library. Turn it on in System Settings › Privacy & Security › Photos."
        }
    }

    static func addToPhotos(_ files: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotosError.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            for file in files {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = file.lastPathComponent
                let type: PHAssetResourceType = videoTypes.contains(file.pathExtension.lowercased()) ? .video : .photo
                request.addResource(with: type, fileURL: file, options: options)
            }
        }
    }

    /// Music has no public API on macOS; AppleScript is the supported way to add a file.
    @MainActor
    static func addToMusic(_ file: URL) -> Bool {
        let path = file.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Music\" to add (POSIX file \"\(path)\")"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
