import AppKit
import SwiftUI

/// "What's New" shown once after each update. The notes come from CHANGELOG.md:
/// build.sh copies this version's section into the app as WhatsNew.md, so the
/// changelog is the only place release notes are written.
@MainActor
enum WhatsNew {
    struct Section: Identifiable {
        let title: String
        let items: [AttributedString]
        var id: String { title }

        var symbol: String {
            switch title.lowercased() {
            case "added": "sparkles"
            case "changed": "arrow.triangle.2.circlepath"
            case "fixed": "wrench.and.screwdriver"
            case "removed": "minus.circle"
            case "security": "lock.shield"
            default: "star"
            }
        }

        var heading: String {
            switch title.lowercased() {
            case "added": "New"
            case "changed": "Improved"
            case "fixed": "Fixed"
            default: title
            }
        }
    }

    private static let seenKey = "whatsNewSeenVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Whether Reel had been set up before this launch. Captured early, before the
    /// engine creates its folder, so a brand-new install isn't greeted with release notes.
    private static var wasInstalledBefore = false

    static func captureInstallState() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        wasInstalledBefore = FileManager.default.fileExists(atPath: support.appendingPathComponent("Reel").path)
    }

    /// Shows the notes if this version hasn't been seen yet. First-time installs just
    /// record the version, so the window only ever follows an update.
    static func showIfUpdated() {
        let defaults = UserDefaults.standard
        let seen = defaults.string(forKey: seenKey)
        defaults.set(currentVersion, forKey: seenKey)
        guard seen != currentVersion else { return }
        // 1.0 didn't record a version, so an existing setup folder means "updated from 1.0".
        guard seen != nil || wasInstalledBefore else { return }
        guard !sections().isEmpty else { return }
        show()
    }

    static func show() {
        WhatsNewWindow.shared.present(version: currentVersion, sections: sections())
    }

    static func sections() -> [Section] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Parses a Keep a Changelog section: `### Heading` lines followed by `- item` lines.
    nonisolated static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        var title: String?
        var items: [AttributedString] = []
        func flush() {
            if let title, !items.isEmpty { sections.append(Section(title: title, items: items)) }
            items = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                flush()
                title = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let markdown = String(line.dropFirst(2))
                let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                items.append((try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown))
            } else if !line.isEmpty, !line.hasPrefix("#"), !items.isEmpty {
                // A wrapped continuation of the previous item.
                var last = items.removeLast()
                last.append(AttributedString(" " + line))
                items.append(last)
            }
        }
        flush()
        return sections
    }
}

/// A standalone window, so it also appears when Reel runs from the menu bar only.
@MainActor
final class WhatsNewWindow {
    static let shared = WhatsNewWindow()
    private var window: NSWindow?

    func present(version: String, sections: [WhatsNew.Section]) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = WhatsNewView(version: version, sections: sections) { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 500, height: 600))
        window.center()
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

struct WhatsNewView: View {
    let version: String
    let sections: [WhatsNew.Section]
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                Text("What's New in Reel")
                    .font(.title.bold())
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(section.heading, systemImage: section.symbol)
                                .font(.headline)
                                .foregroundStyle(.tint)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .fill(.tertiary)
                                        .frame(width: 5, height: 5)
                                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                                    Text(item)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.automatic)

            HStack {
                Link("Full Release Notes", destination: Support.repository.appendingPathComponent("releases/tag/v\(version)"))
                    .font(.callout)
                Spacer()
                Button("Continue", action: dismiss)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.bar)
        }
        .frame(width: 500, height: 600)
    }
}
