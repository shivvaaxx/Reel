import Foundation

/// Re-encodes video QuickTime can't play (VP9, AV1) to HEVC using the Mac's hardware
/// encoder, keeping audio, artwork, chapters and details. Files that are already
/// H.264 or HEVC are left untouched.
final class HEVCConverter: @unchecked Sendable {
    struct Probe {
        let videoCodec: String?
        let audioCodec: String?
        let duration: Double?
    }

    private let ffmpeg: URL
    private let ffprobe: URL
    private let environment: [String: String]
    private var process: Process?
    private let lock = NSLock()
    private var cancelled = false

    init(ffmpeg: URL, ffprobe: URL, environment: [String: String]) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.environment = environment
    }

    static let playableCodecs: Set<String> = ["h264", "hevc"]

    func probe(_ file: URL) async -> Probe? {
        let args = ["-v", "error", "-show_entries", "stream=codec_type,codec_name,disposition=attached_pic:format=duration",
                    "-of", "json", file.path]
        guard let result = try? await Shell.run(ffprobe, args, environment: environment), result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else { return nil }
        let streams = json["streams"] as? [[String: Any]] ?? []
        let video = streams.first {
            ($0["codec_type"] as? String) == "video"
                && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0
        }
        let audio = streams.first { ($0["codec_type"] as? String) == "audio" }
        let duration = ((json["format"] as? [String: Any])?["duration"] as? String).flatMap(Double.init)
        return Probe(videoCodec: video?["codec_name"] as? String, audioCodec: audio?["codec_name"] as? String,
                     duration: duration)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        p?.terminate()
    }

    /// Converts via a temporary file and returns the converted file's location (always .mp4),
    /// or nil if the video was already playable.
    func convertIfNeeded(_ file: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL? {
        guard let info = await probe(file), let codec = info.videoCodec,
              !Self.playableCodecs.contains(codec) else { return nil }

        let temp = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.deletingPathExtension().lastPathComponent).hevc.mp4")
        try? FileManager.default.removeItem(at: temp)

        var args = ["-hide_banner", "-nostats", "-progress", "pipe:1", "-y", "-i", file.path,
                    "-map", "0", "-c", "copy",
                    // The main video stream only; cover art (an attached picture) stays as it is.
                    "-c:v:0", "hevc_videotoolbox", "-q:v:0", "62", "-tag:v:0", "hvc1"]
        if let audio = info.audioCodec, audio != "aac" {
            args += ["-c:a", "aac", "-b:a", "192k"]
        }
        args += ["-movflags", "+faststart", temp.path]

        let duration = info.duration ?? 0
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = ffmpeg
            process.arguments = args
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            let buffer = LineBuffer { line in
                guard duration > 0, line.hasPrefix("out_time_us="),
                      let micro = Double(line.dropFirst("out_time_us=".count)) else { return }
                onProgress(min(micro / 1_000_000 / duration, 1))
            }
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { buffer.append(data) }
            }
            process.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(returning: -1)
                return
            }
            self.process = process
            lock.unlock()
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }

        let wasCancelled = lock.withLock { cancelled }
        guard status == 0, !wasCancelled else {
            try? FileManager.default.removeItem(at: temp)
            if wasCancelled { throw CancellationError() }
            throw ConversionError.failed
        }
        let final = file.deletingPathExtension().appendingPathExtension("mp4")
        if final == file {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        } else {
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: temp, to: final)
            try? FileManager.default.removeItem(at: file)
        }
        return final
    }

    enum ConversionError: LocalizedError {
        case failed
        var errorDescription: String? { "Couldn't convert the video for QuickTime. The original download was kept." }
    }
}
