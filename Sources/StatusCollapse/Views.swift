import SwiftUI

/// Settings, plus a first-run wizard shown in the same window.
struct RootView: View {
    let controller: Controller
    @AppStorage(Controller.setupKey) private var setupComplete = false

    var body: some View {
        if setupComplete {
            SettingsView(controller: controller, rerunSetup: { setupComplete = false })
        } else {
            WizardView(controller: controller, finish: { setupComplete = true })
        }
    }
}

// MARK: - Wizard

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
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish", action: finish).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440, height: 340)
        .onChange(of: step) { _, new in
            // Keep icons visible while the user arranges them.
            if new == 1 { controller.setCollapsed(false) }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chevron.left.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Welcome to StatusCollapse").font(.title2.bold())
            Text("Hide menu bar icons you rarely need and reveal them with one click.")
            Label("No permissions needed. It only manages its own menu bar items, so the clock and Notification Center keep working normally.", systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        }
    }

    private var arrange: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose which icons to hide").font(.title2.bold())
            Text("Look for the \(Image(systemName: controller.iconStyle.symbol(collapsed: false))) button in your menu bar.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Hold ⌘ and drag icons to the **left** of the button to hide them. You can ⌘-drag the button too.")
                Text("2. Collapsing hides everything left of the button. Icons to its right always stay visible.")
            }
            Text("Apple's menu bar doesn't let apps move other apps' icons, so this one step is manual. Positions are remembered.")
                .font(.callout).foregroundStyle(.secondary)
            Button(controller.isCollapsed ? "Show icons" : "Try collapsing") {
                controller.setCollapsed(!controller.isCollapsed)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're all set").font(.title2.bold())
            Text("Click the \(Image(systemName: controller.iconStyle.symbol(collapsed: false))) button to hide or show icons. Right-click it for Settings and Quit.")
            Toggle("Open at login", isOn: Binding(
                get: { controller.launchAtLogin }, set: controller.setLaunchAtLogin))
            if let error = controller.launchError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @Bindable var controller: Controller
    let rerunSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            card("How it works", systemImage: "questionmark.circle") {
                step(1, "Find the \(Image(systemName: controller.iconStyle.symbol(collapsed: false))) button in your menu bar.")
                step(2, "Hold ⌘ and drag icons to the **left** of the button to make them hideable.")
                step(3, "Click the button to hide or show them. Icons to its right always stay visible.")
            }
            card("Menu bar", systemImage: "menubar.rectangle") {
                row("Icon", detail: "The button you click to hide or show icons.",
                    help: "Choose the look of the toggle button") {
                    Picker("Icon", selection: $controller.iconStyle) {
                        ForEach(IconStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbol(collapsed: false)).tag(style)
                        }
                    }
                }
                Divider()
                row("Auto-hide", detail: "Hides icons again after you reveal them.",
                    help: "Re-collapse automatically after a delay") {
                    Picker("Auto-hide", selection: $controller.autoHideSeconds) {
                        ForEach(Controller.autoHideChoices, id: \.self) { seconds in
                            Text(seconds == 0 ? "Never" : "After \(seconds) seconds").tag(seconds)
                        }
                    }
                }
                Divider()
                row("Open at login", detail: "Starts StatusCollapse when you sign in.",
                    help: "Launch automatically at login") {
                    Toggle("Open at login", isOn: Binding(
                        get: { controller.launchAtLogin }, set: controller.setLaunchAtLogin))
                        .toggleStyle(.switch)
                }
                if let error = controller.launchError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            card("Icons", systemImage: "square.grid.2x2") {
                Text("Icons stay shown while this window is open so they're easy to arrange. Positions are remembered. macOS doesn't let apps move other apps' icons, so arranging is manual.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { rerunSetup() } label: { Label("Run Setup", systemImage: "arrow.counterclockwise") }
                        .help("Show the first-run walkthrough again")
                    Button { controller.resetLayout() } label: { Label("Reset Layout", systemImage: "arrow.uturn.backward") }
                        .help("Recreate the button if it's missing")
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                    } label: { Label("System Settings", systemImage: "gearshape") }
                        .help("Open Menu Bar settings in System Settings")
                }
                .controlSize(.regular)
            }
            VStack(spacing: 2) {
                Text("Right-click the menu bar button for Settings and Quit.")
                Text("Version \(Self.version) · Build: \(Self.build)")
            }
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

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
                Text("Hide menu bar icons you rarely need.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

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

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(red: 0.05, green: 0.55, blue: 0.62), in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<Control: View>(_ title: String, detail: String, help: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control().labelsHidden().fixedSize().help(help)
        }
    }
}
