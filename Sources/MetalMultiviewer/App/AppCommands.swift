import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: MonitorAppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink()
        }

        CommandMenu("View") {
            Button("1-Up Layout") {
                model.setLayout(.oneUp)
            }
            .keyboardShortcut("1")

            Button("Multiview Layout") {
                model.setLayout(.fourUp)
            }
            .keyboardShortcut("4")

            Divider()

            Button("Open Program Monitor") {
                try? model.openProgramMonitor()
            }
            .disabled(model.programCoordinator != nil)

            Divider()

            Button("Toggle Focus Peaking") {
                model.toggleFocusPeaking()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Toggle False Color") {
                model.toggleFalseColor()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Toggle Zebra") {
                model.toggleZebra()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()

            Button("Configure Inputs…") {
                model.showSourcesEditor = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button("Acknowledgments…") {
                let alert = NSAlert()
                alert.messageText = "Acknowledgments"
                alert.informativeText = NdiAttribution.acknowledgmentsMessage()
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open ndi.video")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn {
                    NdiAttribution.openWebsite()
                }
            }
        }
    }
}
