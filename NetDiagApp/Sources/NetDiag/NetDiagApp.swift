import SwiftUI

@main
struct NetDiagApp: App {
    @StateObject private var monitor = LatencyMonitor()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("NetDiag 网络诊断", id: "main") {
            ContentView().environmentObject(monitor)
        }
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            Text("目标 \(monitor.target)")
            if let a = monitor.avg { Text(String(format: "平均 %.0f ms · 丢包 %.0f%%", a, monitor.lossPercent)) }
            Divider()
            Button(monitor.running ? "停止监控" : "开始监控") {
                monitor.running ? monitor.stop() : monitor.start()
            }
            Button("打开主窗口") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Label(monitor.menuTitle, systemImage: "network")
        }
    }
}
