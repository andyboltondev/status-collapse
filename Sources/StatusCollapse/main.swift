import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // No Dock icon or app menu. LSUIElement in Info.plist does this for the bundled app; this
    // also covers running the bare executable, e.g. with `swift run`.
    app.setActivationPolicy(.accessory)
    // NSApplication holds its delegate weakly, so keep it alive for as long as the app runs.
    withExtendedLifetime(delegate) { app.run() }
}
