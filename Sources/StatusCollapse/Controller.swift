import AppKit
import Observation
import ServiceManagement
import Symbols

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
}

/// Owns the menu bar button and the collapse state.
///
/// macOS lays status items out right-to-left and lets users Cmd-drag them. Collapsing adds a
/// second, invisible item, the hider, under the button's autosave name: macOS 27 puts an item
/// whose name is already taken just left of the item that owns it, and keeps it there when the
/// button is dragged. The hider is then made too wide to fit anywhere, so macOS hides it together
/// with every icon to its left. The button itself never changes size, so it can never be pushed
/// out, and anything right of it (Control Center, the clock, ...) is never touched. Expanding
/// removes the hider, so it takes up no room while the icons are shown.
@MainActor
@Observable
final class Controller {
    static let autoHideChoices = [0, 5, 10, 30, 60]
    /// Bumped when setup gains steps existing users need to see (v3: no divider, everything left
    /// of the button hides).
    static let setupKey = "setupCompleteV3"

    private(set) var isCollapsed: Bool
    var autoHideSeconds: Int {
        didSet { defaults.set(autoHideSeconds, forKey: "autoHideSeconds"); updateAutoHide() }
    }
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var launchError: String?
    var iconStyle: IconStyle {
        didSet {
            defaults.set(iconStyle.rawValue, forKey: "iconStyle")
            button?.button?.image = Self.placeholder(for: iconStyle)
            render()
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var button: NSStatusItem?
    /// Draws the button's glyph, since only an image view can play the system's symbol
    /// transitions. It renders the same as the button's own image would.
    @ObservationIgnored private let glyphView = GlyphView()
    /// Only exists while collapsed.
    @ObservationIgnored private var hider: NSStatusItem?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    /// Whether to hide the icons again when the settings window closes; nil while it is closed.
    @ObservationIgnored private var collapseAfterSettings: Bool?
    /// Autosave names are versioned so "Reset Layout" can discard the saved position.
    @ObservationIgnored private var layoutVersion: Int { defaults.integer(forKey: "layoutVersion") }
    /// Older versions could swap the button with their divider, so the button may own that name.
    @ObservationIgnored private var buttonName: String {
        (defaults.bool(forKey: "rolesSwapped") ? "divider" : "button") + "\(layoutVersion)"
    }
    @ObservationIgnored var openSettings: () -> Void = {}

    /// macOS fades the icons in over ~200 ms but out over ~150 ms, most of it up front, and that
    /// can't be changed from here. So expanding plays the glyph's transition sped up to land with
    /// the fade-in, while collapsing plays it at the system's pace and hides the icons a beat
    /// after it starts: the old glyph shrinks away with the icons and the new one settles after.
    private static let expandSpeed = 1.4
    private static let collapseSpeed = 1.0
    private static let hideDelay = Duration.milliseconds(50)
    private static let autoHideTick = Duration.milliseconds(500)

    init() {
        isCollapsed = defaults.bool(forKey: "collapsed")
        autoHideSeconds = defaults.integer(forKey: "autoHideSeconds")
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .native

        createButton()
        render()
        updateAutoHide()

        // The collapsed width depends on the displays attached.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    // MARK: Collapse

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return updateAutoHide() }
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
        removeHider()
        if let button { NSStatusBar.system.removeStatusItem(button) }
        createButton()
        render()
    }

    private func render(animated: Bool = false) {
        guard let button = button?.button else { return }
        let label = isCollapsed ? "Show hidden menu bar icons" : "Hide menu bar icons"
        button.toolTip = label
        button.setAccessibilityLabel(label)

        hideTask?.cancel()
        if !isCollapsed {
            removeHider()
        } else if animated {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hideDelay)
                if !Task.isCancelled { self?.showHider() }
            }
        } else {
            showHider()
        }

