import AppKit
import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class DownloadJob: Identifiable {
    enum Status: Equatable {
        case resolving, queued, starting, downloading, processing(String), paused, finished, failed(String), cancelled
    }

    let id = UUID()
    let link: String
    var kind: DownloadKind
    var title: String
    var thumbnail: URL?
    let options: DownloadOptions

    var status: Status = .queued
    var fraction: Double?
    var downloadedBytes: Double = 0
    var expectedBytes: Double?
    var speed: Double?
    var eta: Double?
    var fileURL: URL?
    var fileSize: Double?
    var galleryFiles: [URL] = []
    var log: [String] = []

    /// Connections in use while the accelerator is fetching (nil otherwise).
    var activeConnections: Int?

    @ObservationIgnored var process: Process?
    @ObservationIgnored var accelerator: SegmentedDownloader?
    @ObservationIgnored var acceleratorTask: Task<Void, Never>?
    @ObservationIgnored var plan: AcceleratedPlan?
    @ObservationIgnored var completedStreamBytes: Double = 0
    @ObservationIgnored var currentFormat: String?
    @ObservationIgnored var currentStreamTotal: Double = 0
    @ObservationIgnored var plannedFilename: String?
    @ObservationIgnored var lastError: String?
    @ObservationIgnored var stopReason: StopReason?

    enum StopReason { case pause, cancel }

    init(link: String, kind: DownloadKind, title: String, thumbnail: URL?, options: DownloadOptions) {
        self.link = link
        self.kind = kind
        self.title = title
        self.thumbnail = thumbnail
        self.options = options
    }

    var isRunning: Bool {
        switch status {
        case .starting, .downloading, .processing: true
        default: false
        }
    }

    var isFinishedOrStopped: Bool {
        switch status {
        case .finished, .failed, .cancelled: true
        default: false
        }
    }

    var canPause: Bool { kind == .video && (status == .starting || status == .downloading) }

    func resetProgressForFallback() {
        fraction = nil
        downloadedBytes = 0
        speed = nil
        eta = nil
        completedStreamBytes = 0
        currentFormat = nil
        currentStreamTotal = 0
    }

    func resetProgress() {
        fraction = nil
        downloadedBytes = 0
        expectedBytes = nil
        speed = nil
        eta = nil
        galleryFiles = []
        completedStreamBytes = 0
        currentFormat = nil
        currentStreamTotal = 0
        lastError = nil
        stopReason = nil
    }
}

// MARK: - Status presentation shared by the window and the menu bar panel

extension DownloadJob {
    var showsProgressBar: Bool {
        switch status {
        case .resolving, .starting, .downloading, .processing, .paused: true
        default: false
        }
    }

    /// nil means indeterminate.
    var barValue: Double? {
        if case .processing = status { return nil }
        return kind == .gallery ? nil : fraction
    }

    var isFailed: Bool { if case .failed = status { true } else { false } }

