import AppKit
import IOKit.ps
import Observation
import ServiceManagement
import Symbols
import UniformTypeIdentifiers

/// How the collapse button is drawn. `native` matches the double chevron macOS itself uses for
/// its menu bar overflow control.
enum IconStyle: String, CaseIterable, Identifiable {
    case native, chevron, compactChevron, circleChevron, arrow, triangle, eye, dots, ellipsis, dot, lock
    case tray, grid, sidebar, menuBar, plusMinus, pin, moon, bolt, custom

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .native: L("Native (double chevron)")
        case .chevron: L("Chevron")
        case .compactChevron: L("Light chevron")
        case .circleChevron: L("Circled chevron")
        case .arrow: L("Arrow")
        case .triangle: L("Triangle")
        case .eye: L("Eye")
        case .dots: L("Dots")
        case .ellipsis: L("Ellipsis")
        case .dot: L("Dot")
        case .lock: L("Lock")
        case .tray: L("Tray")
        case .grid: L("Grid")
        case .sidebar: L("Sidebar")
        case .menuBar: L("Menu bar")
        case .plusMinus: L("Plus and minus")
        case .pin: L("Pin")
        case .moon: L("Moon")
        case .bolt: L("Bolt")
        case .custom: L("Custom text")
        }
    }

    /// SF Symbol for the given state. Collapsed points left, expanded points right. The custom
    /// style draws text instead; its symbol is only the picker's label.
    func symbol(collapsed: Bool) -> String {
        switch self {
        case .native: collapsed ? "chevron.left.2" : "chevron.right.2"
        case .chevron: collapsed ? "chevron.left" : "chevron.right"
        case .compactChevron: collapsed ? "chevron.compact.left" : "chevron.compact.right"
        case .circleChevron: collapsed ? "chevron.left.circle.fill" : "chevron.right.circle"
        case .arrow: collapsed ? "arrow.left" : "arrow.right"
        case .triangle: collapsed ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill"
        case .eye: collapsed ? "eye.slash" : "eye"
        case .dots: collapsed ? "ellipsis.circle.fill" : "ellipsis.circle"
        case .ellipsis: collapsed ? "ellipsis.rectangle" : "ellipsis"
        case .dot: collapsed ? "circle.fill" : "circle"
        case .lock: collapsed ? "lock.fill" : "lock.open.fill"
        case .tray: collapsed ? "tray.fill" : "tray"
        case .grid: collapsed ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .sidebar: collapsed ? "sidebar.right" : "sidebar.left"
        case .menuBar: collapsed ? "menubar.rectangle" : "menubar.dock.rectangle"
        case .plusMinus: collapsed ? "plus.circle.fill" : "minus.circle"
        case .pin: collapsed ? "pin.fill" : "pin"
        case .moon: collapsed ? "moon.fill" : "moon"
        case .bolt: collapsed ? "bolt.fill" : "bolt"
        case .custom: "textformat"
        }
    }
}

enum IconSize: String, CaseIterable, Identifiable {
    case small, regular, large, extraLarge
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .small: 11
        case .regular: 13
        case .large: 16
        case .extraLarge: 19
        }
    }
    @MainActor var title: String {
        switch self {
        case .small: L("Small")
        case .regular: L("Regular")
        case .large: L("Large")
        case .extraLarge: L("Extra large")
        }
    }
}

enum IconWeight: String, CaseIterable, Identifiable {
    case light, regular, medium, semibold, bold
    var id: String { rawValue }
    var weight: NSFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
    @MainActor var title: String {
        switch self {
        case .light: L("Light")
        case .regular: L("Regular")
        case .medium: L("Medium")
        case .semibold: L("Semibold")
        case .bold: L("Bold")
        }
    }
}

/// When the button itself can be seen. `whenExpanded` leaves only the hotkey (or hover) to
/// reveal the icons, and the button appears with them so Settings stays one right-click away.
enum ButtonVisibility: String, CaseIterable, Identifiable {
    case always, whenExpanded
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .always: L("Always")
        case .whenExpanded: L("Only when icons are shown")
        }
    }
}

