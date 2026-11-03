import AppKit
import SwiftUI
import UserNotifications

@MainActor
enum Shared {
    static let engine = Engine()
    static let library = Library()
    static let queue = DownloadQueue(engine: engine, library: library)
    static var openWindowAction: OpenWindowAction?

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == WindowIdentifier.id }
    }

    static func openMainWindow() {
        NSApp.activate()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?(id: "main")
        }
    }

    // MARK: Dock & menu bar presence

    static var showInDock: Bool { UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true }
    static var showInMenuBar: Bool { UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true }

    /// Applies the Dock and menu bar settings. With the Dock icon hidden the menu bar
    /// icon is always kept, so Reel can never become unreachable.
    static func applyPresence() {
        let dock = showInDock
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
        MenuBarController.shared.setVisible(showInMenuBar || !dock)
        if !dock, let window = mainWindow, window.isVisible {
            // Switching to accessory hides the app; bring the window back.
            DispatchQueue.main.async {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension Notification.Name {
    static let reelDownloadClipboard = Notification.Name("reelDownloadClipboard")
    static let reelFocusLink = Notification.Name("reelFocusLink")
    static let reelShowLibrary = Notification.Name("reelShowLibrary")
}

/// Tags the main window so AppKit code (the menu bar panel) can find it.
struct WindowIdentifier: NSViewRepresentable {
    static let id = "reel-main"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.identifier = NSUserInterfaceItemIdentifier(Self.id) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = NSUserInterfaceItemIdentifier(Self.id)
    }
}

@main
struct ReelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = Shared.engine
    @State private var queue = Shared.queue
    @State private var library = Shared.library

    var body: some Scene {
        Window("Reel", id: "main") {
            ContentView()
                .environment(engine)
                .environment(queue)
                .environment(library)
                .task {
                    await engine.prepare()
                    queue.pump()
                }
        }
        .defaultSize(width: 760, height: 680)
        .defaultLaunchBehavior(Shared.showInDock ? .presented : .suppressed)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download") {
                    Shared.openMainWindow()
                    NotificationCenter.default.post(name: .reelFocusLink, object: nil)
                }
                .keyboardShortcut("n")
                Button("Download Copied Link") {
                    NotificationCenter.default.post(name: .reelDownloadClipboard, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Downloads") {
                    Shared.openMainWindow()
                    NotificationCenter.default.post(name: .reelFocusLink, object: nil)
                }
                .keyboardShortcut("1")
                Button("Library") {
                    Shared.openMainWindow()
                    NotificationCenter.default.post(name: .reelShowLibrary, object: nil)
                }
                .keyboardShortcut("2")
                Divider()
            }
            CommandMenu("Downloads") {
                Button("Pause All") { Shared.queue.pauseAll() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Resume All") { Shared.queue.resumeAll() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Button("Clear Finished") { Shared.queue.clearFinished() }
                    .keyboardShortcut("k")
            }
            CommandGroup(replacing: .help) {
                Button("Reel on GitHub") { NSWorkspace.shared.open(Support.repository) }
                Button("Report a Problem…") {
                    NSWorkspace.shared.open(Support.repository.appendingPathComponent("issues/new"))
                }
                Divider()
                Button("Support Reel on Ko-fi…") { NSWorkspace.shared.open(Support.kofi) }
                Button("Sponsor on GitHub…") { NSWorkspace.shared.open(Support.sponsors) }
            }
        }

        Settings {
            SettingsView()
                .environment(engine)
                .environment(library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before the first window appears so a hidden Dock icon never flashes.
        MainActor.assumeIsolated {
            _ = NSApp.setActivationPolicy(Shared.showInDock ? .regular : .accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            Shared.applyPresence()
            // The window's .task normally starts setup; when launching menu-bar-only it may not exist.
            Task { @MainActor in
                await Shared.engine.prepare()
                Shared.queue.pump()
            }
            // `open -a Reel --args --download <link> [<link>…]` queues links at launch.
            let args = CommandLine.arguments
            if args.contains("--show-panel") {   // used for visual testing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MenuBarController.shared.showPanel()
                }
            }
            if let flag = args.firstIndex(of: "--download") {
                for link in args[(flag + 1)...] where link.hasPrefix("http") {
                    Shared.queue.quickAdd(link)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            !MenuBarController.shared.isVisible && Shared.queue.activeCount == 0
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { Shared.openMainWindow() } }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Nothing is lost on quit: running downloads keep their partial files and continue
        // the next time Reel opens, so no confirmation is needed.
        MainActor.assumeIsolated {
            Shared.queue.suspendAllForQuit()
        }
        return .terminateNow
    }

    // Clicking a "Download Complete" notification shows the file in Finder.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
