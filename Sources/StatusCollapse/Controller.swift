import AppKit
import Observation
import ServiceManagement

/// How the collapse button is drawn. `native` matches the double chevron macOS itself uses for
/// its menu bar overflow control.
enum IconStyle: String, CaseIterable, Identifiable {
    case native, chevron, arrow, eye

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: "Native (double chevron)"
        case .chevron: "Chevron"
        case .arrow: "Arrow"
        case .eye: "Eye"
        }
    }

    /// SF Symbol for the given state. Collapsed points left, expanded points right.
    func symbol(collapsed: Bool) -> String {
        switch self {
        case .native: collapsed ? "chevron.left.2" : "chevron.right.2"
        case .chevron: collapsed ? "chevron.left" : "chevron.right"
        case .arrow: collapsed ? "arrow.left" : "arrow.right"
        case .eye: collapsed ? "eye.slash" : "eye"
        }
    }

    /// Directional glyphs flip by rotating; the eye cross-fades.
    var rotates: Bool { self != .eye }
}

/// Owns the two menu bar items and the collapse state.
///
/// macOS lays status items out right-to-left and lets users Cmd-drag them. There are two items:
/// the button, and a slim divider to its left that is only drawn while expanded. Collapsing makes
/// the divider too wide to fit anywhere, so macOS 27 hides it together with every icon to its
/// left. The button itself never changes size, so it can never be pushed out. Anything right of
/// the divider (the button, Control Center, the clock, ...) is never touched.
@MainActor
@Observable
final class Controller {
    static let autoHideChoices = [0, 5, 10, 30, 60]
    /// Bumped when setup gains steps existing users need to see (v2: the divider).
    static let setupKey = "setupCompleteV2"

