import AppKit
import SwiftUI

/// Channels and playlists whose new uploads download automatically.
struct SubscriptionsView: View {
    @Environment(Subscriptions.self) private var subscriptions
    @AppStorage("subscriptionHours") private var hours = 6.0
    @State private var link = ""
    @State private var quality = Prefs.defaultQuality
    @State private var latest = 0
    @State private var adding = false
    @State private var error: String?
    @State private var selection: Set<UUID> = []
    @State private var notice: String?
    /// nil = Reel's download folder.
    @State private var folder: URL?

    var body: some View {
        VStack(spacing: 0) {
            addBar
                .padding(20)
            if subscriptions.items.isEmpty {
                ContentUnavailableView {
                    Label("No Subscriptions", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Paste a YouTube channel or playlist link above. Reel checks it regularly and downloads new videos as they appear.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(subscriptions.items) { sub in
                            SubscriptionRow(sub: sub, checking: subscriptions.checking.contains(sub.id)) {
                                downloadExisting(sub)
                            }
                                .tag(sub.id)
                                .contextMenu { menu(for: sub) }
                        }
                    } header: {
                        HStack {
                            Text("Checks every \(hoursText)")
                            Spacer()
                            Picker("Check every", selection: $hours) {
                                Text("Hour").tag(1.0)
                                Text("3 hours").tag(3.0)
                                Text("6 hours").tag(6.0)
                                Text("12 hours").tag(12.0)
                                Text("Day").tag(24.0)
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button("Check Now") { subscriptions.checkAll() }
                                .buttonStyle(.link)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onDeleteCommand { subscriptions.remove(selection) }
            }
        }
    }

    private var hoursText: String {
        hours == 1 ? "hour" : hours == 24 ? "day" : "\(Int(hours)) hours"
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Channel or playlist link", text: $link)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit(add)
                if adding { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .glassEffect(.regular.interactive(), in: .capsule)

            HStack(spacing: 12) {
                QualityPicker(quality: $quality)
                Picker("Also download", selection: $latest) {
                    Text("Only new uploads").tag(0)
                    Text("Plus the latest 1").tag(1)
                    Text("Plus the latest 5").tag(5)
                    Text("Plus the latest 10").tag(10)
                    Divider()
                    Text("Plus everything already there").tag(Subscriptions.everything)
                }
                .labelsHidden()
                .fixedSize()
                Menu {
                    Button("Reel's Download Folder") { folder = nil }
                    Button("Choose Folder…") { if let url = Self.chooseFolder() { folder = url } }
                } label: {
                    Label(folder?.lastPathComponent ?? Prefs.downloadFolder.lastPathComponent, systemImage: "folder")
                }
                .fixedSize()
                .help("Where this subscription saves. Reel checks this folder for videos you already have.")
                Spacer()
                Button("Subscribe", systemImage: "plus", action: add)
                    .buttonStyle(.glassProminent)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || adding)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
            } else if let notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(latest == 0
                     ? "Videos already in the channel or playlist are skipped; only ones added from now on download."
                     : "New videos download automatically from now on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        guard !link.trimmingCharacters(in: .whitespaces).isEmpty, !adding else { return }
        adding = true
        error = nil
        notice = nil
        Task {
            do {
                try await subscriptions.add(link: link, quality: quality, downloadLatest: latest, folder: folder)
                link = ""
                folder = nil
            } catch {
                self.error = error.localizedDescription
            }
            adding = false
        }
    }

    static func chooseFolder(startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose where this subscription saves. Videos already in the folder won't be downloaded again."
        panel.directoryURL = start ?? Prefs.downloadFolder
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func downloadExisting(_ sub: Subscription) {
        error = nil
        notice = nil
        Task {
            do {
                let count = try await subscriptions.downloadExisting(sub.id)
                notice = count == 0
                    ? "Everything in \(sub.title) is already downloaded or in the list."
                    : "Added \(count) video\(count == 1 ? "" : "s") from \(sub.title) to Downloads."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func menu(for sub: Subscription) -> some View {
        Button("Check Now") { Task { await subscriptions.check(sub.id) } }
        Button("Download Existing Videos") { downloadExisting(sub) }
        Button(sub.enabled ? "Pause Subscription" : "Resume Subscription") {
            subscriptions.setEnabled(sub.id, !sub.enabled)
        }
        Menu("Quality") {
            ForEach(Quality.allCases) { q in
                Button {
                    subscriptions.setQuality(sub.id, q)
                } label: {
                    if sub.quality == q.rawValue { Label(q.label, systemImage: "checkmark") } else { Text(q.label) }
                }
            }
        }
        Menu("Save To") {
            Button("Choose Folder…") {
                if let url = Self.chooseFolder(startingAt: sub.folderURL) { subscriptions.setFolder(sub.id, url) }
            }
            if sub.folder != nil {
                Button("Reel's Download Folder") { subscriptions.setFolder(sub.id, nil) }
            }
        }
        Button("Show Folder in Finder") {
            let url = sub.folderURL ?? Prefs.downloadFolder
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
        Button("Open in Browser") { if let url = URL(string: sub.link) { NSWorkspace.shared.open(url) } }
        Divider()
        Button("Unsubscribe", role: .destructive) {
            subscriptions.remove(selection.contains(sub.id) ? selection : [sub.id])
        }
    }
}

private struct SubscriptionRow: View {
    let sub: Subscription
    let checking: Bool
    let downloadExisting: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: sub.thumbnailURL, width: 96, placeholder: "dot.radiowaves.left.and.right")
                .opacity(sub.enabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.title).font(.body.weight(.medium)).lineLimit(1)
                Group {
                    if let error = sub.lastError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if !sub.enabled {
                        Text("Paused")
                    } else if checking {
                        Text("Checking for new uploads…")
                    } else {
                        Text(detail)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if checking {
                ProgressView().controlSize(.small)
            } else if sub.enabled {
                Button("Download Existing", systemImage: "arrow.down.circle", action: downloadExisting)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Download the videos already in \(sub.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        var parts = [Quality(rawValue: sub.quality)?.label ?? "Best"]
        switch sub.downloadedCount {
        case 0: parts.append("waiting for new videos")
        case 1: parts.append("1 downloaded")
        default: parts.append("\(sub.downloadedCount) downloaded")
        }
        if let folder = sub.folderURL { parts.append("in \(folder.lastPathComponent)") }
        if let checked = sub.lastChecked {
            parts.append("checked \(checked.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
