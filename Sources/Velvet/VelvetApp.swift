import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep our memory footprint small: tight URL cache for artwork.
        URLCache.shared = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 64 * 1024 * 1024)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing windows never quits Velvet — it keeps playing in the
        // background. Quit only via Cmd-Q / Dock → Quit. (Exiting PiP with
        // the main window closed used to leave zero windows and terminate
        // the app, which read as a crash.)
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Dock click brings the hidden main window back.
        AppDelegate.showMainWindow()
        return false
    }

    /// Re-show the (hidden, not closed) main window.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where !(window is NSPanel) && window.contentViewController != nil {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

/// Retained target that turns the red close button into "hide": the window
/// stays alive (playback and state intact) and comes back from the Dock.
final class WindowHider: NSObject {
    static let shared = WindowHider()
    @objc func hideWindow(_ sender: Any?) {
        (sender as? NSView)?.window?.orderOut(nil)
    }
}

@main
struct VelvetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
