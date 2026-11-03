import Foundation

/// What Reel's accelerator will fetch for one download: the streams yt-dlp chose,
/// where yt-dlp expects to find them, and the info file yt-dlp resumes from.
struct AcceleratedPlan {
    let infoFile: URL
    /// The final file yt-dlp will produce (after merging).
    let finalPath: String
    var streams: [SegmentedDownloader.Stream]
    var totalBytes: Int64 { streams.reduce(0) { $0 + $1.size } }

    /// Asks yt-dlp to resolve the link without downloading. Returns nil when the
    /// download isn't suited to segmented fetching (streaming formats, cookies, etc.),
    /// in which case yt-dlp downloads it the normal way.
    @MainActor
    static func make(for job: DownloadJob, engine: Engine) async throws -> AcceleratedPlan? {
        let args = engine.baseArguments + ["--simulate", "--no-warnings",
                                           "--print", "@@FN %(filename)s", "--print", "@@J %()j"]
            + job.options.selectionArguments(for: job.link) + ["--", job.link]
        let result = try await Shell.run(engine.path(.ytdlp), args, environment: engine.environment)
        guard result.status == 0 else { return nil }

        let lines = result.stdout.split(separator: "\n")
        guard let fnLine = lines.first(where: { $0.hasPrefix("@@FN ") }),
              let jsonLine = lines.first(where: { $0.hasPrefix("@@J ") }) else { return nil }
        let finalPath = String(fnLine.dropFirst(5))
        let jsonText = String(jsonLine.dropFirst(4))
        guard let info = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
              (info["_type"] as? String) != "playlist" else { return nil }

        let formats = (info["requested_formats"] as? [[String: Any]]) ?? [info]
        let base = (finalPath as NSString).deletingPathExtension
        var streams: [SegmentedDownloader.Stream] = []
        for format in formats {
            let proto = (format["protocol"] as? String) ?? ""
            guard proto == "https" || proto == "http",
                  format["cookies"] == nil || (format["cookies"] as? String)?.isEmpty == true,
                  let urlString = format["url"] as? String, let url = URL(string: urlString),
                  let formatID = format["format_id"] as? String,
                  let ext = format["ext"] as? String else { return nil }
            let headers = (format["http_headers"] as? [String: String]) ?? [:]
            let size = (format["filesize"] as? NSNumber)?.int64Value ?? 0
            let path = formats.count > 1 ? "\(base).f\(formatID).\(ext)" : finalPath
            streams.append(.init(url: url, headers: headers, size: size, destination: URL(fileURLWithPath: path)))
        }

        // Fill in unknown sizes with a one-byte range request.
        for index in streams.indices where streams[index].size <= 0 {
            guard let size = await SegmentedDownloader.remoteSize(of: streams[index]) else { return nil }
            streams[index].size = size
        }
        guard !streams.isEmpty else { return nil }

        let dir = engine.supportDir.appendingPathComponent("plans", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let infoFile = dir.appendingPathComponent(job.id.uuidString + ".info.json")
        try Data(jsonText.utf8).write(to: infoFile)
        return AcceleratedPlan(infoFile: infoFile, finalPath: finalPath, streams: streams)
    }
}

/// Downloads files as many 8 MB segments over several connections at once, writing
/// each segment straight into place. Finished segments are recorded in a small ledger
/// beside the file, so a paused or interrupted download resumes where it stopped.
final class SegmentedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Stream {
        let url: URL
        let headers: [String: String]
        var size: Int64
        let destination: URL

        var partURL: URL { URL(fileURLWithPath: destination.path + ".reelpart") }
        var ledgerURL: URL { URL(fileURLWithPath: destination.path + ".reelpart.json") }
    }

