import AppKit
import ApplicationServices

/// Keeps the empty menu bar beside the button inert while the icons are hidden.
///
/// macOS ejects a status item from any display it is wider than half of, and a display without a
/// notch has more free menu bar than that, so on such a display one hider still fits beside the
/// button. It draws nothing, but macOS 27 draws its own pressed highlight over any status item
/// that is pressed, whatever the item asks for, which showed as a long empty pill. So while the
/// pointer is over a hider, a clear window covers it and takes the press, as empty menu bar would.
///
/// Only a hider that is on screen gets hover events, so one arriving is what says a hider fits;
/// nothing is covered on a guess. The event's own position can't place the cover, as macOS slides
/// a hider into place and the pointer can meet it on the way, but the hider's window already has
/// its final frame. That frame is stale for a hider that doesn't fit, so it is only used when it
/// is on the pointer's display and ends where the button starts, as a hider that fits always does.
///
/// macOS only sends those hover events for the display whose menu bar is active, and the app's own
/// windows don't say where its items are on the others. MenuBarAgent, which lays out every
/// display's menu bar, does say, through Accessibility. So with the setting on and Accessibility
/// allowed, the cover goes over a hider on any display. Otherwise the first press on a hider on
/// another display still shows the highlight, makes that display's menu bar the active one, and
/// the cover takes over from then on.
@MainActor
final class MenuBarShield: NSResponder {
    /// The button's window, which the hiders that fit sit against.
    var buttonWindow: () -> NSWindow? = { nil }
    /// Whether the icons are hidden, the only time a hider can be on screen.
    var hidingIcons = false {
        didSet { if hidingIcons != oldValue { updateOtherDisplays() } }
    }
    /// Whether to ask MenuBarAgent where the hiders are on other displays, which needs
    /// Accessibility and the user's say-so.
    var usesAccessibility = false {
        didSet { if usesAccessibility != oldValue { updateOtherDisplays() } }
    }

    private let panel: NSPanel
    /// The hider the cover was last put over, so the cover can follow it.
    private weak var covered: NSWindow?
    /// Lifts the cover once the pointer leaves it; runs only while it is up.
    private var exitWatch: Task<Void, Never>?
    private static let exitTick = Duration.milliseconds(50)
    private let hiders = NSHashTable<NSWindow>.weakObjects()

    /// Watches the pointer for other displays' menu bars; see `coverOnOtherDisplay`.
    private var pointerMonitor: Any?
    /// Where MenuBarAgent last said the hiders are on a display, and when, so the pointer moving
    /// along a menu bar doesn't ask again on every move.
    private var lastLook: (screen: NSRect, spans: [NSRect], time: ContinuousClock.Instant)?
    private var looking = false
    private static let lookFreshness = Duration.milliseconds(500)
    /// The top of each display, taller than any menu bar. The pointer moves often, so it is checked
    /// against these, kept from when the displays last changed, before anything else.
    private var menuBarBands: [NSRect] = []
    private static let maxBarHeight: CGFloat = 60

    override init() {
        panel = ShieldPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Just above the menu bar and its items, below menus.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Panels zoom in and out by default, which would leave the hider's edges bare at first.
        panel.animationBehavior = .none
        // A clear window lets clicks through unless told otherwise.
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // The menu bar shows on every space, including over full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = ShieldView()
        view.setAccessibilityElement(false)
        panel.contentView = view
        super.init()
        // The cover stops the hider's hover events, so when it or the button moves, as when
        // another item appears or the active display changes, the cover follows or goes.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let moved = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    guard let self, let covered = self.covered,
                          self.hiders.contains(moved) || moved === self.buttonWindow() else { return }
                    self.cover(covered)
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts watching `hider` for the pointer.
    func watch(_ hider: NSStatusItem) {
        if let window = hider.button?.window { hiders.add(window) }
        hider.button?.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    /// Takes the cover away, for when the hiders or the menu bar may have changed under it.
    func lift() {
        exitWatch?.cancel()
        exitWatch = nil
        covered = nil
        lastLook = nil
        panel.orderOut(nil)
    }

    /// Starts or stops watching other displays' menu bars, for when the displays may have changed.
    func updateOtherDisplays() {
        let screens = NSScreen.screens
        menuBarBands = screens.map { NSRect(x: $0.frame.minX, y: $0.frame.maxY - Self.maxBarHeight,
                                            width: $0.frame.width, height: Self.maxBarHeight) }
        let wanted = hidingIcons && usesAccessibility && screens.count > 1
        if wanted, pointerMonitor == nil {
            pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.coverOnOtherDisplay() }
            }
        } else if !wanted, let monitor = pointerMonitor {
            NSEvent.removeMonitor(monitor)
            pointerMonitor = nil
        }
    }