    var statusLine: String {
        switch status {
        case .resolving:
            return "Looking up…"
        case .queued:
            return "Waiting…"
        case .starting:
            return downloadedBytes > 0 ? "Resuming…" : "Starting…"
        case .downloading:
            if kind == .gallery {
                let n = galleryFiles.count
                return n == 0 ? "Saving…" : "Saving… \(n) \(n == 1 ? "item" : "items") so far"
            }
            var parts: [String] = []
            if let expected = expectedBytes, expected > 0 {
                parts.append("\(downloadedBytes.byteString) of \(expected.byteString)")
            } else {
                parts.append(downloadedBytes.byteString)
            }
            if let speed, speed > 0 { parts.append("\(speed.byteString)/s") }
            if let eta, eta > 0 { parts.append(Self.timeLeft(eta)) }
            if let connections = activeConnections, connections > 1 { parts.append("\(connections) connections") }
            return parts.joined(separator: " · ")
        case .processing(let step):
            return step
        case .paused:
            return downloadedBytes > 0 ? "Paused · \(downloadedBytes.byteString)" : "Paused"
        case .finished:
            if kind == .gallery {
                let photos = galleryFiles.filter(Self.isImage).count
                let videos = galleryFiles.count - photos
                var parts: [String] = []
                if photos > 0 { parts.append("\(photos) \(photos == 1 ? "photo" : "photos")") }
                if videos > 0 { parts.append("\(videos) \(videos == 1 ? "video" : "videos")") }
                if let size = fileSize { parts.append(size.byteString) }
                parts.append(Prefs.siteName(for: link))
                return parts.joined(separator: " · ")
            }
            var parts: [String] = []
            if let size = fileSize { parts.append(size.byteString) }
            if let ext = fileURL?.pathExtension, !ext.isEmpty { parts.append(ext.uppercased()) }
            parts.append(options.quality == .audio ? "Audio" : options.quality.label)
            return parts.joined(separator: " · ")
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    static func timeLeft(_ seconds: Double) -> String {
        let text = Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return "\(text) left"
    }

    static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp", "heic", "gif", "avif"].contains(url.pathExtension.lowercased())
    }

    func open() {
        guard status == .finished else { return }
        if let first = galleryFiles.first ?? fileURL { NSWorkspace.shared.open(first) }
    }

    func reveal() {
        if !galleryFiles.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(galleryFiles)
        } else if let url = fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(options.folder)
        }
    }
}

// MARK: - Queue

@MainActor @Observable
final class DownloadQueue {
    var jobs: [DownloadJob] = []
    let engine: Engine

    init(engine: Engine) {
        self.engine = engine
    }

    var maxConcurrent: Int {
        let value = UserDefaults.standard.integer(forKey: "maxConcurrent")
        return value > 0 ? value : 3
    }

    var runningCount: Int { jobs.filter(\.isRunning).count }
    var activeCount: Int { jobs.filter { $0.isRunning || $0.status == .queued || $0.status == .resolving }.count }
    var hasClearable: Bool { jobs.contains(where: \.isFinishedOrStopped) }

    /// Overall progress of running video downloads, for the menu bar icon.
    var overallFraction: Double? {
        let fractions = jobs.filter(\.isRunning).compactMap(\.barValue)
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    // MARK: Queueing

    func enqueue(link: String, title: String, thumbnail: URL?, quality: Quality, kind: DownloadKind = .video) {
        let job = DownloadJob(link: link, kind: kind, title: title, thumbnail: thumbnail,
                              options: .current(quality: quality))
        jobs.insert(job, at: 0)
        Notifier.requestAuthorization()
        pump()
    }

    /// Adds a link with default settings and no preview: used by the menu bar and drops.
    /// Playlists expand into their videos; photo posts go to gallery-dl.
    func quickAdd(_ link: String) {
        let quality = Prefs.defaultQuality
        let placeholder = DownloadJob(link: link, kind: Prefs.kind(for: link),
                                      title: Prefs.siteName(for: link) + " link", thumbnail: nil,
                                      options: .current(quality: quality))
        Notifier.requestAuthorization()

        if placeholder.kind == .gallery {
            placeholder.title = "\(Prefs.siteName(for: link)) post"
            jobs.insert(placeholder, at: 0)
            pump()
            return
        }

        placeholder.status = .resolving
        jobs.insert(placeholder, at: 0)
        updateBadge()
        Task {
            do {
                let info = try await engine.probe(link)
                if info.isPlaylist {
                    jobs.removeAll { $0.id == placeholder.id }
                    for entry in info.entries {
                        enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality)
                    }
                } else {
                    placeholder.title = info.title
                    placeholder.thumbnail = info.thumbnail
                    placeholder.status = .queued
                    pump()
                }
            } catch EngineError.noVideo {
                placeholder.kind = .gallery
                placeholder.title = "\(Prefs.siteName(for: link)) post"
                placeholder.status = .queued
                pump()
            } catch {
                placeholder.status = .failed(error.localizedDescription)
                updateBadge()
            }
        }
    }

    func pump() {
        guard engine.isReady else { return }
        while runningCount < maxConcurrent,
              let next = jobs.last(where: { $0.status == .queued }) {
            start(next)
        }
        updateBadge()
    }

