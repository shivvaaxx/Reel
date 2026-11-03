import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(Engine.self) private var engine
    @Environment(DownloadQueue.self) private var queue
    @AppStorage("defaultQuality") private var defaultQuality = Quality.best.rawValue
    @AppStorage("suggestClipboard") private var suggestClipboard = true
    @Environment(\.openWindow) private var openWindow

    enum Lookup {
        case idle, loading, loaded(MediaInfo), gallery(String), failed(String)
    }

    @State private var link = ""
    @State private var lookup: Lookup = .idle
    @State private var lookupTask: Task<Void, Never>?
    @State private var quality: Quality = .best
    @State private var selection: Set<String> = []
    @State private var clipboardLink: String?
    @State private var dismissedClipboard: String?
    @State private var dropTargeted = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                linkBar
                lookupArea
            }
            .padding(20)
            .animation(.smooth(duration: 0.3), value: lookupKey)

            downloads
        }
        .frame(minWidth: 620, minHeight: 540)
        .navigationTitle("Reel")
        .background(WindowIdentifier())
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear Finished", systemImage: "checklist.checked") {
                    withAnimation { queue.clearFinished() }
                }
                .help("Remove finished, cancelled and failed downloads from the list")
                .disabled(!queue.hasClearable)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Show Downloads Folder", systemImage: "folder") {
                    NSWorkspace.shared.open(Prefs.downloadFolder)
                }
                .help("Open the downloads folder")
            }
        }
        .overlay { setupOverlay }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            link = url.absoluteString
            lookUp()
            return true
        } isTargeted: { dropTargeted = $0 }
        .onAppear {
            Shared.openWindowAction = openWindow
            linkFocused = true
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reelFocusLink)) { _ in
            linkFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .reelDownloadClipboard)) { _ in
            if let copied = Self.copiedLink() {
                link = copied
                lookUp()
            }
        }
    }

    // MARK: Link bar

    private var linkBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Paste a video or playlist link", text: $link)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($linkFocused)
                    .onSubmit(lookUp)
                if case .loading = lookup {
                    ProgressView().controlSize(.small)
                } else if !link.isEmpty {
                    Button {
                        resetLookup()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .glassEffect(.regular.interactive(), in: .capsule)

            if let copied = clipboardLink, link.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        link = copied
                        lookUp()
                    } label: {
                        Label {
                            Text("Use copied link ") + Text(Self.shortened(copied)).foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    Button {
                        dismissedClipboard = copied
                        clipboardLink = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: Lookup results

    @ViewBuilder
    private var lookupArea: some View {
        switch lookup {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking up the link…").foregroundStyle(.secondary)
            }
            .padding(.leading, 6)
            .transition(.opacity)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .padding(.leading, 6)
                .transition(.opacity)
        case .gallery(let galleryLink):
            GalleryCard(link: galleryLink) {
                queue.enqueue(link: galleryLink, title: "\(Prefs.siteName(for: galleryLink)) post",
                              thumbnail: nil, quality: quality, kind: .gallery)
                resetLookup()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        case .loaded(let info):
            Group {
                if info.isPlaylist {
                    PlaylistCard(info: info, quality: $quality, selection: $selection) {
                        downloadSelected(from: info)
                    }
                } else {
                    VideoCard(info: info, quality: $quality) {
                        queue.enqueue(link: info.link, title: info.title, thumbnail: info.thumbnail, quality: quality)
                        resetLookup()
                    }
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Downloads list

    @ViewBuilder
    private var downloads: some View {
        if queue.jobs.isEmpty {
            ContentUnavailableView {
                Label("No Downloads", systemImage: "arrow.down.circle")
            } description: {
                Text("Paste a link above, or drop one anywhere in this window.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(queue.jobs) { job in
                        DownloadRow(job: job)
                    }
                } header: {
                    Text("Downloads")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .animation(.default, value: queue.jobs.map(\.id))
        }
    }

    // MARK: Setup overlay

    @ViewBuilder
    private var setupOverlay: some View {
        switch engine.phase {
        case .installing, .failed:
            EngineSetupView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    // MARK: Actions

    private var lookupKey: String {
        switch lookup {
        case .idle: "idle"
        case .loading: "loading"
        case .failed(let m): "failed-\(m)"
        case .gallery(let l): "gallery-\(l)"
        case .loaded(let i): "loaded-\(i.link)"
        }
    }

    private var subtitle: String {
        let running = queue.runningCount
        let waiting = queue.jobs.filter { $0.status == .queued }.count
        switch (running, waiting) {
        case (0, 0): return ""
        case (_, 0): return running == 1 ? "1 downloading" : "\(running) downloading"
        default: return "\(running) downloading, \(waiting) waiting"
        }
    }

    private func lookUp() {
        var candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let url = URL(string: candidate), url.host != nil else {
            lookup = .failed("That doesn't look like a link.")
            return
        }
        link = candidate
        clipboardLink = nil
        dismissedClipboard = candidate
        quality = Quality(rawValue: defaultQuality) ?? .best
        lookupTask?.cancel()
        if Prefs.kind(for: candidate) == .gallery {
            lookup = .gallery(candidate)
            return
        }
        lookup = .loading
        lookupTask = Task {
            do {
                let info = try await engine.probe(candidate)
                guard !Task.isCancelled else { return }
                selection = Set(info.entries.map(\.id))
                lookup = .loaded(info)
            } catch EngineError.noVideo {
                guard !Task.isCancelled else { return }
                lookup = .gallery(candidate)
            } catch {
                guard !Task.isCancelled else { return }
                lookup = .failed(error.localizedDescription)
            }
        }
    }

    private func downloadSelected(from info: MediaInfo) {
        for entry in info.entries where selection.contains(entry.id) {
            queue.enqueue(link: entry.url, title: entry.title, thumbnail: entry.thumbnail, quality: quality)
        }
        resetLookup()
    }

    private func resetLookup() {
        lookupTask?.cancel()
        link = ""
        lookup = .idle
        linkFocused = true
    }

    private func checkClipboard() {
        guard suggestClipboard, let copied = Self.copiedLink(), copied != dismissedClipboard,
              copied != link else { return }
        withAnimation(.smooth) { clipboardLink = copied }
    }

    nonisolated static func copiedLink() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !string.contains(" "), !string.contains("\n"),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return string
    }

    nonisolated static func shortened(_ link: String) -> String {
        guard let url = URL(string: link), let host = url.host else { return link }
        let path = url.path + (url.query.map { "?" + $0 } ?? "")
        let trimmedHost = host.replacingOccurrences(of: "www.", with: "")
        let text = trimmedHost + path
        return text.count > 42 ? String(text.prefix(40)) + "…" : text
    }
}