    override func mouseEntered(with event: NSEvent) { event.window.map(cover) }
    // Also after a lift while the pointer stayed put, as when another app came to the front.
    override func mouseMoved(with event: NSEvent) { if !panel.isVisible { event.window.map(cover) } }
    // Covering the hider is itself an exit; the cover watches for the pointer leaving instead.
    override func mouseExited(with event: NSEvent) {}

    /// Covers `hider` and any hiders between it and the button, which fit too, or lifts the cover
    /// if that can't be done exactly. Only the hider's left and right edges are used: its window
    /// can sit a little higher or lower than the button's, as after the active display changes.
    private func cover(_ hider: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let button = buttonWindow()?.frame, let screen = Self.screen(containing: mouse),
              screen.frame.contains(hider.frame.center), screen.frame.contains(button.center),
              hider.frame.maxX <= button.minX + 0.5, let bar = Self.menuBar(containing: mouse)
        else { return lift() }
        let span = NSRect(x: hider.frame.minX, y: bar.minY, width: button.minX - hider.frame.minX, height: bar.height)
        guard bar.contains(span), NSMouseInRect(mouse, span, false) else { return lift() }
        covered = hider
        show(span)
    }

    /// While the pointer is on the menu bar of a display whose menu bar isn't active, covers the
    /// hider under it, from where MenuBarAgent says the hiders are on that display.
    private func coverOnOtherDisplay() {
        let mouse = NSEvent.mouseLocation
        guard menuBarBands.contains(where: { NSMouseInRect(mouse, $0, false) }), !panel.isVisible, !looking,
              let screen = Self.screen(containing: mouse),
              // On the active display, the hiders' own hover events do this.
              let button = buttonWindow()?.frame, !screen.frame.contains(button.center),
              let hiderWidth = hiders.anyObject?.frame.width
        else { return }
        if let look = lastLook, look.screen == screen.frame, ContinuousClock.now - look.time < Self.lookFreshness {
            if let span = look.spans.first(where: { NSMouseInRect(mouse, $0, false) }) { show(span) }
            return
        }
        looking = true
        let frame = screen.frame
        Task { [weak self] in
            let spans = await Self.hiderSpans(on: frame, hiderWidth: hiderWidth)
            guard let self else { return }
            looking = false
            lastLook = (frame, spans, .now)
            coverOnOtherDisplay()
        }
    }

    private func show(_ span: NSRect) {
        panel.setFrame(span, display: false)
        panel.orderFrontRegardless()
        guard exitWatch == nil else { return }
        exitWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.exitTick, tolerance: Self.exitTick / 2)
                guard let self, !Task.isCancelled else { return }
                if !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) { return lift() }
            }
        }
    }

    /// The frames of this app's hiders in the menu bar of the display at `screen`, as MenuBarAgent
    /// lays them out. Its Accessibility tree has a window for each display's menu bar, holding an
    /// element for each item placed there, inside which is the app that owns it. Asked off the main
    /// thread and with a short timeout, so a busy MenuBarAgent can't hold up the app.
    private nonisolated static func hiderSpans(on screen: NSRect, hiderWidth: CGFloat) async -> [NSRect] {
        await Task.detached(priority: .userInitiated) {
            guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first,
                  let top = await MainActor.run(body: { NSScreen.screens.first?.frame.maxY })
            else { return [] }
            let ours = ProcessInfo.processInfo.processIdentifier
            let app = AXUIElementCreateApplication(agent.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.25)
            // Accessibility measures down from the top of the main display.
            func cocoa(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
            var spans: [NSRect] = []
            for bar in children(app, kAXWindowsAttribute) {
                guard let barFrame = frame(bar).map(cocoa), abs(barFrame.minX - screen.minX) < 1,
                      abs(barFrame.maxY - screen.maxY) < 1 else { continue }
                for item in children(bar, kAXChildrenAttribute) {
                    guard let owner = children(item, kAXChildrenAttribute).first, let itemFrame = frame(item) else { continue }
                    var pid: pid_t = 0
                    AXUIElementGetPid(owner, &pid)
                    if pid == ours, abs(itemFrame.width - hiderWidth) < 0.5 { spans.append(cocoa(itemFrame)) }
                }
            }
            return spans
        }.value
    }

    private nonisolated static func children(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private nonisolated static func frame(_ element: AXUIElement) -> CGRect? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// The menu bar under `point`, from the menu bar windows the window server keeps for each
    /// display. Only window bounds are read, which needs no Screen Recording permission.
    private static func menuBar(containing point: NSPoint) -> NSRect? {
        // Window bounds are measured down from the top of the main display.
        guard let top = NSScreen.screens.first?.frame.maxY, let screen = screen(containing: point) else { return nil }
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos where info[kCGWindowLayer as String] as? Int == level {
            guard let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }) else { continue }
            let frame = NSRect(x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
            // The whole bar of the pointer's display, not some other window at that level.
            if frame.width == screen.frame.width, NSMouseInRect(point, frame, false) { return frame }
        }
        return nil
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

private final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes presses and does nothing with them, like empty menu bar.
private final class ShieldView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}
