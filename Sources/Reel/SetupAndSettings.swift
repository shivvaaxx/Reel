import AppKit
import SwiftUI

/// First-run screen while Reel fetches its private tools.
struct EngineSetupView: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text(isFailed ? "Reel Couldn't Finish Setting Up" : "Getting Reel Ready")
                    .font(.title2.weight(.semibold))
                Text(isFailed ? failureMessage
                              : "Reel is downloading the tools it uses to fetch videos. This only happens once.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            VStack(spacing: 0) {
                ForEach(engine.installQueue) { component in
                    HStack(spacing: 12) {
                        statusIcon(for: component)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(component.displayName).font(.body.weight(.medium))
                            Text(component.role).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if engine.currentComponent == component, component.reportsProgress {
                            Text(engine.componentProgress, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    if component != engine.installQueue.last { Divider().padding(.leading, 46) }
                }
            }
            .frame(width: 380)
            .background(.fill.quinary, in: .rect(cornerRadius: 14))

            if isFailed {
                Button("Try Again") {
                    Task { await engine.prepare() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
    }

    private var isFailed: Bool { engine.phase.isFailure }

    private var failureMessage: String {
        if case .failed(let message) = engine.phase { message } else { "" }
    }

    @ViewBuilder
    private func statusIcon(for component: Component) -> some View {
        if engine.installedThisRun.contains(component) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if engine.currentComponent == component {
            if component.reportsProgress {
                ProgressView(value: engine.componentProgress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        } else if isFailed {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettings() }
            Tab("Accounts", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("Engine", systemImage: "shippingbox") { EngineSettings() }
        }
        .frame(width: 500)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage("downloadFolder") private var downloadFolder = ""
    @AppStorage("maxConcurrent") private var maxConcurrent = 3
    @AppStorage("notify") private var notify = true
    @AppStorage("suggestClipboard") private var suggestClipboard = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showInMenuBar) {
                    Text("Show Reel in the menu bar")
                    Text("Drop links onto the icon to download them, and click it to check progress without leaving the app you're in.")
                }
                .disabled(!showInDock)
                Toggle(isOn: $showInDock) {
                    Text("Show Reel in the Dock")
                    Text("Turn off to keep Reel only in the menu bar.")
                }
            }
            .onChange(of: showInDock) { _, dock in
                if !dock { showInMenuBar = true }
                Shared.applyPresence()
            }
            .onChange(of: showInMenuBar) { _, _ in Shared.applyPresence() }

            LabeledContent("Save downloads to") {
                HStack {
                    Label {
                        Text(Prefs.downloadFolder.lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Prefs.downloadFolder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Button("Choose…", action: chooseFolder)
                }
            }
            Picker("Download at once", selection: $maxConcurrent) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("Notify me when a download finishes", isOn: $notify)
            Toggle("Offer to use copied links", isOn: $suggestClipboard)
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Prefs.downloadFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }
}

private struct DownloadSettings: View {
    @AppStorage("defaultQuality") private var defaultQuality = Quality.best.rawValue
    @AppStorage("audioFormat") private var audioFormat = AudioFormat.m4a.rawValue
    @AppStorage("compatible") private var compatible = true
    @AppStorage("embedDetails") private var embedDetails = true
    @AppStorage("subtitles") private var subtitles = false
    @AppStorage("subtitleLanguage") private var subtitleLanguage = "en"
    @AppStorage("connections") private var connections = 8

    var body: some View {
        Form {
            Section {
                Picker("Default quality", selection: $defaultQuality) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(selection: $connections) {
                    Text("Off").tag(1)
                    Text("4 connections").tag(4)
                    Text("8 connections").tag(8)
                    Text("16 connections").tag(16)
                } label: {
                    Text("Accelerate downloads")
                    Text("Splits each video into segments and downloads them at the same time, like a download manager. Often several times faster, especially on YouTube.")
                }
                Picker("Audio format", selection: $audioFormat) {
                    ForEach(AudioFormat.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                Toggle(isOn: $compatible) {
                    Text("Prefer QuickTime-compatible video")
                    Text("Downloads H.264 video that plays everywhere on your Mac, iPhone and iPad. Usually limits YouTube to 1080p; turn off for 4K.")
                }
                Toggle(isOn: $embedDetails) {
                    Text("Add artwork, chapters and details")
                    Text("Embeds the thumbnail, title, channel and chapters into the file.")
                }
                Toggle("Include subtitles", isOn: $subtitles)
                if subtitles {
                    TextField("Subtitle language", text: $subtitleLanguage, prompt: Text("en"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettings: View {
    @AppStorage("cookieBrowser") private var cookieBrowser = "none"

    private let browsers: [(id: String, name: String)] = [
        ("none", "Don't Use a Sign-In"),
        ("safari", "Safari"),
        ("chrome", "Google Chrome"),
        ("firefox", "Firefox"),
        ("brave", "Brave"),
        ("edge", "Microsoft Edge"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Use sign-in from", selection: $cookieBrowser) {
                    ForEach(browsers, id: \.id) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text("Instagram and TikTok often only show posts to signed-in people. Reel can borrow the sign-in from your browser for those two sites only. It's never sent anywhere else.")
                    .foregroundStyle(.secondary)
            }

            if cookieBrowser == "safari" {
                Section {
                    LabeledContent {
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!)
                        }
                    } label: {
                        Text("Safari needs Full Disk Access")
                        Text("macOS keeps Safari's sign-ins private. Add Reel under Privacy & Security › Full Disk Access.")
                    }
                }
            } else if cookieBrowser != "none" {
                Section {
                    Text("The first time, macOS may ask whether Reel can use your browser's saved data. Choose Always Allow.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EngineSettings: View {
    @Environment(Engine.self) private var engine
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        Form {
            Section {
                ForEach(Component.allCases) { component in
                    LabeledContent {
                        Text(engine.versions[component] ?? "—")
                            .monospacedDigit()
                            .textSelection(.enabled)
                    } label: {
                        Text(component.displayName)
                        Text(component.role)
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([engine.binDir])
                    }
                    .buttonStyle(.link)
                }
            }

            Section {
                Toggle(isOn: $autoUpdate) {
                    Text("Keep tools up to date automatically")
                    Text("Checks yt-dlp and gallery-dl daily and the other tools monthly. Sites change often, so this keeps downloads working.")
                }
                HStack {
                    if engine.isUpdating {
                        ProgressView().controlSize(.small)
                        Text("Checking…").foregroundStyle(.secondary)
                    } else if let message = engine.updateMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reinstall All") {
                        Task { await engine.reinstallAll() }
                    }
                    Button("Update Now") {
                        Task { await engine.updateTools() }
                    }
                    .disabled(engine.isUpdating)
                }
            }
        }
        .formStyle(.grouped)
        .task { await engine.refreshVersions() }
    }
}
