import AppKit
import SwiftUI

struct DownloadRow: View {
    @Environment(DownloadQueue.self) private var queue
    let job: DownloadJob
    @State private var showingLog = false

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: job.thumbnail, width: 104, placeholder: job.kind == .gallery ? "photo.on.rectangle" : "play.rectangle")
                .overlay {
                    if job.status == .finished && job.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .opacity(0.9)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if job.showsProgressBar {
                    if let value = job.barValue {
                        ProgressView(value: value).progressViewStyle(.linear)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }

                Text(job.statusLine)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(job.isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            JobControls(job: job, size: .title2)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture(count: 2) { job.open() }
        .contextMenu { JobMenu(job: job, showingLog: $showingLog) }
        .popover(isPresented: $showingLog) { LogView(lines: job.log) }
    }
}

/// Pause / resume / cancel / retry / reveal buttons for a job.
struct JobControls: View {
    @Environment(DownloadQueue.self) private var queue
    let job: DownloadJob
    var size: Font = .title2

    var body: some View {
        HStack(spacing: 6) {
            switch job.status {
            case .resolving:
                button("xmark.circle.fill", help: "Cancel") { queue.cancel(job) }
            case .queued, .starting, .downloading:
                if job.kind == .video {
                    button("pause.circle.fill", help: "Pause") { queue.pause(job) }
                        .disabled(!job.canPause)
                }
                button("xmark.circle.fill", help: "Cancel") { queue.cancel(job) }
            case .processing:
                button("xmark.circle.fill", help: "Cancel") { queue.cancel(job) }
            case .paused:
                button("arrow.down.circle.fill", help: "Resume") { queue.resume(job) }
                button("xmark.circle.fill", help: "Cancel") { queue.cancel(job) }
            case .finished:
                button("magnifyingglass.circle.fill", help: "Show in Finder") { job.reveal() }
            case .failed, .cancelled:
                button("arrow.clockwise.circle.fill", help: "Try Again") { queue.retry(job) }
                button("minus.circle.fill", help: "Remove") { withAnimation { queue.remove(job) } }
            }
        }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(size)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct JobMenu: View {
    @Environment(DownloadQueue.self) private var queue
    let job: DownloadJob
    @Binding var showingLog: Bool

    var body: some View {
        if job.status == .finished {
            Button("Open") { job.open() }
            Button("Show in Finder") { job.reveal() }
            Divider()
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.link, forType: .string)
        }
        Button("Show Log") { showingLog = true }
            .disabled(job.log.isEmpty)
        if job.isFinishedOrStopped {
            Button("Download Again") { queue.retry(job) }
        }
        Divider()
        Button("Remove from List", role: .destructive) { withAnimation { queue.remove(job) } }
    }
}

struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            Text(lines.filter { !$0.hasPrefix("@@") }.joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(width: 520, height: 300)
    }
}
