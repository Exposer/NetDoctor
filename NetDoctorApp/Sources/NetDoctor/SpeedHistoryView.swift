import SwiftUI
import Charts

struct SpeedHistoryView: View {
    @ObservedObject private var history = SpeedHistory.shared
    @ObservedObject private var check = SpeedCheck.shared
    @State private var range: Range = .week
    @State private var confirmClear = false

    enum Range: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var seconds: TimeInterval { switch self { case .day: return 86400; case .week: return 7 * 86400; case .month: return 30 * 86400 } }
        var title: String { switch self { case .day: return loc("Last 24 hours"); case .week: return loc("Last 7 days"); case .month: return loc("Last 30 days") } }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in content(now: ctx.date) }
            .padding(16)
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let from = now.addingTimeInterval(-range.seconds)
        let rs = SpeedStats.window(history.records, from: from, to: now)
        let stats = SpeedStats.summary(rs)
        let rpmRecords = rs.filter { $0.rpm != nil }
        let dName = loc("Download"), uName = loc("Upload")
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Speed history", systemImage: "speedometer").font(.title2.bold())
                Text("Runs a speed test on a schedule and charts download, upload and responsiveness over time, so you can see whether the line slows down at certain hours.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Picker("Automatic speed test", selection: Binding(get: { check.intervalHours }, set: { check.requestInterval($0) })) {
                    ForEach(SpeedCheck.intervals, id: \.self) { Text(SpeedCheck.intervalLabel($0)).tag($0) }
                }
                .frame(maxWidth: 300)
                Picker("", selection: $range) { ForEach(Range.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Button(LocalizedStringKey(check.running ? "Testing…" : "Run now")) { check.run() }.disabled(check.running)
                Button("Clear history") { confirmClear = true }.disabled(history.records.isEmpty)
                    .confirmationDialog("Delete all recorded speed tests?", isPresented: $confirmClear) {
                        Button("Clear history", role: .destructive) { history.clear() }
                    }
                Spacer()
            }
            Text("A speed test uses a lot of data (often several hundred MB, on a fast line a few GB). Automatic tests are off by default and are skipped on metered connections such as a phone hotspot.")
                .font(.caption).foregroundStyle(.secondary)
            if !check.summary.isEmpty { Text(check.summary).font(.callout).foregroundStyle(.secondary) }
            if history.records.isEmpty {
                Text("No speed tests recorded yet. Turn on the automatic test, or run one now.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            } else if let s = stats {
                HStack(spacing: 12) {
                    stat("Latest download", String(format: "%.0f Mbps", s.latest.down))
                    stat("Latest upload", String(format: "%.0f Mbps", s.latest.up))
                    stat("Average download", String(format: "%.0f Mbps", s.avgDown))
                    stat("Average upload", String(format: "%.0f Mbps", s.avgUp))
                    stat("Lowest responsiveness", s.lowestRPM.map { String(format: "%.0f RPM", $0) } ?? "—", warn: (s.lowestRPM ?? 1000) < 300)
                    stat("Tests recorded", "\(s.count)")
                }
                Text("Download and upload (Mbps)").font(.headline)
                Chart {
                    ForEach(rs) { r in
                        LineMark(x: .value("Time", r.time), y: .value("Mbps", r.down), series: .value("Direction", dName))
                            .foregroundStyle(by: .value("Direction", dName))
                        PointMark(x: .value("Time", r.time), y: .value("Mbps", r.down))
                            .foregroundStyle(by: .value("Direction", dName))
                        LineMark(x: .value("Time", r.time), y: .value("Mbps", r.up), series: .value("Direction", uName))
                            .foregroundStyle(by: .value("Direction", uName))
                        PointMark(x: .value("Time", r.time), y: .value("Mbps", r.up))
                            .foregroundStyle(by: .value("Direction", uName))
                    }
                }
                .chartForegroundStyleScale([dName: Color.blue, uName: Color.green])
                .chartXScale(domain: from...now)
                .frame(minHeight: 150)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                Text("Responsiveness (RPM, higher is better)").font(.headline)
                Chart {
                    RuleMark(y: .value("Poor", 300)).foregroundStyle(.red.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("Good", 1000)).foregroundStyle(.green.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(rpmRecords) { r in
                        LineMark(x: .value("Time", r.time), y: .value("RPM", r.rpm ?? 0)).foregroundStyle(.orange)
                        PointMark(x: .value("Time", r.time), y: .value("RPM", r.rpm ?? 0)).foregroundStyle(.orange)
                    }
                }
                .chartXScale(domain: from...now)
                .frame(height: 110)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                Text("Below the red line (300) video calls and games lag under load; above the green line (1000) the line stays snappy.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No speed tests in this period.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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
