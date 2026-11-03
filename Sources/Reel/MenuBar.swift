import AppKit
import SwiftUI

/// A floating panel that can take keyboard input without activating Reel, and appears
/// over every Space, including full-screen apps.
final class MenuPanelWindow: NSPanel {
    init(content: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 370, height: 300),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        contentViewController = content
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { MenuBarController.shared.hidePanel() }
    }
}

/// Reel's menu bar icon: drop links onto it to download them, click it to see progress.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate, NSDraggingDestination {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var panel: MenuPanelWindow?
    private var clickMonitor: Any?
    private var lastHidden = Date.distantPast
    private var timer: Timer?
    private var lastIconKey = ""
    private var acceptedUntil: Date?

    var isVisible: Bool { item != nil }

    func setVisible(_ visible: Bool) {
        visible ? install() : uninstall()
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.image = Self.icon(progress: nil, active: false, accepted: false)
        button.toolTip = "Reel — drop a link here to download it"
        button.target = self
        button.action = #selector(togglePanel)
        // The status item's window forwards drag events to its delegate.
        button.window?.registerForDraggedTypes([.URL, .string])
        button.window?.delegate = self
        self.item = item

        let host = NSHostingController(
            rootView: MenuPanel()
                .environment(Shared.engine)
                .environment(Shared.queue)
        )
        host.sizingOptions = .preferredContentSize
        let panel = MenuPanelWindow(content: host)
        // Keep the panel pinned under the icon as its content grows or shrinks.
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarController.shared.positionPanel() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarController.shared.hidePanel() }
        }
        self.panel = panel

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarController.shared.refreshIcon() }
        }
    }

    private func uninstall() {
        timer?.invalidate()
        timer = nil
        hidePanel()
        panel = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        lastIconKey = ""
    }

    var isPanelShown: Bool { panel?.isVisible ?? false }

    @objc private func togglePanel() {
        if isPanelShown {
            hidePanel()
        } else if Date().timeIntervalSince(lastHidden) > 0.25 {
            // (A click on the icon first hides the panel by taking focus; don't reopen it.)
            showPanel()
        }
    }

    func showPanel() {
        guard let panel, item?.button != nil else { return }
        positionPanel()
        // No NSApp.activate(): activating would pull the user out of a full-screen app.
        panel.makeKeyAndOrderFront(nil)
        item?.button?.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { MenuBarController.shared.hidePanel() }
        }
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        item?.button?.highlight(false)
        lastHidden = Date()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// Places the panel just below the icon, kept on screen.
    func positionPanel() {
        guard let panel, let buttonWindow = item?.button?.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let icon = buttonWindow.frame
        let size = panel.frame.size
        let visible = screen.frame
        var x = icon.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = icon.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: Icon

    private func refreshIcon() {
        guard let button = item?.button else { return }
        let queue = Shared.queue
        let active = queue.activeCount > 0
        let progress = queue.overallFraction
        let accepted = (acceptedUntil ?? .distantPast) > Date()
        let key = "\(active)-\(progress.map { Int($0 * 40) } ?? -1)-\(accepted)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = Self.icon(progress: progress, active: active, accepted: accepted)
    }

    /// A template image: an arrow in a ring that fills with overall progress.
    static func icon(progress: Double?, active: Bool, accepted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.6

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(active ? 0.3 : 1).setStroke()
            track.stroke()

            if active {
                let fraction = max(progress ?? 0.12, 0.04)
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = 2.2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            let symbolName = accepted ? "checkmark" : "arrow.down"
            let config = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold)
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let size = symbol.size
                symbol.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                       width: size.width, height: size.height))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Reel"
        return image
    }

    // MARK: Dropping links

    nonisolated func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let links = Self.links(from: sender.draggingPasteboard)
        MainActor.assumeIsolated { item?.button?.highlight(!links.isEmpty) }
        return links.isEmpty ? [] : .copy
    }

    nonisolated func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { item?.button?.highlight(false) }
    }

    nonisolated func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    nonisolated func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let links = Self.links(from: sender.draggingPasteboard)
        return MainActor.assumeIsolated {
            item?.button?.highlight(false)
            guard !links.isEmpty else { return false }
            links.forEach { Shared.queue.quickAdd($0) }
            // Brief checkmark so you know it landed, without leaving the app you're in.
            acceptedUntil = Date().addingTimeInterval(1.2)
            refreshIcon()
            return true
        }
    }

    nonisolated static func links(from pasteboard: NSPasteboard) -> [String] {
        var found: [String] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            found += urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }.map(\.absoluteString)
        }
        if found.isEmpty, let text = pasteboard.string(forType: .string) {
            found += text.split(whereSeparator: \.isWhitespace).compactMap { piece in
                let s = String(piece)
                guard let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { return nil }
                return s
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }
}

