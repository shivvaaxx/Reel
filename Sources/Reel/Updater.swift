import Sparkle
import SwiftUI

/// Reel's own updates (separate from its download tools), via Sparkle. Each update is
/// verified against the public key in Info.plist before it's installed.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    @Published var canCheck = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}

/// Settings rows bound straight to Sparkle's own preferences.
struct UpdateSettings: View {
    @State private var automaticChecks = Updater.shared.updater.automaticallyChecksForUpdates
    @State private var automaticDownloads = Updater.shared.updater.automaticallyDownloadsUpdates

    var body: some View {
        Toggle(isOn: $automaticChecks) {
            Text("Check for Reel updates automatically")
            Text("Reel checks once a day and shows what's new before installing.")
        }
        .onChange(of: automaticChecks) { _, on in Updater.shared.updater.automaticallyChecksForUpdates = on }
        Toggle("Download and install updates automatically", isOn: $automaticDownloads)
            .disabled(!automaticChecks)
            .onChange(of: automaticDownloads) { _, on in Updater.shared.updater.automaticallyDownloadsUpdates = on }
        LabeledContent("Version") {
            HStack {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    .monospacedDigit()
                CheckForUpdatesButton()
            }
        }
    }
}
