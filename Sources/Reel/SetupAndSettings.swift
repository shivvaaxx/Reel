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
            Tab("Support", systemImage: "heart") { SupportSettings() }
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
    @AppStorage("resumeOnLaunch") private var resumeOnLaunch = true
    @AppStorage("handoffStartsImmediately") private var handoffStartsImmediately = true
    @State private var copiedBookmarklet = false

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
            Toggle(isOn: $suggestClipboard) {
                Text("Offer to use copied links")
                Text("Reel only checks whether a link was copied; it reads the clipboard when you click the button.")
            }
            Toggle(isOn: $resumeOnLaunch) {
                Text("Continue unfinished downloads when Reel opens")
                Text("Downloads interrupted by quitting pick up where they left off.")
            }

            Section {
                Toggle(isOn: $handoffStartsImmediately) {
                    Text("Start links sent from other apps right away")
                    Text("Applies to the Services menu, the Share menu, the Safari button and the bookmarklet. Off: they open in Reel for a preview first.")
                }
                LabeledContent {
                    Button(copiedBookmarklet ? "Copied" : "Copy Bookmarklet") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Handoff.bookmarklet, forType: .string)
                        copiedBookmarklet = true
                    }
                } label: {
                    Text("Bookmarklet for any browser")
                    Text("Make a bookmark, paste this as its address, and click it on any video page to send it to Reel.")
                }
            } header: {
                Text("From Other Apps")
            } footer: {
                Text("Select a link in any app and choose Services › Download with Reel.")
                    .foregroundStyle(.secondary)
            }
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
    @AppStorage("proxy") private var proxy = ""
    @AppStorage("hevc4K") private var hevc4K = true
    @AppStorage("limitRate") private var limitRate = false
    @AppStorage("rateLimitMB") private var rateLimitMB = 5.0
    @AppStorage("scheduleEnabled") private var scheduleEnabled = false
    @AppStorage("scheduleStart") private var scheduleStart = 60
    @AppStorage("scheduleEnd") private var scheduleEnd = 420
    @AppStorage("pauseOnCostlyNetwork") private var pauseOnCostlyNetwork = true
    @AppStorage("photosMode") private var photosMode = Integrations.PhotosMode.off.rawValue
    @AppStorage("addToMusic") private var addToMusic = false

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
                    Text("Files play in QuickTime, Photos and on iPhone and iPad.")
                }
                if compatible {
                    Toggle(isOn: $hevc4K) {
                        Text("Keep 4K by converting to HEVC")
                        Text("YouTube's 4K is only offered in formats QuickTime can't play. Reel downloads it and converts it with your Mac's video encoder. Off: limit to 1080p H.264.")
                    }
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
            Section {
                Picker(selection: $photosMode) {
                    ForEach(Integrations.PhotosMode.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    Text("Add to Photos")
                    Text("Copies downloaded photos (and optionally playable videos) into your Photos library.")
                }
                Toggle(isOn: $addToMusic) {
                    Text("Add audio downloads to Music")
                    Text("Audio-only downloads appear in your Music library with their artwork.")
                }
            } header: {
                Text("After Downloading")
            } footer: {
                Text("Files are always kept in your downloads folder too.")
                    .foregroundStyle(.secondary)
            }
            Section("Speed") {
                Toggle("Limit download speed", isOn: $limitRate)
                if limitRate {
                    LabeledContent("Maximum") {
                        HStack {
                            TextField("", value: $rateLimitMB, format: .number.precision(.fractionLength(0...1)))
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("MB/s")
                            Stepper("", value: $rateLimitMB, in: 0.5...500, step: 0.5).labelsHidden()
                        }
                    }
                    Text("Limited downloads use a single connection, so the accelerator is off while this is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Schedule") {
                Toggle(isOn: $scheduleEnabled) {
                    Text("Only download during set hours")
                    Text("New and paused downloads wait until the window opens, and pause when it closes.")
                }
                if scheduleEnabled {
                    DatePicker("From", selection: minutes($scheduleStart), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutes($scheduleEnd), displayedComponents: .hourAndMinute)
                }
                Toggle(isOn: $pauseOnCostlyNetwork) {
                    Text("Wait on Personal Hotspot or Low Data Mode")
                    Text("Saves your mobile data. Downloads continue when you're back on regular Wi-Fi.")
                }
            }
            .onChange(of: scheduleEnabled) { Shared.queue.applyHold() }
            .onChange(of: scheduleStart) { Shared.queue.applyHold() }
            .onChange(of: scheduleEnd) { Shared.queue.applyHold() }
            .onChange(of: pauseOnCostlyNetwork) { Shared.queue.applyHold() }
            Section {
                TextField("Proxy", text: $proxy, prompt: Text("None"))
            } footer: {
                Text("For videos blocked in your country. Enter a proxy address such as socks5://127.0.0.1:1080 or http://host:port. Leave empty to connect directly.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private func minutes(_ value: Binding<Int>) -> Binding<Date> {
    Binding(get: { Schedule.date(fromMinutes: value.wrappedValue) },
            set: { value.wrappedValue = Schedule.minutes(from: $0) })
}

private struct AccountSettings: View {
    @AppStorage("cookieBrowser") private var cookieBrowser = "none"
    @State private var signInSites = Prefs.signInSites

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
                Text("Some posts and videos are only shown to signed-in people (Instagram, TikTok, age-restricted or members-only YouTube). Reel can borrow your browser's sign-in for the sites you tick below. It's read on your Mac by the download tools and never sent anywhere else.")
                    .foregroundStyle(.secondary)
            }

            if cookieBrowser != "none" {
                Section("Use it for") {
                    ForEach(Prefs.signInSiteKeys, id: \.key) { site in
                        Toggle(site.name, isOn: Binding(
                            get: { signInSites.contains(site.key) },
                            set: { on in
                                var sites = signInSites
                                if on { sites.insert(site.key) } else { sites.remove(site.key) }
                                UserDefaults.standard.set(Array(sites).sorted(), forKey: "signInSites")
                                signInSites = sites
                            }
                        ))
                    }
                }
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

private struct SupportSettings: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.pink)
                    Text("Reel is free and open source")
                        .font(.headline)
                    Text("If it saves you time, you can support its development. Every coffee helps keep Reel updated as sites change.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                LabeledContent {
                    Button("Buy Me a Coffee…") { NSWorkspace.shared.open(Support.kofi) }
                } label: {
                    Text("Ko-fi")
                    Text("A one-off tip by card, PayPal or Apple Pay.")
                }
                LabeledContent {
                    Button("Sponsor…") { NSWorkspace.shared.open(Support.sponsors) }
                } label: {
                    Text("GitHub Sponsors")
                    Text("Monthly or one-time, for GitHub users.")
                }
                LabeledContent {
                    Button("Open GitHub…") { NSWorkspace.shared.open(Support.repository) }
                } label: {
                    Text("Star the project or report a problem")
                    Text("Free, and it helps too.")
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

            Section("Reel") {
                UpdateSettings()
            }

            Section("Download Tools") {
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