        guard let glyph = NSImage(systemSymbolName: iconStyle.symbol(collapsed: isCollapsed), accessibilityDescription: nil)
        else { return }
        if animated {
            // Magic Replace draws the eye's slash on and off; the arrows and chevrons have nothing
            // to morph, so they use the standard Replace, layer by layer. Both retarget smoothly
            // if clicked again mid-transition.
            glyphView.setSymbolImage(glyph, contentTransition: .replace.magic(fallback: .replace.downUp.byLayer),
                                     options: .speed(isCollapsed ? Self.collapseSpeed : Self.expandSpeed))
        } else {
            glyphView.image = glyph
        }
    }

    /// macOS 27 ejects any item whose window (length plus 16 pt of chrome) reaches half the width
    /// of the narrowest display, which would un-hide everything. Just under that, the hider is
    /// too wide to fit or to be parked behind the system overflow chevron, so macOS hides it and
    /// every item to its left, with or without a notch.
    private var collapsedLength: CGFloat {
        let narrowest = NSScreen.screens.map(\.frame.width).min() ?? 1440
        return (narrowest / 2 - 17).rounded(.down)
    }

    private func createButton() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = buttonName
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Like the system's own menu bar items, respond as soon as the button is pressed.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            // The button's own image only sizes the item, so its width never changes.
            button.image = Self.placeholder(for: iconStyle)
            glyphView.imageScaling = .scaleNone
            glyphView.frame = button.bounds
            glyphView.autoresizingMask = [.width, .height]
            glyphView.setAccessibilityElement(false)
            button.addSubview(glyphView)
        }
        button = item
    }

    /// Adds the hider, or resizes it for the current displays. It is created at normal size and
    /// widened in the same pass, before macOS draws it: an item created already wide is ejected
    /// instead of hiding anything, and one shown at normal size first would shove every icon
    /// sideways for a few frames before they fade out.
    private func showHider() {
        if hider == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = buttonName
            item.button?.setAccessibilityElement(false)
            hider = item
        }
        hider?.length = collapsedLength
    }

    private func removeHider() {
        if let hider { NSStatusBar.system.removeStatusItem(hider) }
        hider = nil
    }

    // MARK: Glyph

    /// A clear image as large as the style's bigger glyph, so the item keeps one width for both.
    private static func placeholder(for style: IconStyle) -> NSImage {
        let sizes = [true, false].compactMap {
            NSImage(systemSymbolName: style.symbol(collapsed: $0), accessibilityDescription: nil)?.size
        }
        let image = NSImage(size: NSSize(width: sizes.map(\.width).max() ?? 16, height: sizes.map(\.height).max() ?? 16))
        image.isTemplate = true
        return image
    }

    // MARK: Auto-hide

    /// Auto-hide counts down only while the pointer is away from the menu bar: being over it
    /// restarts the countdown. The pointer is read twice a second while the icons are shown, with
    /// slack so the system can coalesce the wake-ups, rather than watching every mouse movement.
    private func updateAutoHide() {
        autoHideTask?.cancel()
        guard !isCollapsed, autoHideSeconds > 0, collapseAfterSettings == nil else { return }
        let total = Duration.seconds(autoHideSeconds), tick = Self.autoHideTick
        autoHideTask = Task { [weak self] in
            var remaining = total
            while true {
                try? await Task.sleep(for: tick, tolerance: tick / 2)
                if Task.isCancelled { return }
                if Self.pointerInMenuBar { remaining = total; continue }
                remaining -= tick
                guard remaining <= .zero else { continue }
                // Listing windows costs more than reading the pointer, so menus are only checked
                // once time is up. One left open still counts as use: wait it out, then count
                // down afresh rather than snapping shut the moment it closes.
                guard Self.menuIsOpen else { break }
                while !Task.isCancelled, Self.menuIsOpen {
                    try? await Task.sleep(for: tick, tolerance: tick / 2)
                }
                remaining = total
            }
            self?.setCollapsed(true)
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
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
        } else if !event.modifierFlags.contains(.command) {
            // Cmd is held while rearranging items; starting a drag shouldn't toggle.
            setCollapsed(!isCollapsed)
        }
    }

    private func showMenu(from sender: NSStatusBarButton) {
        guard let item = button, item.button === sender else { return }
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

/// The button's glyph. Clicks fall through to the button underneath.
private final class GlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
