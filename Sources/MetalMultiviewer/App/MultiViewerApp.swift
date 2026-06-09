import SwiftUI

@main
struct MultiViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = MonitorAppModel()

    var body: some Scene {
        WindowGroup {
            MainMonitorView(model: model)
                .task {
                    appDelegate.attach(model: model)
                }
        }
        .defaultSize(width: 1280, height: 720)
        .commands {
            AppCommands(model: model)
        }

        Settings {
            PreferencesView(model: model)
        }
    }
}
