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
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: placeholder)
                            .font(.system(size: width / 5))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(.rect(cornerRadius: width > 120 ? 12 : 7))
        .overlay {
            RoundedRectangle(cornerRadius: width > 120 ? 12 : 7)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
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

/// Shown after looking up a single video.
struct VideoCard: View {
    let info: MediaInfo
    @Binding var quality: Quality
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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

            VStack(alignment: .leading, spacing: 6) {
                Text(info.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let uploader = info.uploader {
                    Text(uploader)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    QualityPicker(quality: $quality)
                    Spacer()
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 117)
        .padding(16)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
    }
}

/// Shown for photo posts (Instagram posts, TikTok photo slideshows).
struct GalleryCard: View {
    let link: String
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 112, height: 63)
                .overlay {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Prefs.siteName(for: link)) Post")
                    .font(.title3.weight(.semibold))
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
        .padding(16)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
    }
}

/// Shown after looking up a playlist: pick which videos to download.
struct PlaylistCard: View {
    let info: MediaInfo
    @Binding var quality: Quality
    @Binding var selection: Set<String>
    let onDownload: () -> Void

    private var allSelected: Bool { selection.count == info.entries.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Thumbnail(url: info.thumbnail, width: 112)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(info.entries.count == 1 ? "1 video" : "\(info.entries.count) videos")
                        .foregroundStyle(.secondary)
                    if let uploader = info.uploader {
                        Text(uploader).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(info.entries.map(\.id))
                }
                .buttonStyle(.link)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(info.entries.enumerated()), id: \.element.id) { index, entry in
                        Toggle(isOn: binding(for: entry.id)) {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(entry.title).lineLimit(1)
                                Spacer()
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
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 10))

            HStack(spacing: 10) {
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
        .padding(16)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
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
