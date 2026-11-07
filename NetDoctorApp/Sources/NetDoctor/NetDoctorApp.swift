import SwiftUI

@main
struct NetDoctorApp: App {
    @StateObject private var monitor = LatencyMonitor()
    @StateObject private var health = HealthCheck.shared
    @StateObject private var speed = SpeedCheck.shared
    @State private var loginItem = LoginItem.isEnabled
    @State private var loginError = ""
    @Environment(\.openWindow) private var openWindow

    init() { HealthCheck.shared.start(); SpeedCheck.shared.start() }   // the menu bar content is built lazily; the timer must not wait for it

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
            Menu("Automatic health check") {
                Picker("Automatic health check", selection: $health.intervalMinutes) {
                    ForEach(HealthCheck.intervals, id: \.self) { Text(HealthCheck.intervalLabel($0)).tag($0) }
                }.pickerStyle(.inline)
            }
            Button("Show health history") {
                Navigation.shared.selection = "health"
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Menu("Automatic speed test") {
                Picker("Automatic speed test", selection: Binding(get: { speed.intervalHours }, set: { speed.requestInterval($0) })) {
                    ForEach(SpeedCheck.intervals, id: \.self) { Text(SpeedCheck.intervalLabel($0)).tag($0) }
                }.pickerStyle(.inline)
            }
            Button("Show speed history") {
                Navigation.shared.selection = "speed-history"
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
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
