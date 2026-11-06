import SwiftUI

@main
struct NetDoctorApp: App {
    @StateObject private var monitor = LatencyMonitor()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("NetDoctor Network Diagnostics", id: "main") {
            ContentView().environmentObject(monitor)
        }
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            Text(String(format: loc("Target %@"), monitor.target))
            if let a = monitor.avg { Text(String(format: loc("Avg %.0f ms · Loss %.0f%%"), a, monitor.lossPercent)) }
            Divider()
            Button(LocalizedStringKey(monitor.running ? "Stop monitoring" : "Start monitoring")) {
                monitor.running ? monitor.stop() : monitor.start()
            }
            Button("Open main window") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Label(monitor.menuTitle, systemImage: "network")
        }
    }
}
