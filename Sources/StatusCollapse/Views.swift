import SwiftUI

/// Renders markdown, so a translation can bold a word with `**`.
@MainActor
private func md(_ text: String) -> Text {
    Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text))
}

/// A sentence with the SF Symbol dropped in where the translation has `%@`, since word order
/// differs between languages.
@MainActor
private func withIcon(_ key: String, _ symbol: String) -> Text {
    let parts = L(key).components(separatedBy: "%@")
    guard parts.count == 2 else { return Text(verbatim: parts.joined()) }
    let (before, after) = (parts[0], parts[1])
    return Text("\(before)\(Image(systemName: symbol))\(after)")
}

/// Settings, plus a first-run wizard shown in the same window.
struct RootView: View {
    let controller: Controller
    @AppStorage(Controller.setupKey) private var setupComplete = false

    var body: some View {
        Group {
            if setupComplete {
                SettingsView(controller: controller, rerunSetup: { setupComplete = false })
            } else {
                WizardView(controller: controller, finish: { setupComplete = true })
            }
        }
        // Rebuilds the window in the new language as soon as it is chosen.
        .id(controller.language)
        .environment(\.layoutDirection, Strings.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Wizard

/// First-run walkthrough: welcome, arranging icons, then the login item. Shown until finished,
/// and again from "Run Setup".
private struct WizardView: View {
    let controller: Controller
    let finish: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0: welcome
            case 1: arrange
            default: done
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button(L("Back")) { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button(L("Continue")) { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Finish"), action: finish).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440, height: 360)
        .onChange(of: step) { _, new in
            // Keep icons visible while the user arranges them.
            if new == 1 { controller.setCollapsed(false) }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chevron.left.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text(L("Welcome to StatusCollapse")).font(.title2.bold())
            Text(L("Hide menu bar icons you rarely need and reveal them with one click."))
            Label(L("No permissions needed. It only manages its own menu bar items, so the clock and Notification Center keep working normally."), systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        }
    }

    private var arrange: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Choose which icons to hide")).font(.title2.bold())
            withIcon("Look for the %@ button in your menu bar.", controller.iconStyle.symbol(collapsed: true))
            VStack(alignment: .leading, spacing: 6) {
                md(L("1. Hold ⌘ and drag icons to the **left** of the button to hide them. You can ⌘-drag the button too."))
                md(L("2. Collapsing hides everything left of the button. Icons to its right always stay visible."))
            }
            Text(L("Apple's menu bar doesn't let apps move other apps' icons, so this one step is manual. Positions are remembered."))
                .font(.callout).foregroundStyle(.secondary)
            Button(controller.isCollapsed ? L("Show icons") : L("Try collapsing")) {
                controller.setCollapsed(!controller.isCollapsed)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("You're all set")).font(.title2.bold())
            withIcon("Click the %@ button to hide or show icons. Right-click it for Settings and Quit.",
                     controller.iconStyle.symbol(collapsed: true))
            if controller.hotkeyEnabled && !controller.hotkeyConflict {
                Text(L("Or press %@ from anywhere.", controller.hotkey.display))
            }
            Toggle(L("Open at login"), isOn: Binding(
                get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
            if let error = controller.launchError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Changelog

/// The app's icon as drawn in its windows: the chevron on a teal tile.
private struct AppBadge: View {
    var body: some View {
        Image(systemName: "chevron.left.2")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: [Color(red: 0.18, green: 0.83, blue: 0.75), Color(red: 0.05, green: 0.45, blue: 0.56)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The newest section of the bundled CHANGELOG.md: its heading (`1.0.0 - 2026-10-03`), any
/// paragraphs before the first group, and groups of bullets under bold titles.
private struct ReleaseNotes {
    struct Group: Identifiable {
        let id: Int
        var title: String?
        var items: [String] = []
    }
    var version = ""
    var date: Date?
    var intro: [String] = []
    var groups: [Group] = []

    static let latest: ReleaseNotes? = {
        guard let text = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
                .flatMap({ try? String(contentsOf: $0, encoding: .utf8) }),
              let section = text.components(separatedBy: "\n## ").dropFirst().first else { return nil }
        let lines = section.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let heading = lines.first else { return nil }
        var notes = ReleaseNotes()
        let parts = heading.components(separatedBy: " - ")
        notes.version = parts[0]
        notes.date = parts.count > 1 ? try? Date(parts[1], strategy: .iso8601.year().month().day()) : nil
        for line in lines.dropFirst() {
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
                notes.groups.append(Group(id: notes.groups.count, title: String(line.dropFirst(2).dropLast(2))))
            } else if line.hasPrefix("- ") {
                if notes.groups.isEmpty { notes.groups.append(Group(id: 0)) }
                notes.groups[notes.groups.count - 1].items.append(String(line.dropFirst(2)))
            } else {
                notes.intro.append(line)
            }
        }
        return notes
    }()
}

/// What's new in the running version: a header, the notes in groups, and a Close button.
private struct ChangelogView: View {
    let notes: ReleaseNotes?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        AppBadge()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("StatusCollapse \(notes?.version ?? "")").font(.title3.bold())
                            if let date = notes?.date {
                                Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Strings.locale)))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(notes?.intro ?? [], id: \.self) { md($0).foregroundStyle(.secondary) }
                    ForEach(notes?.groups ?? []) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = group.title { Text(title).font(.headline) }
                            ForEach(group.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(verbatim: "•").foregroundStyle(.secondary)
                                    md(item).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("Close"), action: close).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}

/// The release notes in a small window of their own, reused while open.
@MainActor
private enum ChangelogWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let new = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
            new.isReleasedWhenClosed = false
            new.center()
            window = new
        }
        guard let window else { return }
        // Rebuilt each time, so it follows the language chosen in Settings.
        window.title = L("What's New")
        window.contentView = NSHostingView(rootView: ChangelogView(notes: .latest) { window.close() }
            .environment(\.layoutDirection, Strings.isRightToLeft ? .rightToLeft : .leftToRight))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - Window sizing

/// For each tab, the height its content needs and the height its scroll view is showing, measured
/// in place. Kept per tab because the tab view keeps every tab laid out, not just the selected one.
private struct TabFitKey: PreferenceKey {
    static let defaultValue: [Int: TabFit] = [:]
    static func reduce(value: inout [Int: TabFit], nextValue: () -> [Int: TabFit]) {
        for (tab, next) in nextValue() {
            value[tab, default: TabFit()].content = next.content ?? value[tab]?.content
            value[tab, default: TabFit()].visible = next.visible ?? value[tab]?.visible
        }
    }
}

private struct TabFit: Equatable {
    var content: CGFloat?
    var visible: CGFloat?
}

/// The settings view's whole height, measured in the same layout pass as the tabs.
private struct RootHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// Sizes the hosting window to the selected tab: the room outside the tab's scroll view, which is
/// the same on every tab, plus what the tab's content needs. So each tab fits exactly, with the
/// same margins, and scrolls only past `maxShare` of the screen. Both come from one layout pass, so
/// they agree even while the window is animating. It acts when the tab, its content or that room
/// changes, not when the window is resized by hand, which changes neither. The top edge stays put,
/// as in System Settings, and the change animates once the window is showing.
private struct WindowSizer: NSViewRepresentable {
    let tab: Int
    let fit: TabFit
    let rootHeight: CGFloat?
    let minHeight: CGFloat
    let maxShare: CGFloat

    final class Coordinator {
        var latest: (tab: Int, content: CGFloat, room: CGFloat)?
        var applied: (tab: Int, content: CGFloat, room: CGFloat)?
        var scheduled = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let content = fit.content, let visible = fit.visible, let rootHeight else { return }
        let coordinator = context.coordinator
        coordinator.latest = (tab, content, rootHeight - visible)
        // A switch reports in more than one pass; act on where they settle.
        guard !coordinator.scheduled else { return }
        coordinator.scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [minHeight, maxShare] in
            coordinator.scheduled = false
            guard let window = view.window, let latest = coordinator.latest else { return }
            if let applied = coordinator.applied, applied.tab == latest.tab,
               abs(applied.content - latest.content) < 1, abs(applied.room - latest.room) < 1 { return }
            coordinator.applied = latest
            var frame = window.frame
            let current = window.contentRect(forFrameRect: frame).height
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            let target = max(minHeight, min(latest.room + latest.content, (screen * maxShare).rounded(.down)))
            let delta = target - current
            guard abs(delta) >= 1 else { return }
            frame.size.height += delta
            frame.origin.y -= delta
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
    }
}

// MARK: - Settings

/// The settings window's content once setup is finished.
private struct SettingsView: View {
    @Bindable var controller: Controller
    let rerunSetup: () -> Void

    /// The selected tab's measured heights, which size the window.
    @State private var fits: [Int: TabFit] = [:]
    @State private var rootHeight: CGFloat?

    private static let minimumSize = CGSize(width: 540, height: 380)
    /// The window grows to fit the selected tab, but no taller than this share of the screen.
    private static let screenShare = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TabView(selection: $controller.settingsTab) {
                tab(0) { menuBarTab }.tabItem { Label(L("Menu bar"), systemImage: "menubar.rectangle") }.tag(0)
                tab(1) { behaviourTab }.tabItem { Label(L("Behaviour"), systemImage: "slider.horizontal.3") }.tag(1)
                tab(2) { generalTab }.tabItem { Label(L("General"), systemImage: "gearshape") }.tag(2)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: Self.minimumSize.width, maxWidth: .infinity,
               minHeight: Self.minimumSize.height, idealHeight: 660, maxHeight: .infinity)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: RootHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(RootHeightKey.self) { rootHeight = $0 }
        .background(WindowSizer(tab: controller.settingsTab, fit: fits[controller.settingsTab] ?? TabFit(), rootHeight: rootHeight,
                                minHeight: Self.minimumSize.height, maxShare: Self.screenShare))
        .onPreferenceChange(TabFitKey.self) { fits = $0 }
    }

    /// A tab's content, with the same margins on every tab, measured where it is shown.
    private func tab<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: TabFitKey.self, value: [index: TabFit(content: proxy.size.height)])
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TabFitKey.self, value: [index: TabFit(visible: proxy.size.height)])
        })
    }

    // MARK: Tabs

    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(L("How it works"), systemImage: "questionmark.circle") {
                step(1, withIcon("Find the %@ button in your menu bar.", controller.iconStyle.symbol(collapsed: true)))
                step(2, md(L("Hold ⌘ and drag icons to the **left** of the button to make them hideable.")))
                step(3, md(L("Click the button to hide or show them. Icons to its right always stay visible.")))
            }
            card(L("Button"), systemImage: "circle.grid.cross") {
                row(L("Icon"), detail: L("The button you click to hide or show icons.")) {
                    Picker(L("Icon"), selection: $controller.iconStyle) {
                        ForEach(IconStyle.allCases) { style in
                            Label { Text(style.title) } icon: { Image(nsImage: Self.pairImage(style)) }.tag(style)
                        }
                    }
                }
                if controller.iconStyle == .custom {
                    Divider()
                    row(L("Text when icons are shown"), detail: L("Up to four characters, such as ▸ or •••.")) {
                        TextField("", text: $controller.customExpanded).frame(width: 90).multilineTextAlignment(.center)
                    }
                    row(L("Text when icons are hidden"), detail: "") {
                        TextField("", text: $controller.customCollapsed).frame(width: 90).multilineTextAlignment(.center)
                    }
                }
                Divider()
                row(L("Size"), detail: "") {
                    Picker(L("Size"), selection: $controller.iconSize) {
                        ForEach(IconSize.allCases) { Text($0.title).tag($0) }
                    }
                }
                row(L("Weight"), detail: "") {
                    Picker(L("Weight"), selection: $controller.iconWeight) {
                        ForEach(IconWeight.allCases) { Text($0.title).tag($0) }
                    }
                }
                Divider()
                row(L("Opacity when icons are hidden"), detail: L("Fade the button while it isn't needed.")) {
                    HStack {
                        Slider(value: $controller.collapsedOpacity, in: 0.2...1, step: 0.05).frame(width: 130)
                        Text(L("%d%%", Int((controller.collapsedOpacity * 100).rounded())))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Divider()
                row(L("Show the button"), detail: L("Hiding it needs the keyboard shortcut turned on.")) {
                    Picker(L("Show the button"), selection: $controller.buttonVisibility) {
                        ForEach(controller.hotkeyEnabled ? ButtonVisibility.allCases : [.always]) { Text($0.title).tag($0) }
                    }
                }
            }
        }
    }

    private var behaviourTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(L("Shortcut"), systemImage: "keyboard") {
                row(L("Keyboard shortcut"), detail: L("Hides or shows the icons from anywhere.")) {
                    Toggle(L("Keyboard shortcut"), isOn: $controller.hotkeyEnabled).toggleStyle(.switch)
                }
                if controller.hotkeyEnabled {
                    row(L("Shortcut"), detail: L("Click, then press the keys. Esc cancels.")) {
                        HStack {
                            HotKeyRecorder(combo: controller.hotkey, prompt: L("Press keys…"),
                                           recordingChanged: { controller.setHotKeyRecording($0) },
                                           recorded: { controller.hotkey = $0 })
                            Button(L("Reset")) { controller.hotkey = .standard }
                                .disabled(controller.hotkey == .standard)
                        }
                    }
                    if controller.hotkeyConflict {
                        Text(L("macOS or another app already uses that shortcut. Choose another."))
                            .font(.callout).foregroundStyle(.red)
                    }
                }
            }
            card(L("Auto-hide"), systemImage: "timer") {
                Text(L("Auto-hide, including hiding again after hover, pauses while this window is open."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                row(L("Auto-hide"), detail: L("Hides icons again after you reveal them.")) {
                    HStack {
                        Slider(value: Binding(get: { Double(controller.autoHideSeconds) },
                                              set: { controller.autoHideSeconds = Int($0) }),
                               in: Controller.autoHideRange, step: 5).frame(width: 130)
                        Text(controller.autoHideSeconds == 0 ? L("Never") : L("%d seconds", controller.autoHideSeconds))
                            .monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
                Divider()
                row(L("Auto-hide on"), detail: L("Only hide automatically on this power source.")) {
                    Picker(L("Auto-hide on"), selection: $controller.autoHidePower) {
                        ForEach(AutoHidePower.allCases) { Text($0.title).tag($0) }
                    }
                }
                Divider()
                row(L("Reveal on hover"), detail: L("Show the icons when the pointer touches the button.")) {
                    Toggle(L("Reveal on hover"), isOn: $controller.hoverReveal).toggleStyle(.switch)
                }
            }
            card(L("Privacy"), systemImage: "lock.shield") {
                row(L("Hide when the Mac locks or sleeps"), detail: L("So the icons are hidden when you return.")) {
                    Toggle(L("Hide when the Mac locks or sleeps"), isOn: $controller.collapseOnLock).toggleStyle(.switch)
                }
                Divider()
                row(L("Hide when mirroring a display"), detail: L("For projectors and AirPlay screens.")) {
                    Toggle(L("Hide when mirroring a display"), isOn: $controller.collapseOnMirroring).toggleStyle(.switch)
                }
            }
            card(L("Other displays"), systemImage: "display.2") {
                row(L("Prevent click highlights"),
                    detail: L("Clicking the empty menu bar beside the button on a display you aren't using can briefly highlight it. Preventing this needs the Device Control and Data Access permission.")) {
                    Toggle(L("Prevent click highlights"), isOn: $controller.coverOtherDisplays).toggleStyle(.switch)
                }
                if controller.coverOtherDisplays {
                    Divider()
                    if controller.accessibilityAllowed {
                        Label(L("Access is allowed. StatusCollapse only reads where menu bar items are."),
                              systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L("Waiting for access. Turn on StatusCollapse in Privacy & Security → Device Control and Data Access. If it's already on, turn it off and on again."))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { controller.openAccessibilitySettings() } label: {
                            Label(L("Open Privacy & Security"), systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
        }
    }

    private var updateMessage: String {
        switch controller.updateStatus {
        case .unknown: L("Version %@", Controller.currentVersion)
        case .checking: L("Checking…")
        case .upToDate: L("You're up to date.")
        case .failed: L("Couldn't check for updates.")
        case .available: ""
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(L("General"), systemImage: "gearshape") {
                row(L("Open at login"), detail: L("Starts StatusCollapse when you sign in.")) {
                    Toggle(L("Open at login"), isOn: Binding(
                        get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                }
                if let error = controller.launchError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Divider()
                row(L("Language"), detail: L("Follows your Mac unless you choose one.")) {
                    Picker(L("Language"), selection: $controller.language) {
                        Text(L("System default")).tag(AppLanguage.system)
                        Divider()
                        ForEach(AppLanguage.all) { Text($0.name).tag($0.code) }
                    }
                }
            }
            card(L("Updates"), systemImage: "arrow.down.circle") {
                row(L("Check for updates"), detail: L("Looks for a newer version once a day. Nothing is downloaded or installed.")) {
                    Toggle(L("Check for updates"), isOn: $controller.updateChecks).toggleStyle(.switch)
                }
                HStack(spacing: 8) {
                    switch controller.updateStatus {
                    case .available(let release):
                        Text(L("Version %@ is available.", release.version)).font(.callout)
                        Spacer(minLength: 0)
                        Button { NSWorkspace.shared.open(release.url) } label: {
                            Label(L("View release"), systemImage: "arrow.up.right.square")
                        }
                    default:
                        Text(updateMessage).font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(L("Check now")) { controller.checkForUpdates() }
                            .disabled(controller.updateStatus == .checking)
                    }
                }
            }
            card(L("Settings file"), systemImage: "square.and.arrow.up.on.square") {
                Text(L("Keep a copy of your settings, or carry them to another Mac."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button { controller.exportSettings() } label: { Label(L("Export…"), systemImage: "square.and.arrow.up") }
                    Button { controller.importSettings() } label: { Label(L("Import…"), systemImage: "square.and.arrow.down") }
                }
                if let message = controller.settingsMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            card(L("Icons"), systemImage: "square.grid.2x2") {
                Text(L("Icons stay shown while this window is open so they're easy to arrange. Positions are remembered. macOS doesn't let apps move other apps' icons, so arranging is manual."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Longer translations don't fit one row, so the buttons stack when they must.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { setupButtons; Spacer(minLength: 0); systemSettingsButton }
                    VStack(alignment: .leading, spacing: 8) { setupButtons; systemSettingsButton }
                }
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder private var setupButtons: some View {
        Button { rerunSetup() } label: { Label(L("Run Setup"), systemImage: "arrow.counterclockwise") }
        Button { controller.resetLayout() } label: { Label(L("Reset Layout"), systemImage: "arrow.uturn.backward") }
    }

    private var systemSettingsButton: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
        } label: { Label(L("System Settings"), systemImage: "gearshape") }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text(L("Right-click the menu bar button for Settings and Quit."))
            Button { ChangelogWindow.show() } label: {
                Text(L("Version %@ · Build: %@", Self.version, Self.build))
            }
            .buttonStyle(.plain)
        }
        .font(.caption).foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    /// Both of a style's glyphs, hidden icons then shown icons, either side of a slash, as one
    /// template image, since a menu item has room for a single image.
    private static var pairImages: [IconStyle: NSImage] = [:]
    private static func pairImage(_ style: IconStyle) -> NSImage {
        if let cached = pairImages[style] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let glyphs = [true, false].compactMap {
            NSImage(systemSymbolName: style.symbol(collapsed: $0), accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
        let slash = NSAttributedString(string: "/", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .light), .foregroundColor: NSColor.black,
        ])
        let gap: CGFloat = 5
        let height = max(glyphs.map(\.size.height).max() ?? 16, slash.size().height)
        let width = glyphs.map(\.size.width).reduce(0, +) + slash.size().width + gap * 2
        let image = NSImage(size: NSSize(width: ceil(width), height: ceil(height)))
        image.lockFocus()
        var x: CGFloat = 0
        func place(_ size: NSSize, _ draw: (NSPoint) -> Void) {
            draw(NSPoint(x: x, y: (height - size.height) / 2))
            x += size.width + gap
        }
        for (index, glyph) in glyphs.enumerated() {
            if index == 1 { place(slash.size()) { slash.draw(at: $0) } }
            place(glyph.size) { glyph.draw(at: $0, from: .zero, operation: .sourceOver, fraction: 1) }
        }
        image.unlockFocus()
        image.isTemplate = true
        pairImages[style] = image
        return image
    }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    private var header: some View {
        HStack(spacing: 12) {
            AppBadge()
            VStack(alignment: .leading, spacing: 2) {
                Text("StatusCollapse").font(.title3.bold())
                Text(L("Hide menu bar icons you rarely need.")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// A titled, rounded group of settings.
    private func card<Content: View>(_ title: String, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
        }
    }

    /// A numbered instruction.
    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(red: 0.05, green: 0.55, blue: 0.62), in: Circle())
            text.fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A setting: title and explanation on the left, its control on the right.
    private func row<Control: View>(_ title: String, detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            control().labelsHidden().fixedSize()
        }
    }
}

