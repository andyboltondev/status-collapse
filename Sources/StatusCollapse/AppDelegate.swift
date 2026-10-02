import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: Controller!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller()
        controller.openSettings = { [weak self] in self?.showWindow() }
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

    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: RootView(controller: controller)))
            w.title = "StatusCollapse"
            w.styleMask = [.titled, .closable]
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
