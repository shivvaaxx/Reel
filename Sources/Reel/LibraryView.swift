import AppKit
import SwiftUI

/// Everything Reel has downloaded: searchable, with the source link kept.
struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(DownloadQueue.self) private var queue
    @State private var search = ""
    @State private var site = "All"
    @State private var selection: Set<LibraryItem.ID> = []
    @State private var trashError: String?

    private var sites: [String] {
        ["All"] + Array(Set(library.items.map(\.site))).sorted()
    }

    private var filtered: [LibraryItem] {
        library.items.filter { item in
            (site == "All" || item.site == site)
                && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search)
                    || item.link.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        Group {
            if library.items.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "books.vertical")
                } description: {
                    Text("Everything you download appears here, even after you clear the downloads list.")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { item in
                        LibraryRow(item: item) { trash([item.id]) }
                            .tag(item.id)
                            .contextMenu { menu(for: item) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: LibraryItem.ID.self) { _ in
                } primaryAction: { ids in
                    library.items.filter { ids.contains($0.id) }.forEach { $0.open() }
                }
                .onDeleteCommand { library.remove(selection) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Library")
        .alert("Couldn't Move to Trash", isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trashError ?? "")
        }
        .safeAreaInset(edge: .top) {
            if library.items.count > 0 {
                HStack {
                    Picker("Site", selection: $site) {
                        ForEach(sites, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if library.items.contains(where: { !$0.isAvailable }) {
                        Button("Remove Missing") { library.removeMissing() }
                            .help("Remove items whose files were moved or deleted")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }

    private var summary: String {
        let count = filtered.count
        let bytes = filtered.compactMap(\.size).reduce(0, +)
        let items = count == 1 ? "1 item" : "\(count) items"
        return bytes > 0 ? "\(items) · \(bytes.byteString)" : items
    }

    @ViewBuilder
    private func menu(for item: LibraryItem) -> some View {
        Button("Open") { item.open() }.disabled(!item.isAvailable)
        Button("Show in Finder") { item.reveal() }.disabled(!item.isAvailable)
        Divider()
        Button("Open Original Page") {
            if let url = URL(string: item.link) { NSWorkspace.shared.open(url) }
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.link, forType: .string)
        }
        Button("Download Again") {
            queue.enqueue(link: item.link, title: item.title, thumbnail: item.thumbnailURL,
                          quality: Quality(rawValue: item.quality) ?? Prefs.defaultQuality,
                          kind: item.isGallery ? .gallery : .video)
            NotificationCenter.default.post(name: .reelFocusLink, object: nil)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            trash(selection.contains(item.id) ? selection : [item.id])
        }
        .disabled(!item.isAvailable)
        Button("Remove from Library") {
            let ids = selection.contains(item.id) ? selection : [item.id]
            library.remove(ids)
        }
    }

    private func trash(_ ids: Set<LibraryItem.ID>) {
        let failed = library.trash(ids)
        selection.subtract(ids)
        if !failed.isEmpty {
            trashError = "Reel couldn't move \(failed.joined(separator: ", ")) to the Trash. It may be open in another app, or in a folder you can't change."
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let trash: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: item.thumbnailURL, width: 96,
                      placeholder: item.isGallery ? "photo.on.rectangle" : "play.rectangle")
                .opacity(item.isAvailable ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.site)
                    Text("·")
                    Text(item.date, format: .dateTime.day().month().year())
                    if let size = item.size {
                        Text("·")
                        Text(size.byteString)
                    }
                    if item.isGallery {
                        Text("·")
                        Text(item.files.count == 1 ? "1 file" : "\(item.files.count) files")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if !item.isAvailable {
                    Label("File moved or deleted", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if item.isAvailable {
                HStack(spacing: 4) {
                    Button("Show in Finder", systemImage: "magnifyingglass") { item.reveal() }
                        .help("Show in Finder")
                    Button("Move to Trash", systemImage: "trash", action: trash)
                        .help("Move to Trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
