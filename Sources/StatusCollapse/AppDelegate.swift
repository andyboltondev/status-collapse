import AppKit
import SwiftUI

/// Starts the controller at launch and owns the settings window, which hosts the SwiftUI views.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Created once launching finishes, since it adds its menu bar item straight away.
    private var controller: Controller!
    /// Created the first time settings are shown, then reused.
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller()
        controller.openSettings = { [weak self] in self?.showWindow() }        // First launch, or setup has gained steps since the user last finished it.
        if !UserDefaults.standard.bool(forKey: Controller.setupKey) { showWindow() }
    }

    /// Quitting with the window open still restores the state it was opened from.
    func applicationWillTerminate(_ notification: Notification) {
        controller.settingsDidClose()
    }

    func windowWillClose(_ notification: Notification) {
        controller.settingsDidClose()
    }

    /// Re-opening the app (e.g. from Finder) brings up settings, since there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// Brings the settings window (the setup wizard until it is finished) in front of other apps.
    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: RootView(controller: controller)))
            w.title = "StatusCollapse"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        controller.settingsWillOpen()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