/// Which power source auto-hide applies on.
enum AutoHidePower: String, CaseIterable, Identifiable {
    case always, battery, plugged
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .always: L("Always")
        case .battery: L("On battery only")
        case .plugged: L("When plugged in only")
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
    /// Auto-hide delays offered in settings, in seconds; 0 turns auto-hide off.
    static let autoHideRange = 0.0...120.0
    /// Bumped when setup gains steps existing users need to see (v3: no divider, everything left
    /// of the button hides).
    static let setupKey = "setupCompleteV3"

    /// UserDefaults keys, kept in one place so a typo can't silently split a setting in two.
    private enum Key {
        static let collapsed = "collapsed"
        static let autoHideSeconds = "autoHideSeconds"
        static let autoHidePower = "autoHidePower"
        static let iconStyle = "iconStyle"
        static let iconSize = "iconSize"
        static let iconWeight = "iconWeight"
        static let customCollapsed = "customCollapsed"
        static let customExpanded = "customExpanded"
        static let collapsedOpacity = "collapsedOpacity"
        static let buttonVisibility = "buttonVisibility"
        static let hoverReveal = "hoverReveal"
        static let collapseOnLock = "collapseOnLock"
        static let collapseOnMirroring = "collapseOnMirroring"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkey = "hotkey"
        static let language = "language"
        static let layoutVersion = "layoutVersion"
        static let rolesSwapped = "rolesSwapped"

        /// What export and import carry: the preferences, not the state (collapsed, layout).
        static let portable = [autoHideSeconds, autoHidePower, iconStyle, iconSize, iconWeight, customCollapsed,
                               customExpanded, collapsedOpacity, buttonVisibility, hoverReveal, collapseOnLock,
                               collapseOnMirroring, hotkeyEnabled, hotkey, language]
    }

    /// Set once launching finishes, so loading settings doesn't act on a button that isn't there yet.
    @ObservationIgnored private var ready = false