/// The panel under the menu bar icon.
struct MenuPanel: View {
    @Environment(DownloadQueue.self) private var queue
    @Environment(Engine.self) private var engine
    @State private var link = ""
    @State private var copied: String?
    @State private var dropTargeted = false
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reel").font(.headline)
                Spacer()
                Button {
                    MenuBarController.shared.hidePanel()
                    Shared.openMainWindow()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("Open Reel Window")
                Button {
                    MenuBarController.shared.hidePanel()
                    NSApp.activate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Paste a link to download", text: $link)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            if let copied, link.isEmpty {
                Button {
                    queue.quickAdd(copied)
                    self.copied = nil
                } label: {
                    Label {
                        Text("Download copied link ") + Text(ContentView.shortened(copied)).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.glass)
            }

            if case .installing = engine.phase {
                Label("Reel is finishing setup…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }

            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Drop links onto the menu bar icon, or paste one above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(queue.jobs.prefix(30)) { job in
                            MiniRow(job: job)
                        }
                    }
                }
                .frame(maxHeight: 330)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Finished") { withAnimation { queue.clearFinished() } }
                    .disabled(!queue.hasClearable)
                Button("Quit") {
                    MenuBarController.shared.hidePanel()
                    NSApp.activate()
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 370)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let links = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            links.forEach { queue.quickAdd($0.absoluteString) }
            return !links.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // The panel is reused; refresh the clipboard suggestion each time it opens.
            guard (note.object as? NSWindow) is MenuPanelWindow else { return }
            refreshCopied()
            focused = true
        }
        .onAppear {
            copied = ContentView.copiedLink().flatMap { candidate in
                queue.jobs.contains(where: { $0.link == candidate }) ? nil : candidate
            }
            focused = true
        }
    }

    private var summary: String {
        let active = queue.activeCount
        if active > 0 { return active == 1 ? "1 download in progress" : "\(active) downloads in progress" }
        let done = queue.jobs.filter { $0.status == .finished }.count
        return done > 0 ? "All downloads finished" : "Ready"
    }

    private func refreshCopied() {
        copied = ContentView.copiedLink().flatMap { candidate in
            queue.jobs.contains(where: { $0.link == candidate }) ? nil : candidate
        }
    }

    private func add() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard URL(string: candidate)?.host != nil else { return }
        queue.quickAdd(candidate)
        link = ""
    }
}

struct MiniRow: View {
    let job: DownloadJob
    @State private var showingLog = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: job.thumbnail, width: 60, placeholder: job.kind == .gallery ? "photo" : "play.rectangle")
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if job.showsProgressBar {
                    if let value = job.barValue {
                        ProgressView(value: value).progressViewStyle(.linear).controlSize(.small)
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.small)
                    }
                }
                Text(job.statusLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(job.isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            JobControls(job: job, size: .title3)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { job.open() }
        .contextMenu { JobMenu(job: job, showingLog: $showingLog) }
        .popover(isPresented: $showingLog) { LogView(lines: job.log) }
    }
}