    // MARK: Controls

    func pause(_ job: DownloadJob) {
        guard job.canPause else { return }
        job.stopReason = .pause
        stop(job)
    }

    func resume(_ job: DownloadJob) {
        guard job.status == .paused else { return }
        job.status = .queued
        pump()
    }

    func cancel(_ job: DownloadJob) {
        if job.isRunning {
            job.stopReason = .cancel
            stop(job)
        } else if job.status == .queued || job.status == .paused || job.status == .resolving {
            job.status = .cancelled
            removePartialFiles(of: job)
            updateBadge()
        }
    }

    func retry(_ job: DownloadJob) {
        job.resetProgress()
        job.status = .queued
        pump()
    }

    func remove(_ job: DownloadJob) {
        if job.isRunning { cancel(job) }
        jobs.removeAll { $0.id == job.id }
        updateBadge()
    }

    func clearFinished() {
        jobs.removeAll(where: \.isFinishedOrStopped)
    }

    func stopAll() {
        for job in jobs where job.isRunning {
            job.stopReason = .cancel
            job.process?.interrupt()
        }
    }

    // MARK: Running the tools

    private func start(_ job: DownloadJob) {
        job.status = .starting
        job.lastError = nil
        job.stopReason = nil
        job.log.removeAll()
        // Resumed jobs pick up from their .part files; byte counters restart.
        job.completedStreamBytes = 0
        job.currentFormat = nil
        job.galleryFiles = []

        job.activeConnections = nil

        try? FileManager.default.createDirectory(at: job.options.folder, withIntermediateDirectories: true)

        if job.kind == .video && job.options.connections > 1 {
            job.acceleratorTask = Task { await self.runAccelerated(job) }
        } else {
            launchProcess(job, infoFile: nil)
        }
    }

    /// Fetches the streams with many connections, then lets yt-dlp merge and tag them.
    /// Anything the accelerator can't handle falls back to a normal yt-dlp download.
    private func runAccelerated(_ job: DownloadJob) async {
        do {
            guard let plan = try await AcceleratedPlan.make(for: job, engine: engine) else {
                if job.stopReason != nil { finish(job, exitStatus: 0) } else { launchProcess(job, infoFile: nil) }
                return
            }
            job.plan = plan
            job.plannedFilename = plan.finalPath   // used to clean up if cancelled
            if job.stopReason != nil { finish(job, exitStatus: 0); return }

            let total = Double(plan.totalBytes)
            job.expectedBytes = total
            job.status = .downloading
            job.activeConnections = job.options.connections
            let downloader = SegmentedDownloader(streams: plan.streams, connections: job.options.connections) {
                [weak job] downloaded, speed in
                Task { @MainActor in
                    guard let job, job.status == .downloading else { return }
                    job.downloadedBytes = Double(downloaded)
                    job.fraction = total > 0 ? min(Double(downloaded) / total, 0.99) : nil
                    job.speed = speed > 0 ? speed : nil
                    job.eta = speed > 0 ? max(total - Double(downloaded), 0) / speed : nil
                }
            }
            job.accelerator = downloader
            try await downloader.run()
            job.accelerator = nil
            job.activeConnections = nil
            if job.stopReason != nil { finish(job, exitStatus: 0); return }

            job.log.append("Reel fetched \(plan.streams.count) stream(s) over \(job.options.connections) connections.")
            job.downloadedBytes = total
            job.fraction = 0.99
            job.status = .processing("Finishing…")
            launchProcess(job, infoFile: plan.infoFile)
        } catch {
            job.accelerator = nil
            job.activeConnections = nil
            if job.stopReason != nil {
                finish(job, exitStatus: 0)
            } else {
                // Segmented fetching failed (e.g. the server refused ranges): use yt-dlp directly.
                job.log.append("Accelerator unavailable (\(error.localizedDescription)); using a single connection.")
                job.resetProgressForFallback()
                launchProcess(job, infoFile: nil)
            }
        }
    }