    private(set) var isCollapsed = false
    var autoHideSeconds = 0 {
        didSet { guard ready else { return }; defaults.set(autoHideSeconds, forKey: Key.autoHideSeconds); updateAutoHide() }
    }
    var autoHidePower = AutoHidePower.always {
        didSet { guard ready else { return }; defaults.set(autoHidePower.rawValue, forKey: Key.autoHidePower); updateAutoHide() }
    }
    var hoverReveal = false {
        didSet { guard ready else { return }; defaults.set(hoverReveal, forKey: Key.hoverReveal); updateAutoHide(); updateHoverWatch() }
    }
    var collapseOnLock = true {
        didSet { guard ready else { return }; defaults.set(collapseOnLock, forKey: Key.collapseOnLock) }
    }
    var collapseOnMirroring = false {
        didSet { guard ready else { return }; defaults.set(collapseOnMirroring, forKey: Key.collapseOnMirroring) }
    }
    var iconStyle = IconStyle.native {
        didSet { guard ready else { return }; defaults.set(iconStyle.rawValue, forKey: Key.iconStyle); glyphSizingChanged() }
    }
    var iconSize = IconSize.regular {
        didSet { guard ready else { return }; defaults.set(iconSize.rawValue, forKey: Key.iconSize); glyphSizingChanged() }
    }
    var iconWeight = IconWeight.regular {
        didSet { guard ready else { return }; defaults.set(iconWeight.rawValue, forKey: Key.iconWeight); glyphSizingChanged() }
    }
    var customCollapsed = "◂" {
        didSet {
            // Reassigning re-enters this observer, so only when clipping changed something.
            if customCollapsed.count > Self.customTextLimit { return customCollapsed = Self.clipped(customCollapsed) }
            guard ready else { return }
            defaults.set(customCollapsed, forKey: Key.customCollapsed)
            if iconStyle == .custom { glyphSizingChanged() }
        }
    }
    var customExpanded = "▸" {
        didSet {
            // Reassigning re-enters this observer, so only when clipping changed something.
            if customExpanded.count > Self.customTextLimit { return customExpanded = Self.clipped(customExpanded) }
            guard ready else { return }
            defaults.set(customExpanded, forKey: Key.customExpanded)
            if iconStyle == .custom { glyphSizingChanged() }
        }
    }
    /// How opaque the button is while the icons are hidden.
    var collapsedOpacity = 1.0 {
        didSet { guard ready else { return }; defaults.set(collapsedOpacity, forKey: Key.collapsedOpacity); updateGlyphAlpha() }
    }
    var buttonVisibility = ButtonVisibility.always {
        didSet { guard ready else { return }; defaults.set(buttonVisibility.rawValue, forKey: Key.buttonVisibility); updateGlyphAlpha() }
    }
    var hotkeyEnabled = true {
        didSet {
            guard ready else { return }
            defaults.set(hotkeyEnabled, forKey: Key.hotkeyEnabled)
            applyHotKey()
        }
    }
    var hotkey = HotKeyCombo.standard {
        didSet { guard ready else { return }; defaults.set(hotkey.plist, forKey: Key.hotkey); applyHotKey() }
    }
    /// "system" or an `AppLanguage` code.
    var language = AppLanguage.system {
        didSet {
            guard ready else { return }
            defaults.set(language, forKey: Key.language)
            Strings.use(language)
            render()
        }
    }
    /// The settings tab showing, so the window rebuilt for a new language stays on it.
    var settingsTab = 0
    /// True if the system refused the hotkey, because something else already uses it.
    private(set) var hotkeyConflict = false
    /// The outcome of the last export or import, shown under the buttons.
    private(set) var settingsMessage: String?
    /// The status the system reports, re-read whenever settings open since it can also be
    /// changed in System Settings.
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Why the last login item change failed, shown under the toggle.
    private(set) var launchError: String?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var button: NSStatusItem?
    /// Draws the button's glyph, since only an image view can play the system's symbol
    /// transitions. It renders the same as the button's own image would.
    @ObservationIgnored private let glyphView = GlyphView()
    /// Watches for the pointer touching the button while collapsed; see `updateHoverWatch`.
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    /// Only exists while collapsed.
    @ObservationIgnored private var hider: NSStatusItem?
    /// The hide that follows the start of a collapse animation; see `hideDelay`.
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    /// Re-checks whether anything sits left of the button; see `updateGlyphAlpha`.
    @ObservationIgnored private var dimTask: Task<Void, Never>?
    /// How many items sat left of the button when last counted, for the tooltip.
    @ObservationIgnored private var hiddenCount = 0
    /// While the hotkey is being recorded it is unregistered, or pressing it would just toggle.
    @ObservationIgnored private var hotkeyRecording = false
    /// Whether to hide the icons again when the settings window closes; nil while it is closed.
    @ObservationIgnored private var collapseAfterSettings: Bool?
    /// Autosave names are versioned so "Reset Layout" can discard the saved position.
    private var layoutVersion: Int { defaults.integer(forKey: Key.layoutVersion) }
    /// Older versions could swap the button with their divider, so the button may own that name.
    private var buttonName: String {
        (defaults.bool(forKey: Key.rolesSwapped) ? "divider" : "button") + "\(layoutVersion)"
    }
    /// Set by the app delegate to open the settings window.
    @ObservationIgnored var openSettings: () -> Void = {}

    /// macOS fades the icons in over ~200 ms but out over ~150 ms, most of it up front, and that
    /// can't be changed from here. So expanding plays the glyph's transition sped up to land with
    /// the fade-in, while collapsing plays it at the system's pace and hides the icons a beat
    /// after it starts: the old glyph shrinks away with the icons and the new one settles after.
    private static let expandSpeed = 1.4
    private static let collapseSpeed = 1.0
    private static let hideDelay = Duration.milliseconds(50)
    private static let autoHideTick = Duration.milliseconds(500)
    private static let dimTick = Duration.seconds(1)
    private static let hoverTick = Duration.milliseconds(100)
    private static let dimmedAlpha: CGFloat = 0.35
    /// How long the pointer must stay off the menu bar before hover-to-reveal hides the icons
    /// again, when no auto-hide delay is set.
    private static let hoverHideSeconds = 2

    init() {
        Self.migrateLegacyDefaults(into: defaults)
        isCollapsed = defaults.bool(forKey: Key.collapsed)
        loadSettings()
        Strings.use(language)

        createButton()
        ready = true
        render()
        updateAutoHide()
        updateHoverWatch()
        startDimming()
        applyHotKey()
        observeSystem()
    }

