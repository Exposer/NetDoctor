import SwiftUI
import Charts

private let termBg = Color(red: 0.07, green: 0.08, blue: 0.10)

struct ContentView: View {
    @StateObject private var store = RunnerStore()
    @EnvironmentObject var monitor: LatencyMonitor
    @State private var selection: String? = "quick"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Diagnostics") {
                    ForEach(Tool.all) { t in
                        Label(LocalizedStringKey(t.title), systemImage: t.icon).tag(Optional(t.id))
                    }
                }
                Section("Monitoring") {
                    Label("Live latency", systemImage: "chart.xyaxis.line").tag(Optional("monitor"))
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            if selection == "monitor" {
                MonitorView()
            } else if let t = Tool.all.first(where: { $0.id == selection }) {
                ToolView(runner: store.runner(for: t))
            } else {
                Text("Select a tool on the left").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct ToolView: View {
    @ObservedObject var runner: Runner
    private var tool: Tool { runner.tool }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(LocalizedStringKey(tool.title), systemImage: tool.icon).font(.title2.bold())
                Text(LocalizedStringKey(tool.summary)).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(tool.inputs) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(LocalizedStringKey(i.label)) + Text(i.required ? " *" : "")).font(.caption).foregroundStyle(.secondary)
                        TextField(i.placeholder, text: Binding(
                            get: { runner.values[i.name] ?? "" },
                            set: { runner.values[i.name] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160, maxWidth: 280)
                            .onSubmit { runner.run() }
                    }
                }
                if tool.admin == .optional {
                    Toggle("Administrator rights (fuller details)", isOn: $runner.useAdmin).toggleStyle(.checkbox)
                } else if tool.admin == .required {
                    Label("Requires administrator rights", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                }
                Button(LocalizedStringKey(runner.running ? "Running…" : "Run")) { runner.run() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(runner.running)
                Button("Stop") { runner.stop() }.disabled(!runner.running || runner.useAdmin || tool.admin == .required)
                Spacer()
            }
            TerminalView(text: runner.output, running: runner.running)
            HStack {
                if runner.running { ProgressView().controlSize(.small) }
                Text(runner.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { runner.copy() }.disabled(runner.plain.isEmpty)
                Button("Save…") { runner.save() }.disabled(runner.plain.isEmpty)
            }
        }
        .padding(16)
    }
}

struct TerminalView: View {
    let text: AttributedString
    let running: Bool
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if text.characters.isEmpty {
                        Text(LocalizedStringKey(running ? "" : "Click “Run” to start. Try “Quick check” first."))
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    } else {
                        Text(text).textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(termBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: text.characters.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

struct MonitorView: View {
    @EnvironmentObject var m: LatencyMonitor
    private let presets = ["1.1.1.1", "8.8.8.8", "223.5.5.5", "114.114.114.114"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Live latency", systemImage: "chart.xyaxis.line").font(.title2.bold())
                Text("Pings once a second; red lines mark packet loss. The menu bar shows the current latency.").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Target", text: $m.target).textFieldStyle(.roundedBorder).frame(width: 220)
                Menu("Presets") { ForEach(presets, id: \.self) { p in Button(p) { m.target = p; m.clear() } } }
                    .frame(width: 80)
                Button(LocalizedStringKey(m.running ? "Stop" : "Start")) { m.running ? m.stop() : m.start() }
                    .buttonStyle(.borderedProminent)
                Button("Clear") { m.clear() }
                Spacer()
            }
            HStack(spacing: 12) {
                stat("Now", m.last.map { String(format: "%.0f ms", $0) } ?? "—")
                stat("Average", m.avg.map { String(format: "%.1f ms", $0) } ?? "—")
                stat("Min / Max", m.minMs.map { String(format: "%.0f / %.0f ms", $0, m.maxMs ?? 0) } ?? "—")
                stat("Jitter", m.jitter.map { String(format: "%.1f ms", $0) } ?? "—")
                stat("Loss", String(format: "%.1f%%", m.lossPercent), warn: m.lossPercent > 0)
            }
            Chart {
                ForEach(m.samples) { s in
                    if let ms = s.ms {
                        LineMark(x: .value("Time", s.time), y: .value("ms", ms))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                    } else {
                        RuleMark(x: .value("Time", s.time)).foregroundStyle(Color.red.opacity(0.6))
                    }
                }
            }
            .chartYAxisLabel("ms")
            .frame(minHeight: 240)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold()).foregroundColor(warn ? .red : .primary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
