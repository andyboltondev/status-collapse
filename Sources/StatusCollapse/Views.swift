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
            withIcon("Look for the %@ button in your menu bar.", controller.iconStyle.symbol(collapsed: false))
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
                     controller.iconStyle.symbol(collapsed: false))
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

// MARK: - Window sizing

private struct TabHeightsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Resizes the hosting window to `height` when it first becomes known and whenever it changes
/// (a longer translation, say), so the tabs fit without scrolling. Resizing it by hand still works.
private struct WindowSizer: NSViewRepresentable {
    let height: CGFloat?

    final class Coordinator { var applied: CGFloat? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let height, height != context.coordinator.applied else { return }
        context.coordinator.applied = height
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            var size = window.contentLayoutRect.size
            size.height = height
            window.setContentSize(size)
        }
    }
}

// MARK: - Settings

/// The settings window's content once setup is finished.
private struct SettingsView: View {
    @Bindable var controller: Controller
    let rerunSetup: () -> Void
    @State private var showChangelog = false

    /// Natural height of each tab's content, the height of the window outside the tab area, and
    /// the tab area's width, all measured so the window can be sized to show a tab without scrolling.
    @State private var tabHeights: [Int: CGFloat] = [:]

    /// Everything in the window beyond the header, footer and a tab's content: the window padding,
    /// the gaps between the parts, and the tab control's own bar and margins.
    private static let fixedChrome: CGFloat = 40 + 24 + 30
    /// Widths the header, footer and tab content are laid out at, for measuring them.
    private static let outerWidth: CGFloat = 500
    private static let innerWidth: CGFloat = 476

    private static let minimumSize = CGSize(width: 540, height: 380)
    /// The window opens as tall as its content needs, but no taller than this share of the screen.
    private static let screenShare = 0.8

    /// The window height that shows the tallest tab in full, or nil until it has been measured.
    private var fittingHeight: CGFloat? {
        guard tabHeights.count == 5, let tallest = (0...2).compactMap({ tabHeights[$0] }).max() else { return nil }
        let chrome = tabHeights[3, default: 0] + tabHeights[4, default: 0] + Self.fixedChrome
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(Self.minimumSize.height, min(chrome + tallest, (screen * Self.screenShare).rounded(.down)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TabView(selection: $controller.settingsTab) {
                tab { menuBarTab }.tabItem { Label(L("Menu bar"), systemImage: "menubar.rectangle") }.tag(0)
                tab { behaviourTab }.tabItem { Label(L("Behaviour"), systemImage: "slider.horizontal.3") }.tag(1)
                tab { generalTab }.tabItem { Label(L("General"), systemImage: "gearshape") }.tag(2)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: Self.minimumSize.width, maxWidth: .infinity,
               minHeight: Self.minimumSize.height, idealHeight: fittingHeight ?? 660, maxHeight: .infinity)
        .background(alignment: .topLeading) { measurer }
        .background(WindowSizer(height: fittingHeight))
        .onPreferenceChange(TabHeightsKey.self) { tabHeights = $0 }
    }

    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.vertical, 8).padding(.horizontal, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Invisible copies of every tab at the visible tab's width, which only report their heights.
    private var measurer: some View {
        ZStack(alignment: .top) {
            measured(0, menuBarTab, width: Self.innerWidth)
            measured(1, behaviourTab, width: Self.innerWidth)
            measured(2, generalTab, width: Self.innerWidth)
            measured(3, header, width: Self.outerWidth)
            measured(4, footer, width: Self.outerWidth)
        }
        .hidden().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func measured<Content: View>(_ index: Int, _ content: Content, width: CGFloat) -> some View {
        content
            .padding(.vertical, index < 3 ? 8 : 0).padding(.horizontal, index < 3 ? 4 : 0)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TabHeightsKey.self, value: [index: proxy.size.height])
            })
    }

    // MARK: Tabs

    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(L("How it works"), systemImage: "questionmark.circle") {
                step(1, withIcon("Find the %@ button in your menu bar.", controller.iconStyle.symbol(collapsed: false)))
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
            Button { showChangelog.toggle() } label: {
                Text(L("Version %@ · Build: %@", Self.version, Self.build))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showChangelog, arrowEdge: .top) {
                Text(Self.latestChanges)
                    .font(.callout).textSelection(.enabled)
                    .frame(width: 300, alignment: .leading).padding(14)
            }
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

    /// The newest section of the bundled CHANGELOG.md, as markdown. The changelog is in English.
    private static let latestChanges: AttributedString = {
        let text = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let section = text.components(separatedBy: "\n## ").dropFirst().first ?? ""
        guard !section.isEmpty else { return AttributedString("No changelog available.") }
        let lines = section.split(separator: "\n", omittingEmptySubsequences: true)
        let title = "**\(lines[0])**"
        let items = lines.dropFirst().map { $0.hasPrefix("- ") ? "•" + $0.dropFirst() : String($0) }
        let body = ([title] + items).joined(separator: "\n")
        return (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(body)
    }()

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left.2")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [Color(red: 0.18, green: 0.83, blue: 0.75), Color(red: 0.05, green: 0.45, blue: 0.56)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