    private(set) var isCollapsed: Bool
    var autoHideSeconds: Int {
        didSet { defaults.set(autoHideSeconds, forKey: "autoHideSeconds"); updateAutoHide() }
    }
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var launchError: String?
    var iconStyle: IconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: "iconStyle"); stopFlip(); render() }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var button: NSStatusItem?
    @ObservationIgnored private var divider: NSStatusItem?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private var pointerInMenuBar = false
    /// Whether to hide the icons again when the settings window closes; nil while it is closed.
    @ObservationIgnored private var collapseAfterSettings: Bool?
    @ObservationIgnored private var roleCheckTask: Task<Void, Never>?
    @ObservationIgnored private var dividerPlaced = false
    @ObservationIgnored private var placementTask: Task<Void, Never>?
    @ObservationIgnored private var flip: (link: CADisplayLink, start: CFTimeInterval)?
    /// Autosave names are versioned so "Reset Layout" can discard saved positions.
    @ObservationIgnored private var layoutVersion: Int { defaults.integer(forKey: "layoutVersion") }
    @ObservationIgnored var openSettings: () -> Void = {}

    private static let flipDuration: CFTimeInterval = 0.24

    init() {
        isCollapsed = defaults.bool(forKey: "collapsed")
        autoHideSeconds = defaults.integer(forKey: "autoHideSeconds")
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .native

        createItems()
        render()
        updateAutoHide()

        let center = NotificationCenter.default
        // The collapsed width depends on the displays attached.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        })
        // The user may Cmd-drag the button left of the divider; swap roles so it never hides itself.
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            let moved = ObjectIdentifier(window)
            MainActor.assumeIsolated {
                guard let self else { return }
                let ours = [self.button, self.divider].compactMap { $0?.button?.window.map(ObjectIdentifier.init) }
                if ours.contains(moved) { self.scheduleRoleCheck() }
            }
        })
    }

    /// Checks roles once the menu bar has settled, so a mid-drag or mid-layout frame can't swap them.
    private func scheduleRoleCheck() {
        roleCheckTask?.cancel()
        roleCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if NSEvent.pressedMouseButtons != 0 { return self.scheduleRoleCheck() }
            self.assignRoles()
        }
    }

    // MARK: Collapse

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return updateAutoHide() }
        if collapsed { assignRoles() }
        isCollapsed = collapsed
        defaults.set(collapsed, forKey: "collapsed")
        render(animated: true)
        updateAutoHide()
    }

    /// Icons stay shown while the settings window is open so they're easy to arrange; closing it
    /// puts back the state it was opened from.
    func settingsWillOpen() {
        guard collapseAfterSettings == nil else { return }
        collapseAfterSettings = isCollapsed
        setCollapsed(false)
    }

    func settingsDidClose() {
        guard let collapse = collapseAfterSettings else { return }
        collapseAfterSettings = nil
        if collapse { setCollapsed(true) } else { updateAutoHide() }
    }

    func resetLayout() {
        defaults.set(layoutVersion + 1, forKey: "layoutVersion")
        defaults.set(false, forKey: "rolesSwapped")
        isCollapsed = false
        defaults.set(false, forKey: "collapsed")
        stopFlip()
        for item in [button, divider].compactMap(\.self) { NSStatusBar.system.removeStatusItem(item) }
        createItems()
        render()
    }

    private func render(animated: Bool = false) {
        guard let button = button?.button, let divider else { return }
        let label = isCollapsed ? "Show hidden menu bar icons" : "Hide menu bar icons"
        button.toolTip = label
        button.setAccessibilityLabel(label)
        divider.button?.toolTip = "Icons left of this divider are hidden when collapsed"
        divider.button?.setAccessibilityLabel("StatusCollapse divider")

        if isCollapsed {
            divider.button?.image = nil
            divider.length = dividerPlaced ? collapsedLength : NSStatusItem.variableLength
        } else {
            divider.length = NSStatusItem.variableLength
            divider.button?.image = Self.dividerImage
        }

        switch (animated, flip) {
        case (true, nil):
            let link = button.displayLink(target: self, selector: #selector(flipStep(_:)))
            link.add(to: .main, forMode: .common)
            flip = (link, CACurrentMediaTime())
        case (true, let running?):
            // Reversed mid-flip: continue from the mirrored point so the glyph doesn't jump.
            let elapsed = CACurrentMediaTime() - running.start
            flip?.start = CACurrentMediaTime() - max(0, Self.flipDuration - elapsed)
        case (false, nil):
            button.image = glyph(progress: 1)
        case (false, _?):
            break // The running flip already draws toward the current state.
        }
    }

    /// macOS 27 ejects any item whose window (length plus 16 pt of chrome) reaches half the width
    /// of the narrowest display, which would un-hide everything. Just under that, the divider is
    /// too wide to fit or to be parked behind the system overflow chevron, so macOS hides it and
    /// every item to its left, with or without a notch.
    private var collapsedLength: CGFloat {
        let narrowest = NSScreen.screens.map(\.frame.width).min() ?? 1440
        return (narrowest / 2 - 17).rounded(.down)
    }

    /// Whichever of our two items is further left must be the divider, otherwise collapsing would
    /// hide the button along with the icons. Only meaningful while expanded and both are on screen.
    private func assignRoles() {
        guard !isCollapsed, let button, let divider,
              let buttonWindow = button.button?.window, let dividerWindow = divider.button?.window,
              buttonWindow.screen != nil, dividerWindow.screen != nil,
              buttonWindow.frame.minX < dividerWindow.frame.minX
        else { return }
        stopFlip()
        (self.button, self.divider) = (divider, button)
        defaults.set(!defaults.bool(forKey: "rolesSwapped"), forKey: "rolesSwapped")
        render()
    }

    private func createItems() {
        // The button is created first so that, for a fresh layout, the divider lands just left of it.
        let first = makeItem(autosaveName: "button\(layoutVersion)")
        let second = makeItem(autosaveName: "divider\(layoutVersion)")
        (button, divider) = defaults.bool(forKey: "rolesSwapped") ? (second, first) : (first, second)
        awaitDividerPlacement()
    }

    /// macOS ejects a brand-new item that is already too wide to fit, instead of letting it hide
    /// anything, so a new divider stays narrow until it has been given its spot in the menu bar.
    private func awaitDividerPlacement() {
        dividerPlaced = false
        placementTask?.cancel()
        placementTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(50))
                if let window = self?.divider?.button?.window, let screen = window.screen,
                   window.frame.minX > 0, window.frame.maxY >= screen.frame.maxY - 1 { break }
            }
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled else { return }
            self.dividerPlaced = true
            self.render()
        }
    }

    private func makeItem(autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        return item
    }

    // MARK: Glyph

    /// The button's image `progress` of the way from the other state's glyph to this state's.
    /// Directional glyphs rotate a quarter turn out and the new glyph a quarter turn in (they
    /// coincide at 90°); the eye cross-fades. Drawn on a fixed canvas so the width never changes.
    private func glyph(progress: CGFloat) -> NSImage? {
        let label = isCollapsed ? "Show hidden menu bar icons" : "Hide menu bar icons"
        guard let from = NSImage(systemSymbolName: iconStyle.symbol(collapsed: !isCollapsed), accessibilityDescription: nil),
              let to = NSImage(systemSymbolName: iconStyle.symbol(collapsed: isCollapsed), accessibilityDescription: label)
        else { return nil }
        if progress >= 1 { return to }

        let width = max(from.size.width, to.size.width)
        let size = NSSize(width: width, height: max(width, from.size.height, to.size.height))
        let rotates = iconStyle.rotates
        // Collapsing turns clockwise, expanding turns back.
        let sign: CGFloat = isCollapsed ? -1 : 1
        let image = NSImage(size: size, flipped: false) { rect in
            func draw(_ glyph: NSImage, degrees: CGFloat, alpha: CGFloat) {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                transform.rotate(byDegrees: degrees)
                transform.concat()
                let origin = NSPoint(x: -glyph.size.width / 2, y: -glyph.size.height / 2)
                glyph.draw(in: NSRect(origin: origin, size: glyph.size), from: .zero, operation: .sourceOver, fraction: alpha)
                NSGraphicsContext.restoreGraphicsState()
            }
            if rotates {
                if progress < 0.5 {
                    draw(from, degrees: sign * 180 * progress, alpha: 1)
                } else {
                    draw(to, degrees: -sign * 180 * (1 - progress), alpha: 1)
                }
            } else {
                draw(from, degrees: 0, alpha: 1 - progress)
                draw(to, degrees: 0, alpha: progress)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }

    @objc private func flipStep(_ link: CADisplayLink) {
        guard let flip else { return }
        let t = min(1, (CACurrentMediaTime() - flip.start) / Self.flipDuration)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        button?.button?.image = glyph(progress: eased)
        if t >= 1 { stopFlip() }
    }

    private func stopFlip() {
        flip?.link.invalidate()
        flip = nil
    }

    /// A slim, softly tinted vertical rule marking where hiding begins.
    private static let dividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1, width: 1.5, height: rect.height - 2),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Icons left of this divider are hidden when collapsed"
        return image
    }()

    // MARK: Auto-hide

    /// Auto-hide counts down only while the pointer is away from the menu bar: moving out starts
    /// the countdown, moving back in cancels it. The pointer is only watched while it matters.
    private func updateAutoHide() {
        autoHideTask?.cancel()
        guard !isCollapsed, autoHideSeconds > 0, collapseAfterSettings == nil else {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors = []
            return
        }
        if mouseMonitors.isEmpty {
            let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            mouseMonitors = [
                NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pointerMoved() }
                },
                NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                    self?.pointerMoved()
                    return event
                },
            ].compactMap(\.self)
        }
        pointerInMenuBar = Self.pointerInMenuBar
        if !pointerInMenuBar { startCountdown() }
    }

    private func pointerMoved() {
        let inside = Self.pointerInMenuBar
        guard inside != pointerInMenuBar else { return }
        pointerInMenuBar = inside
        if inside { autoHideTask?.cancel() } else { startCountdown() }
    }

    private func startCountdown() {
        autoHideTask?.cancel()
        let seconds = autoHideSeconds
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            // A menu left open still counts as use: wait it out, then count down afresh rather
            // than snapping shut the moment it closes.
            var waited = false
            while !Task.isCancelled, Self.menuIsOpen {
                waited = true
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self, !Task.isCancelled else { return }
            if waited { self.startCountdown() } else { self.setCollapsed(true) }
        }
    }

    /// True while the pointer is over the menu bar of whichever display it is on.
    private static var pointerInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return false }
        let barHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top,
                            screen.frame.maxY - screen.visibleFrame.maxY)
        return mouse.y >= screen.frame.maxY - barHeight
    }

    /// True while any app has a menu open.
    private static var menuIsOpen: Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowLayer as String] as? Int == menuLevel }
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Status item interaction

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
        } else if !event.modifierFlags.contains(.command) {
            // Cmd is held while rearranging items; dropping one shouldn't toggle.
            setCollapsed(!isCollapsed)
        }
    }

    private func showMenu(from sender: NSStatusBarButton) {
        guard let item = [button, divider].compactMap(\.self).first(where: { $0.button === sender }) else { return }
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(settingsChosen), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StatusCollapse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        // Attach only for this click so left-click keeps toggling.
        item.menu = menu
        sender.performClick(nil)
        item.menu = nil
    }

    @objc private func settingsChosen() { openSettings() }
}