    enum Failure: LocalizedError {
        case badStatus(Int), shortSegment, cancelled
        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "The server refused a segment (HTTP \(code))."
            case .shortSegment: "A segment arrived incomplete."
            case .cancelled: "Cancelled."
            }
        }
    }

    static let segmentSize: Int64 = 8 << 20

    private let streams: [Stream]
    private let connections: Int
    private let onProgress: @Sendable (_ downloaded: Int64, _ speed: Double) -> Void
    private var session: URLSession!

    private let lock = NSLock()
    private var states: [Int: SegmentState] = [:]
    private var downloaded: Int64 = 0
    private var isCancelled = false
    private var lastReport = Date.distantPast
    private var speedSamples: [(Date, Int64)] = []

    private struct SegmentState {
        let handle: FileHandle
        var offset: Int64
        let expected: Int64
        var received: Int64
        var failure: Error?
        let continuation: CheckedContinuation<Void, Error>
    }

    init(streams: [Stream], connections: Int,
         onProgress: @escaping @Sendable (Int64, Double) -> Void) {
        self.streams = streams
        self.connections = max(1, connections)
        self.onProgress = onProgress
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = self.connections
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        session.invalidateAndCancel()
    }

    func run() async throws {
        defer { session.finishTasksAndInvalidate() }
        for stream in streams {
            try await download(stream)
        }
    }

    // MARK: One stream

    private func download(_ stream: Stream) async throws {
        let fm = FileManager.default
        let segmentCount = Int((stream.size + Self.segmentSize - 1) / Self.segmentSize)

        // Already finished on an earlier run?
        if fm.fileExists(atPath: stream.destination.path),
           (try? stream.destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == stream.size {
            add(stream.size)
            return
        }

        var done = Set<Int>()
        if fm.fileExists(atPath: stream.partURL.path),
           let data = try? Data(contentsOf: stream.ledgerURL),
           let ledger = try? JSONDecoder().decode(Ledger.self, from: data), ledger.size == stream.size {
            done = Set(ledger.done)
        } else {
            try? fm.removeItem(at: stream.partURL)
            fm.createFile(atPath: stream.partURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: stream.partURL)
            try handle.truncate(atOffset: UInt64(stream.size))
            try handle.close()
        }
        for index in done { add(segmentLength(index, of: stream)) }

        let handle = try FileHandle(forWritingTo: stream.partURL)
        defer { try? handle.close() }

        let pending = Array((0..<segmentCount).filter { !done.contains($0) })
        let queue = SegmentQueue(pending)
        let ledgerLock = NSLock()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<min(connections, max(pending.count, 1)) where !pending.isEmpty {
                group.addTask {
                    while let index = queue.next() {
                        try await self.fetchWithRetry(index, of: stream, into: handle)
                        let snapshot = ledgerLock.withLock {
                            done.insert(index)
                            return Ledger(size: stream.size, done: Array(done))
                        }
                        try? JSONEncoder().encode(snapshot).write(to: stream.ledgerURL, options: .atomic)
                    }
                }
            }
            try await group.waitForAll()
        }

        try? handle.synchronize()
        try? fm.removeItem(at: stream.destination)
        try fm.moveItem(at: stream.partURL, to: stream.destination)
        try? fm.removeItem(at: stream.ledgerURL)
    }

    private func segmentLength(_ index: Int, of stream: Stream) -> Int64 {
        let start = Int64(index) * Self.segmentSize
        return min(Self.segmentSize, stream.size - start)
    }

    private func fetchWithRetry(_ index: Int, of stream: Stream, into handle: FileHandle) async throws {
        var attempt = 0
        while true {
            if cancelledNow() { throw Failure.cancelled }
            do {
                try await fetch(index, of: stream, into: handle)
                return
            } catch {
                if cancelledNow() { throw Failure.cancelled }
                attempt += 1
                if attempt > 4 { throw error }
                try await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
    }

    private func fetch(_ index: Int, of stream: Stream, into handle: FileHandle) async throws {
        let start = Int64(index) * Self.segmentSize
        let length = segmentLength(index, of: stream)
        var request = URLRequest(url: stream.url)
        for (key, value) in stream.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=\(start)-\(start + length - 1)", forHTTPHeaderField: "Range")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.dataTask(with: request)
            lock.lock()
            if isCancelled {
                lock.unlock()
                continuation.resume(throwing: Failure.cancelled)
                return
            }
            states[task.taskIdentifier] = SegmentState(handle: handle, offset: start, expected: length,
                                                       received: 0, failure: nil, continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }

    private func cancelledNow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }

    private func add(_ bytes: Int64) {
        lock.lock()
        downloaded += bytes
        lock.unlock()
    }

    // MARK: URLSession delegate (serial queue)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 206 || code == 200 {
            completionHandler(.allow)
        } else {
            lock.lock()
            states[dataTask.taskIdentifier]?.failure = Failure.badStatus(code)
            lock.unlock()
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var state = states[dataTask.taskIdentifier] else { lock.unlock(); return }
        let room = state.expected - state.received
        let chunk = data.count > room ? data.prefix(Int(room)) : data
        do {
            try state.handle.seek(toOffset: UInt64(state.offset))
            try state.handle.write(contentsOf: chunk)
        } catch {
            state.failure = error
        }
        state.offset += Int64(chunk.count)
        state.received += Int64(chunk.count)
        downloaded += Int64(chunk.count)
        states[dataTask.taskIdentifier] = state

        let now = Date()
        var report: (Int64, Double)?
        if now.timeIntervalSince(lastReport) > 0.25 {
            lastReport = now
            speedSamples.append((now, downloaded))
            speedSamples.removeAll { now.timeIntervalSince($0.0) > 3 }
            var speed = 0.0
            if let first = speedSamples.first, now.timeIntervalSince(first.0) > 0.2 {
                speed = Double(downloaded - first.1) / now.timeIntervalSince(first.0)
            }
            report = (downloaded, speed)
        }
        lock.unlock()
        if let report { onProgress(report.0, report.1) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let state = states.removeValue(forKey: task.taskIdentifier) else { lock.unlock(); return }
        let failure = state.failure ?? error ?? (state.received == state.expected ? nil : Failure.shortSegment)
        if failure != nil {
            downloaded -= state.received   // the segment will be fetched again in full
        }
        lock.unlock()
        if let failure {
            state.continuation.resume(throwing: failure)
        } else {
            state.continuation.resume()
        }
    }

    // MARK: Helpers

    private struct Ledger: Codable {
        let size: Int64
        let done: [Int]
    }

    private final class SegmentQueue: @unchecked Sendable {
        private var items: [Int]
        private let lock = NSLock()
        init(_ items: [Int]) { self.items = items.reversed() }
        func next() -> Int? {
            lock.lock(); defer { lock.unlock() }
            return items.popLast()
        }
    }

    static func remoteSize(of stream: Stream) async -> Int64? {
        var request = URLRequest(url: stream.url)
        for (key, value) in stream.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int64($0) }) else { return nil }
        return total
    }
}
