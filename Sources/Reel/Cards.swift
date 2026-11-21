import SwiftUI

struct Thumbnail: View {
    let url: URL?
    var width: CGFloat
    var placeholder = "play.rectangle"

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Look.Colors.cardFill)
                    .overlay {
                        Image(systemName: placeholder)
                            .font(.system(size: width / 5))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(.rect(cornerRadius: width > 120 ? Look.Radius.card : Look.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: width > 120 ? Look.Radius.card : Look.Radius.chip, style: .continuous)
                .strokeBorder(Look.Colors.hairline, lineWidth: 0.5)
        }
    }
}

struct QualityPicker: View {
    @Binding var quality: Quality

    var body: some View {
        Picker("Quality", selection: $quality) {
            ForEach(Quality.allCases.filter { $0 != .audio }) { q in
                Text(q.label).tag(q)
            }
            Divider()
            Label("Audio Only", systemImage: "music.note").tag(Quality.audio)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// A section of a video to download, in seconds (nil end = to the end).
struct Clip: Equatable {
    var start: Double?
    var end: Double?
}

/// Parses "1:23", "1:02:03", "83" or "83.5" into seconds.
enum TimeText {
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// Shown after looking up a single video.
struct VideoCard: View {
    let info: MediaInfo
    @Binding var quality: Quality
    /// Called with a clip when trimming, nil for the whole video.
    let onDownload: (Clip?) -> Void

    @State private var trimming = false
    @State private var startText = ""
    @State private var endText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Look.Spacing.md) {
            summary
            if trimming {
                trimRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(Look.Spacing.xl)
        .glassSheet()
        .animation(.smooth(duration: 0.25), value: trimming)
    }

    private var clip: Clip? {
        guard trimming else { return nil }
        let start = TimeText.seconds(startText).flatMap { $0 > 0 ? $0 : nil }
        let end = TimeText.seconds(endText).flatMap { value in
            info.duration.map { value < $0 - 0.5 } ?? true ? value : nil
        }
        return start == nil && end == nil ? nil : Clip(start: start, end: end)
    }

    private var clipIsValid: Bool {
        guard trimming else { return true }
        if !startText.isEmpty, TimeText.seconds(startText) == nil { return false }
        if !endText.isEmpty, TimeText.seconds(endText) == nil { return false }
        if let c = clip, let s = c.start, let e = c.end, e <= s { return false }
        if let c = clip, let s = c.start, let d = info.duration, s >= d { return false }
        return true
    }

    private var trimRow: some View {
        HStack(spacing: Look.Spacing.sm) {
            Image(systemName: "scissors").foregroundStyle(.secondary)
            Text("From")
            TextField("0:00", text: $startText)
                .textFieldStyle(.plain)
                .padding(.horizontal, Look.Spacing.sm)
                .frame(width: 80, height: 28)
                .quietCard(cornerRadius: Look.Radius.chip)
                .monospacedDigit()
            Text("to")
            TextField(info.duration?.clockString ?? "end", text: $endText)
                .textFieldStyle(.plain)
                .padding(.horizontal, Look.Spacing.sm)
                .frame(width: 80, height: 28)
                .quietCard(cornerRadius: Look.Radius.chip)
                .monospacedDigit()
            if !clipIsValid {
                Label("Check the times", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if let c = clip {
                Text(clipLength(c))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func clipLength(_ c: Clip) -> String {
        let end = c.end ?? info.duration
        guard let end else { return "" }
        return "\((end - (c.start ?? 0)).clockString) long"
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Look.Spacing.lg) {
            Thumbnail(url: info.thumbnail, width: 208)
                .overlay(alignment: .bottomTrailing) {
                    if let duration = info.duration {
                        Text(duration.clockString)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: .capsule)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: Look.Spacing.sm) {
                Text(info.title)
                    .font(Look.Typography.titleSmall)
                    .lineLimit(2)
                if let uploader = info.uploader {
                    Text(uploader)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Look.Spacing.md)
                HStack(spacing: Look.Spacing.sm) {
                    QualityPicker(quality: $quality)
                    Button { trimming.toggle() } label: { Label("Trim", systemImage: "scissors") }
                    .buttonStyle(.quietChip(selected: trimming))
                    .help("Download only part of the video")
                    .disabled(info.isLive)
                    Spacer()
                    Button {
                        onDownload(clip)
                    } label: {
                        Label(clip == nil ? "Download" : "Download Clip", systemImage: "arrow.down")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!clipIsValid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 117)
    }
}

/// Shown for photo posts (Instagram posts, TikTok photo slideshows).
struct GalleryCard: View {
    let link: String
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: Look.Spacing.lg) {
            RoundedRectangle(cornerRadius: Look.Radius.card, style: .continuous)
                .fill(Look.Colors.cardFill)
                .frame(width: 112, height: 63)
                .overlay {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            VStack(alignment: .leading, spacing: Look.Spacing.hair) {
                Text("\(Prefs.siteName(for: link)) Post")
                    .font(Look.Typography.titleSmall)
                Text("Saves every photo and video in the post.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Look.Spacing.xl)
        .glassSheet()
    }
}

/// Shown after looking up a playlist: pick which videos to download.
struct PlaylistCard: View {
    let info: MediaInfo
    @Binding var quality: Quality
    @Binding var selection: Set<String>
    /// Entries already in the Library.
    var downloaded: Set<String> = []
    let onDownload: () -> Void

    private var allSelected: Bool { selection.count == info.entries.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Look.Spacing.md) {
            HStack(spacing: Look.Spacing.md) {
                Thumbnail(url: info.thumbnail, width: 112)
                VStack(alignment: .leading, spacing: Look.Spacing.hair) {
                    Text(info.title)
                        .font(Look.Typography.titleSmall)
                        .lineLimit(1)
                    Text(countText)
                        .foregroundStyle(.secondary)
                    if let uploader = info.uploader {
                        Text(uploader).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(info.entries.map(\.id))
                }
                .buttonStyle(.quietChip)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(info.entries.enumerated()), id: \.element.id) { index, entry in
                        Toggle(isOn: binding(for: entry.id)) {
                            HStack(spacing: Look.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(entry.title).lineLimit(1)
                                Spacer()
                                if downloaded.contains(entry.id) {
                                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                if let duration = entry.duration {
                                    Text(duration.clockString)
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxHeight: 200)
            .quietCard()

            HStack(spacing: Look.Spacing.sm) {
                QualityPicker(quality: $quality)
                Spacer()
                Button(action: onDownload) {
                    Label(selection.count == 1 ? "Download 1 Video" : "Download \(selection.count) Videos",
                          systemImage: "arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(Look.Spacing.xl)
        .glassSheet()
    }

    private var countText: String {
        let total = info.entries.count == 1 ? "1 video" : "\(info.entries.count) videos"
        let done = info.entries.filter { downloaded.contains($0.id) }.count
        return done > 0 ? "\(total) · \(done) already downloaded" : total
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }
}
