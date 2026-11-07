import SwiftUI
import Charts

/// Shared navigation state, so the menu bar can open the main window on a given page.
final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var selection: String? = "quick"
}

struct HealthHistoryView: View {
    @ObservedObject private var history = HealthHistory.shared
    @ObservedObject private var health = HealthCheck.shared
    @State private var range: Range = .day
    @State private var confirmClear = false

    enum Range: String, CaseIterable, Identifiable {
        case sixHours, day, week
        var id: String { rawValue }
        var seconds: TimeInterval { switch self { case .sixHours: return 6 * 3600; case .day: return 86400; case .week: return 7 * 86400 } }
        var title: String { switch self { case .sixHours: return loc("Last 6 hours"); case .day: return loc("Last 24 hours"); case .week: return loc("Last 7 days") } }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in content(now: ctx.date) }
            .padding(16)
    }

    private func color(_ s: Severity) -> Color { s == .good ? .green : (s == .warning ? .orange : .red) }

    /// Records further apart than this are not joined: the app was closed or the Mac asleep in between.
    private var gapLimit: TimeInterval { HealthCheck.gap(forIntervalMinutes: health.intervalMinutes) }

    @ViewBuilder private func content(now: Date) -> some View {
        let from = now.addingTimeInterval(-range.seconds)
        let all = HealthTimeline.episodes(history.records, gapLimit: gapLimit, now: now)
        let eps = HealthTimeline.clipped(all, from: from, to: now)
        let problems = eps.filter { $0.severity != .good }.sorted { $0.start > $1.start }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Health history", systemImage: "waveform.path.ecg").font(.title2.bold())
                Text("Runs the diagnosis in the background and records the result, so you can see when and at which layer the network had problems.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Picker("Automatic health check", selection: $health.intervalMinutes) {
                    ForEach(HealthCheck.intervals, id: \.self) { Text(HealthCheck.intervalLabel($0)).tag($0) }
                }
                .frame(maxWidth: 300)
                Picker("", selection: $range) { ForEach(Range.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                Button(LocalizedStringKey(health.running ? "Checking…" : "Run now")) { health.run() }.disabled(health.running)
                Button("Clear history") { confirmClear = true }.disabled(history.records.isEmpty)
                    .confirmationDialog("Delete all recorded health checks?", isPresented: $confirmClear) {
                        Button("Clear history", role: .destructive) { history.clear() }
                    }
                Spacer()
            }
            if !health.summary.isEmpty { Text(health.summary).font(.callout).foregroundStyle(.secondary) }
            if history.records.isEmpty {
                Text("No health checks recorded yet. Turn on the automatic check, or run one now.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            } else {
                HStack(spacing: 12) {
                    stat("Healthy", HealthTimeline.healthyShare(eps).map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                    stat("Problem periods", "\(problems.count)", warn: !problems.isEmpty)
                    stat("Checks recorded", "\(history.records.filter { $0.time >= from }.count)")
                }
                Chart {
                    ForEach(eps) { e in
                        BarMark(xStart: .value("From", e.start), xEnd: .value("To", max(e.end, e.start.addingTimeInterval(range.seconds / 400))),
                                y: .value("Status", ""))
                            .foregroundStyle(color(e.severity))
                    }
                }
                .chartXScale(domain: from...now)
                .chartYAxis(.hidden)
                .frame(height: 60)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                HStack(spacing: 14) {
                    legend(.good, "Healthy"); legend(.warning, "Unstable or weak Wi-Fi"); legend(.problem, "Problem")
                    Text("Blank = no data (app closed or Mac asleep)").font(.caption).foregroundStyle(.secondary)
                }
                Text("Problem periods").font(.headline)
                if problems.isEmpty {
                    Label("No problems in this period.", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    List(problems) { e in
                        HStack(spacing: 10) {
                            Circle().fill(color(e.severity)).frame(width: 10, height: 10)
                            Text(e.label).bold()
                            Spacer()
                            Text(HealthHistoryView.span(e)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .listStyle(.inset)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legend(_ s: Severity, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: 5) { Circle().fill(color(s)).frame(width: 9, height: 9); Text(key).font(.caption) }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold()).foregroundColor(warn ? .red : .primary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    /// "10:05 – 10:40 (35 min)"; with the date when it does not start today.
    static func span(_ e: HealthEpisode) -> String {
        let day = DateFormatter(); day.dateStyle = .short; day.timeStyle = .short
        let time = DateFormatter(); time.dateStyle = .none; time.timeStyle = .short
        let cal = Calendar.current
        let start = cal.isDateInToday(e.start) ? time.string(from: e.start) : day.string(from: e.start)
        let end = cal.isDate(e.start, inSameDayAs: e.end) ? time.string(from: e.end) : day.string(from: e.end)
        return "\(start) – \(end) (\(duration(e.duration)))"
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = max(1, Int((s / 60).rounded()))
        return m < 60 ? String(format: loc("%d min"), m) : String(format: loc("%d h %d min"), m / 60, m % 60)
    }
}
