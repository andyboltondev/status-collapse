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
            Text("Look for the divider \(Text("│").foregroundStyle(.secondary)) and the \(Image(systemName: controller.iconStyle.symbol(collapsed: false))) button in your menu bar.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Hold ⌘ and drag icons to the **left** of the divider to hide them. You can ⌘-drag the divider too.")
                Text("2. Collapsing hides everything left of the divider. Icons to its right always stay visible.")
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
        Form {
            Section("Menu bar") {
                Picker("Icon", selection: $controller.iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Label(style.title, systemImage: style.symbol(collapsed: false)).tag(style)
                    }
                }
                Picker("Auto-hide", selection: $controller.autoHideSeconds) {
                    ForEach(Controller.autoHideChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? "Never" : "After \(seconds) seconds").tag(seconds)
                    }
                }
            }
            Section("Icons") {
                Text("Icons stay shown while Settings is open. Hold ⌘ and drag them left of the divider to hide them, or right of it to keep them visible.")
                    .foregroundStyle(.secondary)
                Button("Run Setup Again", action: rerunSetup)
                Button("Reset Layout") { controller.resetLayout() }
                Button("Menu Bar System Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                }
            }
            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { controller.launchAtLogin }, set: controller.setLaunchAtLogin))
                if let error = controller.launchError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
    }
}
