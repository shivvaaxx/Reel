import Foundation
import Testing
@testable import Reel

/// Runs against Reel's real FFmpeg; skipped on machines where Reel hasn't installed it yet.
@Suite("HEVC conversion")
struct ConverterTests {
    static let bin = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Reel/bin")
    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("ffmpeg").path)
    }

    private func makeVideo(codec: [String], audio: [String], ext: String) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("source.\(ext)")
        let args = ["-hide_banner", "-loglevel", "error",
                    "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30",
                    "-f", "lavfi", "-i", "sine", "-t", "2"] + codec + audio + [file.path, "-y"]
        let result = try await Shell.run(Self.bin.appendingPathComponent("ffmpeg"), args)
        #expect(result.status == 0, "\(result.stderr)")
        return file
    }

    private var converter: HEVCConverter {
        HEVCConverter(ffmpeg: Self.bin.appendingPathComponent("ffmpeg"),
                      ffprobe: Self.bin.appendingPathComponent("ffprobe"), environment: ProcessInfo.processInfo.environment)
    }

    @Test(.enabled(if: ConverterTests.available))
    func vp9BecomesHEVCWithAAC() async throws {
        let source = try await makeVideo(codec: ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-b:v", "1M"],
                                         audio: ["-c:a", "libopus"], ext: "webm")
        let output = try #require(try await converter.convertIfNeeded(source) { _ in })
        #expect(output.pathExtension == "mp4")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let probe = try #require(await converter.probe(output))
        #expect(probe.videoCodec == "hevc")
        #expect(probe.audioCodec == "aac")
        #expect((probe.duration ?? 0) > 1.5)
    }

    @Test(.enabled(if: ConverterTests.available))
    func h264IsLeftAlone() async throws {
        let source = try await makeVideo(codec: ["-c:v", "libx264", "-preset", "ultrafast"],
                                         audio: ["-c:a", "aac"], ext: "mp4")
        let output = try await converter.convertIfNeeded(source) { _ in }
        #expect(output == nil)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