    private func launchProcess(_ job: DownloadJob, infoFile: URL?) {
        let process = Process()
        switch job.kind {
        case .video:
            process.executableURL = engine.path(.ytdlp)
            process.arguments = engine.baseArguments + job.options.videoArguments(for: job.link, infoFile: infoFile)
        case .gallery:
            process.executableURL = engine.path(.gallerydl)
            process.arguments = job.options.galleryArguments(for: job.link)
        }
        process.environment = engine.environment
        process.currentDirectoryURL = job.options.folder

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let handle: (String) -> Void = { [weak self, weak job] line in
            Task { @MainActor in
                guard let self, let job else { return }
                self.handle(line, for: job)
            }
        }
        let outBuffer = LineBuffer(onLine: handle)
        let errBuffer = LineBuffer(onLine: handle)

        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil } else { outBuffer.append(data) }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil } else { errBuffer.append(data) }
        }

        process.terminationHandler = { [weak self, weak job] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            outBuffer.append(out.fileHandleForReading.readDataToEndOfFile())
            errBuffer.append(err.fileHandleForReading.readDataToEndOfFile())
            outBuffer.flush()
            errBuffer.flush()
            let status = proc.terminationStatus
            Task { @MainActor in
                guard let self, let job else { return }
                self.finish(job, exitStatus: status)
            }
        }

        do {
            try process.run()
            job.process = process
        } catch {
            job.status = .failed("Couldn't start the downloader: \(error.localizedDescription)")
        }
    }

    private func stop(_ job: DownloadJob) {
        if let accelerator = job.accelerator {
            accelerator.cancel()   // runAccelerated() then calls finish()
            return
        }
        guard let process = job.process, process.isRunning else {
            // Still resolving the plan; runAccelerated() checks stopReason when it returns.
            return
        }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard process.isRunning else { return }
            process.terminate()
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-TERM", "-P", "\(pid)"])
        }
    }

    private func handle(_ line: String, for job: DownloadJob) {
        job.log.append(line)
        if job.log.count > 400 { job.log.removeFirst(job.log.count - 400) }

        if job.kind == .gallery {
            handleGallery(line, for: job)
            return
        }

        if line.hasPrefix("@@P ") {
            parseProgress(String(line.dropFirst(4)), for: job)
        } else if line.hasPrefix("@@PP ") {
            job.status = .processing(Self.friendlyStep(String(line.dropFirst(5))))
            job.speed = nil
            job.eta = nil
        } else if line.hasPrefix("@@T ") {
            let title = String(line.dropFirst(4))
            if !title.isEmpty, title != "NA" { job.title = title }
        } else if line.hasPrefix("@@S ") {
            job.expectedBytes = Double(line.dropFirst(4))
        } else if line.hasPrefix("@@I ") {
            if job.thumbnail == nil { job.thumbnail = URL(string: String(line.dropFirst(4))) }
        } else if line.hasPrefix("@@N ") {
            job.plannedFilename = String(line.dropFirst(4))
        } else if line.hasPrefix("@@F ") {
            job.fileURL = URL(fileURLWithPath: String(line.dropFirst(4)))
        } else if line.hasPrefix("ERROR:") {
            job.lastError = Engine.readableError(line, fallback: "The download failed.")
        }
    }

    /// gallery-dl prints each saved file's path ("# path" if it already existed).
    private func handleGallery(_ line: String, for job: DownloadJob) {
        var path = line
        if path.hasPrefix("# ") { path.removeFirst(2) }
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            job.galleryFiles.append(url)
            job.fileURL = url
            job.status = .downloading
            if job.thumbnail == nil || job.thumbnail?.isFileURL == false, DownloadJob.isImage(url) {
                job.thumbnail = url
            }
            if job.galleryFiles.count == 1 {
                job.title = url.deletingPathExtension().lastPathComponent
            }
        } else if line.contains("][error]") {
            job.lastError = Engine.readableError(job.log.joined(separator: "\n"), fallback: "The download failed.")
        }
    }

    private func parseProgress(_ payload: String, for job: DownloadJob) {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return }

        let downloaded = Double(parts[0]) ?? 0
        let streamTotal = Double(parts[1]) ?? Double(parts[2]) ?? 0
        let format = parts[5]

        // A new stream (e.g. audio after video) began: bank the previous one.
        if let current = job.currentFormat, current != format {
            job.completedStreamBytes += job.currentStreamTotal
        }
        job.currentFormat = format
        job.currentStreamTotal = max(streamTotal, downloaded)

        job.status = .downloading
        job.downloadedBytes = job.completedStreamBytes + downloaded
        job.speed = Double(parts[3])
        job.eta = Double(parts[4])

        if let expected = job.expectedBytes, expected > 0 {
            job.fraction = min(job.downloadedBytes / expected, 0.99)
        } else if streamTotal > 0 {
            job.fraction = min(downloaded / streamTotal, 0.99)
        }
    }

    private func finish(_ job: DownloadJob, exitStatus: Int32) {
        job.process = nil
        job.accelerator = nil
        job.acceleratorTask = nil
        job.activeConnections = nil
        if let info = job.plan?.infoFile, job.stopReason != .pause { try? FileManager.default.removeItem(at: info) }
        switch job.stopReason {
        case .pause:
            job.status = .paused
            job.speed = nil
            job.eta = nil
        case .cancel:
            job.status = .cancelled
            removePartialFiles(of: job)
        case nil:
            let succeeded = job.kind == .gallery
                ? (exitStatus == 0 && !job.galleryFiles.isEmpty)
                : exitStatus == 0
            if succeeded {
                job.status = .finished
                job.fraction = 1
                let files = job.kind == .gallery ? job.galleryFiles : [job.fileURL].compactMap { $0 }
                let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                if !sizes.isEmpty { job.fileSize = Double(sizes.reduce(0, +)) }
                Notifier.downloadFinished(job)
            } else if job.kind == .gallery && exitStatus == 0 {
                job.status = .failed("There was nothing to save in this post.")
            } else {
                job.status = .failed(job.lastError
                    ?? Engine.readableError(job.log.joined(separator: "\n"),
                                            fallback: "The download stopped unexpectedly (code \(exitStatus))."))
            }
        }
        pump()
    }

    private func removePartialFiles(of job: DownloadJob) {
        // Accelerator segments and their ledgers.
        for stream in job.plan?.streams ?? [] {
            try? FileManager.default.removeItem(at: stream.partURL)
            try? FileManager.default.removeItem(at: stream.ledgerURL)
        }
        job.plan = nil
        guard let planned = job.plannedFilename else { return }
        let plannedURL = URL(fileURLWithPath: planned)
        let folder = plannedURL.deletingLastPathComponent()
        let stem = plannedURL.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in items where name.hasPrefix(stem) {
            if name.hasSuffix(".part") || name.hasSuffix(".ytdl") || name.contains(".part-Frag") || name.contains(".temp.") {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    private func updateBadge() {
        let count = activeCount
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    static func friendlyStep(_ name: String) -> String {
        switch name {
        case "Merger": "Merging video and audio…"
        case "ExtractAudio", "FFmpegExtractAudio": "Converting audio…"
        case "EmbedThumbnail": "Adding artwork…"
        case "FFmpegMetadata", "Metadata": "Adding details…"
        case "FFmpegEmbedSubtitle", "EmbedSubtitle": "Adding subtitles…"
        case "VideoConvertor", "VideoRemuxer", "FFmpegVideoConvertor", "FFmpegVideoRemuxer": "Converting…"
        case "FixupM3u8", "FixupM4a", "FixupDuplicateMoov", "FixupTimestamp": "Tidying up…"
        default: "Finishing…"
        }
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func downloadFinished(_ job: DownloadJob) {
        let enabled = UserDefaults.standard.object(forKey: "notify") as? Bool ?? true
        guard enabled, !NSApp.isActive || !(NSApp.keyWindow?.isVisible ?? false) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = job.title
        content.sound = .default
        if let path = (job.galleryFiles.first ?? job.fileURL)?.path { content.userInfo = ["path": path] }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
        )
    }
}
