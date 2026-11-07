import SwiftUI

@main
struct NetDoctorApp: App {
    @StateObject private var monitor = LatencyMonitor()
    @StateObject private var health = HealthCheck()
    @State private var loginItem = LoginItem.isEnabled
    @State private var loginError = ""
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
            Button(LocalizedStringKey(health.running ? "Checking…" : "Run health check")) { health.run() }.disabled(health.running)
            if !health.summary.isEmpty { Text(health.summary) }
            Divider()
            Button(LocalizedStringKey(monitor.running ? "Stop monitoring" : "Start monitoring")) {
                monitor.running ? monitor.stop() : monitor.start()
            }
            Toggle("Notify when the connection drops", isOn: $monitor.notifyOnLoss)
            Toggle("Open at login", isOn: Binding(get: { loginItem }, set: { on in
                loginError = LoginItem.set(on) ?? ""
                loginItem = LoginItem.isEnabled
            }))
            if !loginError.isEmpty { Text(loginError) }
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
