import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs a command to completion off the main thread and collects its output.
enum Shell {
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let environment { process.environment = environment }
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}

/// Splits a stream of bytes into lines (on \n or \r) and hands each one on.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func append(_ data: Data) {
        lock.lock()
        pending.append(data)
        var lines: [String] = []
        while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending[pending.startIndex..<index]
            pending.removeSubrange(pending.startIndex...index)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty { lines.append(line) }
        }
        lock.unlock()
        lines.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        lock.unlock()
        if !rest.isEmpty { onLine(rest) }
    }
}

/// Downloads a file with progress reporting.
enum Downloader {
    private final class ObservationBox: @unchecked Sendable {
        var observation: NSKeyValueObservation?
    }

    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let box = ObservationBox()
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                box.observation?.invalidate()
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tmp, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continuation.resume(throwing: EngineError.badResponse(url.lastPathComponent))
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            box.observation = task.progress.observe(\.fractionCompleted) { p, _ in
                progress(p.fractionCompleted)
            }
            task.resume()
        }
    }
}