    /// 1.0.0 shipped as com.example.StatusCollapse. Its icon style and auto-hide delay carry over,
    /// then its preferences are removed. Setup runs again (its completion isn't copied), since the
    /// button's saved menu bar position may not survive the change of bundle ID.
    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        let legacyDomain = "com.example.StatusCollapse"
        // A removed domain reads back as empty rather than nil.
        guard let legacy = defaults.persistentDomain(forName: legacyDomain), !legacy.isEmpty else { return }
        for key in [Key.iconStyle, Key.autoHideSeconds] where defaults.object(forKey: key) == nil {
            defaults.set(legacy[key], forKey: key)
        }
        defaults.removePersistentDomain(forName: legacyDomain)
    }

    /// Reads every preference, keeping the default for anything missing or out of range.
    private func loadSettings() {
        func raw<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        autoHideSeconds = min(max(defaults.integer(forKey: Key.autoHideSeconds), 0), Int(Self.autoHideRange.upperBound))
        autoHidePower = raw(Key.autoHidePower, .always)
        hoverReveal = flag(Key.hoverReveal, false)
        collapseOnLock = flag(Key.collapseOnLock, true)
        collapseOnMirroring = flag(Key.collapseOnMirroring, false)
        iconStyle = raw(Key.iconStyle, .native)
        iconSize = raw(Key.iconSize, .regular)
        iconWeight = raw(Key.iconWeight, .regular)
        customCollapsed = defaults.string(forKey: Key.customCollapsed) ?? "◂"
        customExpanded = defaults.string(forKey: Key.customExpanded) ?? "▸"
        collapsedOpacity = min(max(defaults.object(forKey: Key.collapsedOpacity) as? Double ?? 1, 0.2), 1)
        // 1.3.0 betas also had "hidden", which left no way to reach Settings; it now means this.
        buttonVisibility = defaults.string(forKey: Key.buttonVisibility) == "hidden" ? .whenExpanded
            : raw(Key.buttonVisibility, .always)
        hotkeyEnabled = flag(Key.hotkeyEnabled, true)
        let savedKey = HotKeyCombo(plist: defaults.object(forKey: Key.hotkey))
        hotkey = savedKey.flatMap { HotKeyCombo.retired.contains($0) ? nil : $0 } ?? .standard
        let saved = defaults.string(forKey: Key.language) ?? AppLanguage.system
        language = saved == AppLanguage.system || AppLanguage.named(saved) != nil ? saved : AppLanguage.system
    }

    /// Custom button text is limited to what fits a menu bar item.
    private static let customTextLimit = 4
    private static func clipped(_ text: String) -> String { String(text.prefix(customTextLimit)) }

    // MARK: Collapse

    /// Collapses or expands, animated. Asking for the current state still re-evaluates auto-hide,
    /// which is how opening the settings window pauses it.
    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return updateAutoHide() }
        if collapsed, let count = itemsLeftOfButton { hiddenCount = count }
        isCollapsed = collapsed
        defaults.set(collapsed, forKey: Key.collapsed)
        // Hiding or showing icons while settings are open is the user's choice, so closing the
        // window keeps it.
        if collapseAfterSettings != nil { collapseAfterSettings = collapsed }
        render(animated: true)
        updateAutoHide()
        updateHoverWatch()
    }

    /// Icons are shown when the settings window opens so they're easy to arrange. Hiding them
    /// again while it is open is allowed; closing the window keeps the last state chosen.
    func settingsWillOpen() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        settingsMessage = nil
        guard collapseAfterSettings == nil else { return }
        let before = isCollapsed
        collapseAfterSettings = before
        setCollapsed(false)
        // Opening shows the icons, but that isn't a choice to restore when the window closes.
        collapseAfterSettings = before
        updateGlyphAlpha()
    }

    func settingsDidClose() {
        guard let collapse = collapseAfterSettings else { return }
        collapseAfterSettings = nil
        updateGlyphAlpha()
        if collapse { setCollapsed(true) } else { updateAutoHide() }
    }

    /// Recreates the button under a new autosave name, discarding its saved position, so a button
    /// that went missing comes back. Icons are left shown, and the button is made visible again.
    func resetLayout() {
        defaults.set(layoutVersion + 1, forKey: Key.layoutVersion)
        defaults.set(false, forKey: Key.rolesSwapped)
        isCollapsed = false
        defaults.set(false, forKey: Key.collapsed)
        buttonVisibility = .always
        updateHoverWatch()
        removeHider()
        if let button { NSStatusBar.system.removeStatusItem(button) }
        createButton()
        render()
    }

    private func collapseForPrivacy() { setCollapsed(true) }

    private func toggleFromHotKey() {
        setCollapsed(!isCollapsed)
    }

    /// Brings the tooltip, glyph and hider in line with `isCollapsed`. Animated changes play the
    /// glyph transition, and a collapse hides the icons a beat after it starts.
    private func render(animated: Bool = false) {
        guard let button = button?.button else { return }
        let label = isCollapsed ? L("Show hidden menu bar icons") : L("Hide menu bar icons")
        button.toolTip = isCollapsed && hiddenCount > 0 ? "\(label) (\(hiddenCount))" : label
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

        glyphView.symbolConfiguration = symbolConfiguration
        if iconStyle == .custom {
            glyphView.image = Self.textImage(isCollapsed ? customCollapsed : customExpanded,
                                             size: iconSize.points, weight: iconWeight.weight)
        } else if let glyph = NSImage(systemSymbolName: iconStyle.symbol(collapsed: isCollapsed), accessibilityDescription: nil) {
            // A button shown only with the icons has no collapsed look, so nothing may morph
            // from one: the expanded glyph is simply there when it appears.
            if animated && buttonVisibility == .always {
                // Magic Replace draws the eye's slash on and off; the arrows and chevrons have nothing
                // to morph, so they use the standard Replace, layer by layer. Both retarget smoothly
                // if clicked again mid-transition.
                glyphView.setSymbolImage(glyph, contentTransition: .replace.magic(fallback: .replace.downUp.byLayer),
                                         options: .speed(isCollapsed ? Self.collapseSpeed : Self.expandSpeed))
            } else {
                glyphView.image = glyph
            }
        }
        updateGlyphAlpha()
    }

    /// The size and weight the user chose, or nil for the system's own look.
    private var symbolConfiguration: NSImage.SymbolConfiguration? {
        guard iconSize != .regular || iconWeight != .regular else { return nil }
        return NSImage.SymbolConfiguration(pointSize: iconSize.points, weight: iconWeight.weight)
    }

    /// The placeholder sets the item's width, which depends on the style's glyphs and their size.
    private func glyphSizingChanged() {
        button?.button?.image = placeholder()
        render()
    }

    // MARK: Glyph opacity

    /// Items to the left of the button can't be seen from here being added or removed (the button
    /// doesn't move when they do), so the menu bar is checked once a second.
    private func startDimming() {
        dimTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.dimTick, tolerance: Self.dimTick / 2)
                self?.updateGlyphAlpha()
            }
        }
    }

    /// Sets how visible the glyph is. While the icons are shown and nothing is left of the button
    /// to hide, it is dimmed like a disabled control (it still works: it can be dragged and
    /// right-clicked). While collapsed, the hider's own state says nothing about what it hides, so
    /// it takes the user's collapsed opacity. The user can also hide the glyph.
    private func updateGlyphAlpha() {
        if buttonVisibility == .whenExpanded && isCollapsed {
            glyphView.alphaValue = 0
            return
        }
        if isCollapsed {
            glyphView.alphaValue = collapsedOpacity
        } else {
            if let count = itemsLeftOfButton { hiddenCount = count }
            glyphView.alphaValue = itemsLeftOfButton == 0 ? Self.dimmedAlpha : 1
        }
    }

    /// How many other status items are on screen to the left of the button, on the same bar, or
    /// nil if that can't be told.
    private var itemsLeftOfButton: Int? {
        guard let window = button?.button?.window, window.windowNumber > 0 else { return nil }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        func bounds(_ info: [String: Any]) -> CGRect? {
            (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        }
        guard let mine = infos.first(where: { $0[kCGWindowNumber as String] as? Int == window.windowNumber })
            .flatMap(bounds) else { return nil }
        return infos.filter { info in
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  info[kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier,
                  let other = bounds(info) else { return false }
            return abs(other.minY - mine.minY) < 4 && other.maxX <= mine.minX + 1
        }.count
    }

    /// macOS 27 ejects any item whose window (length plus 16 pt of chrome) reaches half the width
    /// of the narrowest display, which would un-hide everything. Just under that, the hider is
    /// too wide to fit or to be parked behind the system overflow chevron, so macOS hides it and
    /// every item to its left. Measured on a notched display; displays without one are untested.
    private var collapsedLength: CGFloat {
        let narrowest = NSScreen.screens.map(\.frame.width).min() ?? 1440
        return (narrowest / 2 - 17).rounded(.down)
    }

    /// Adds the button under its autosave name, which makes macOS put it back where it was saved.
    private func createButton() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = buttonName
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Like the system's own menu bar items, respond as soon as the button is pressed.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            // The button's own image only sizes the item, so its width never changes.
            button.image = placeholder()
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
    private func placeholder() -> NSImage {
        let sizes: [NSSize]
        if iconStyle == .custom {
            sizes = [customCollapsed, customExpanded].map { Self.textImage($0, size: iconSize.points, weight: iconWeight.weight).size }
        } else {
            sizes = [true, false].compactMap { collapsed in
                guard let symbol = NSImage(systemSymbolName: iconStyle.symbol(collapsed: collapsed), accessibilityDescription: nil)
                else { return nil }
                return (symbolConfiguration.flatMap { symbol.withSymbolConfiguration($0) } ?? symbol).size
            }
        }
        let image = NSImage(size: NSSize(width: sizes.map(\.width).max() ?? 16, height: sizes.map(\.height).max() ?? 16))
        image.isTemplate = true
        return image
    }

    /// `text` as a template image, so it takes the menu bar's colour like a symbol does.
    private static func textImage(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSImage {
        let string = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.black,
        ])
        let extent = string.size()
        let image = NSImage(size: NSSize(width: ceil(extent.width), height: ceil(extent.height)))
        image.lockFocus()
        string.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: Auto-hide

    /// Auto-hide counts down only while the pointer is away from the menu bar: being over it
    /// restarts the countdown. The pointer is read twice a second while the icons are shown, with
    /// slack so the system can coalesce the wake-ups, rather than watching every mouse movement.
    /// Coalesced wake-ups can arrive late, so the countdown is timed against the clock rather
    /// than by counting them. Hover-to-reveal needs the same countdown to hide again.
    private func updateAutoHide() {
        autoHideTask?.cancel()
        let seconds = autoHideSeconds > 0 ? autoHideSeconds : (hoverReveal ? Self.hoverHideSeconds : 0)
        guard !isCollapsed, seconds > 0, collapseAfterSettings == nil else { return }
        let delay = Duration.seconds(seconds), tick = Self.autoHideTick, power = autoHidePower
        autoHideTask = Task { [weak self] in
            var deadline = ContinuousClock.now + delay
            while true {
                try? await Task.sleep(for: tick, tolerance: tick / 2)
                if Task.isCancelled { return }
                if Self.pointerInMenuBar { deadline = ContinuousClock.now + delay; continue }
                guard ContinuousClock.now >= deadline else { continue }
                // Hold off while the power source isn't the one auto-hide was limited to.
                guard Self.powerAllowsAutoHide(power) else { deadline = ContinuousClock.now + delay; continue }
                // Listing windows costs more than reading the pointer, so menus are only checked
                // once time is up. One left open still counts as use: wait it out, then count
                // down afresh rather than snapping shut the moment it closes.
                guard Self.menuIsOpen else { break }
                while !Task.isCancelled, Self.menuIsOpen {
                    try? await Task.sleep(for: tick, tolerance: tick / 2)
                }
                deadline = ContinuousClock.now + delay
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

    /// True while any app has a menu open. Only window layers are read, which needs no Screen
    /// Recording permission.
    private static var menuIsOpen: Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowLayer as String] as? Int == menuLevel }
    }

    private static func powerAllowsAutoHide(_ power: AutoHidePower) -> Bool {
        guard power != .always else { return true }
        var onBattery = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            onBattery = (source as String) == kIOPSBatteryPowerValue
        }
        return power == .battery ? onBattery : !onBattery
    }

    // MARK: Triggers

    /// Status item buttons never receive mouse-entered events, so while collapsed with hover
    /// reveal on, the pointer is read ten times a second. It must leave the button first, or a
    /// click that collapses would reveal again at once.
    private func updateHoverWatch() {
        hoverTask?.cancel()
        guard hoverReveal, isCollapsed else { return }
        let tick = Self.hoverTick
        hoverTask = Task { [weak self] in
            var armed = false
            while !Task.isCancelled {
                try? await Task.sleep(for: tick, tolerance: tick / 2)
                guard let self, let frame = self.button?.button?.window?.frame else { continue }
                if frame.contains(NSEvent.mouseLocation) {
                    if armed { return self.setCollapsed(false) }
                } else {
                    armed = true
                }
            }
        }
    }

    /// Screen lock, sleep and display mirroring, plus the displays attached (the collapsed width
    /// depends on them).
    private func observeSystem() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render()
                if self.collapseOnMirroring, Self.isMirroring { self.collapseForPrivacy() }
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.collapseOnLock == true { self?.collapseForPrivacy() } }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.collapseOnLock == true { self?.collapseForPrivacy() } }
        }
    }

    /// True while any display shows another's picture, as when presenting on a projector or AirPlay.
    private static var isMirroring: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    // MARK: Hotkey

    /// Pauses the hotkey while its replacement is recorded.
    func setHotKeyRecording(_ recording: Bool) {
        hotkeyRecording = recording
        applyHotKey()
    }

    private func applyHotKey() {
        let center = HotKeyCenter.shared
        center.action = { [weak self] in self?.toggleFromHotKey() }
        let active = hotkeyEnabled && !hotkeyRecording
        let registered = center.register(active ? hotkey : nil)
        hotkeyConflict = !registered
        // Without a working shortcut, a hidden button would leave no way to toggle.
        if (!hotkeyEnabled || hotkeyConflict), buttonVisibility != .always { buttonVisibility = .always }
    }

    // MARK: Login item

    /// Registers or unregisters the app as a login item, then shows the status the system
    /// reports, so the toggle never claims a change that didn't happen.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Export and import

    /// Saves the preferences, not the collapsed state or button position, as a JSON file.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "StatusCollapse Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let values = Key.portable.reduce(into: [String: Any]()) { $0[$1] = defaults.object(forKey: $1) }
        do {
            try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: url)
            settingsMessage = L("Settings exported.")
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    /// Applies a file made by `exportSettings`. Anything it doesn't recognise is ignored, and
    /// values out of range fall back to their defaults.
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            settingsMessage = L("That file isn't a StatusCollapse settings file.")
            return
        }
        for key in Key.portable {
            guard let value = values[key], value is String || value is NSNumber || value is [String: Any] else { continue }
            defaults.set(value, forKey: key)
        }
        loadSettings()
        settingsMessage = L("Settings imported.")
    }

    // MARK: Status item interaction

    /// Left-click toggles; right-click or Control-click opens the menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // A press from VoiceOver or keyboard navigation has no mouse-down behind it; it toggles.
        guard let event = NSApp.currentEvent, [.leftMouseDown, .rightMouseDown].contains(event.type) else {
            return setCollapsed(!isCollapsed)
        }
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
        let toggle = menu.addItem(withTitle: isCollapsed ? L("Show hidden menu bar icons") : L("Hide menu bar icons"),
                                  action: #selector(toggleChosen), keyEquivalent: "")
        toggle.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L("Settings…"), action: #selector(settingsChosen), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit StatusCollapse"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        // Attach only for this click so left-click keeps toggling.
        item.menu = menu
        sender.performClick(nil)
        item.menu = nil
    }

    @objc private func settingsChosen() { openSettings() }
    @objc private func toggleChosen() { setCollapsed(!isCollapsed) }
}

/// The button's glyph. Clicks fall through to the button underneath.
private final class GlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

