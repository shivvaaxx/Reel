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

    var body: some View {
        VStack(spacing: 0) {
            addBar
                .padding(20)
            if subscriptions.items.isEmpty {
                ContentUnavailableView {
                    Label("No Subscriptions", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Paste a YouTube channel or playlist link above. Reel will download new uploads as they appear.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(subscriptions.items) { sub in
                            SubscriptionRow(sub: sub, checking: subscriptions.checking.contains(sub.id))
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
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Subscribe", systemImage: "plus", action: add)
                    .buttonStyle(.glassProminent)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || adding)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        guard !link.trimmingCharacters(in: .whitespaces).isEmpty, !adding else { return }
        adding = true
        error = nil
        Task {
            do {
                try await subscriptions.add(link: link, quality: quality, downloadLatest: latest)
                link = ""
            } catch {
                self.error = error.localizedDescription
            }
            adding = false
        }
    }

    @ViewBuilder
    private func menu(for sub: Subscription) -> some View {
        Button("Check Now") { Task { await subscriptions.check(sub.id) } }
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
            if checking { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        var parts = [Quality(rawValue: sub.quality)?.label ?? "Best"]
        parts.append(sub.downloadedCount == 1 ? "1 downloaded" : "\(sub.downloadedCount) downloaded")
        if let checked = sub.lastChecked {
            parts.append("checked \(checked.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
