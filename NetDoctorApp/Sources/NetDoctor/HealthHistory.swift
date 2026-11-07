import Foundation

enum Severity: Int { case good, warning, problem }

/// One health check result. `verdict` is the code printed by `netdoctor doctor` (ok, dns, wifi, …), so the
/// history stays meaningful when the app language changes: the label is looked up when it is shown.
struct HealthRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    let time: Date
    let verdict: String
    /// How long this record may stand for when no newer record follows (set from the check interval in force
    /// when it was taken, so changing the interval later does not rewrite the past). nil in older files.
    var gap: TimeInterval? = nil

    var severity: Severity { HealthRecord.severity(of: verdict) }
    var label: String { HealthRecord.label(for: verdict) }

    static func severity(of verdict: String) -> Severity {
        switch verdict {
        case "ok": return .good
        case "unstable", "wifi": return .warning
        default: return .problem
        }
    }

    static func label(for verdict: String) -> String {
        switch verdict {
        case "ok": return loc("Healthy")
        case "link": return loc("Not connected to any network")
        case "dhcp": return loc("No IP address from the router (DHCP failed)")
        case "gateway": return loc("Router unreachable")
        case "internet": return loc("No internet access")
        case "dns", "dns_all": return loc("DNS problem")
        case "captive": return loc("Wi-Fi login page blocks access")
        case "clock": return loc("The Mac's clock is wrong")
        case "http": return loc("Web access fails")
        case "unstable": return loc("Unstable connection")
        case "wifi": return loc("Weak Wi-Fi signal")
        default: return loc("Problem")
        }
    }
}

/// A stretch of time with the same verdict.
struct HealthEpisode: Identifiable, Equatable {
    var id: Date { start }
    let start: Date
    let end: Date
    let verdict: String
    var severity: Severity { HealthRecord.severity(of: verdict) }
    var label: String { HealthRecord.label(for: verdict) }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum HealthTimeline {
    /// Turns the records (any order) into episodes. A record describes the time until the next record, but at
    /// most the record's own `gap` (`gapLimit` for records without one; the app was closed or the Mac asleep: that time is unknown and left empty). The last
    /// record reaches up to `now` while it is recent. Consecutive records with the same verdict and no gap
    /// between them become one episode.
    static func episodes(_ records: [HealthRecord], gapLimit: TimeInterval, now: Date) -> [HealthEpisode] {
        let sorted = records.sorted { $0.time < $1.time }
        var out: [HealthEpisode] = []
        for (i, r) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].time : now
            let end = max(r.time, min(next, r.time.addingTimeInterval(r.gap ?? gapLimit)))
            if let last = out.last, last.verdict == r.verdict, last.end >= r.time {
                out[out.count - 1] = HealthEpisode(start: last.start, end: end, verdict: r.verdict)
            } else {
                out.append(HealthEpisode(start: r.time, end: end, verdict: r.verdict))
            }
        }
        return out
    }

    /// Share of the covered time that was healthy (0…1); nil when nothing is covered.
    static func healthyShare(_ episodes: [HealthEpisode]) -> Double? {
        let total = episodes.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return nil }
        return episodes.filter { $0.severity == .good }.reduce(0) { $0 + $1.duration } / total
    }

    /// Keeps the part of the episodes inside [from, to] (episodes crossing the edge are cut).
    static func clipped(_ episodes: [HealthEpisode], from: Date, to: Date) -> [HealthEpisode] {
        episodes.compactMap { e in
            let s = max(e.start, from), t = min(e.end, to)
            return t > s || (e.start >= from && e.start <= to) ? HealthEpisode(start: s, end: max(s, t), verdict: e.verdict) : nil
        }
    }

    static func pruned(_ records: [HealthRecord], now: Date, maxAge: TimeInterval, maxCount: Int) -> [HealthRecord] {
        var r = records.filter { now.timeIntervalSince($0.time) <= maxAge }.sorted { $0.time < $1.time }
        if r.count > maxCount { r.removeFirst(r.count - maxCount) }
        return r
    }
}

/// The recorded health checks, kept on disk (Application Support) for two weeks.
final class HealthHistory: ObservableObject {
    static let shared = HealthHistory()
    @Published private(set) var records: [HealthRecord] = []
    private let url: URL?
    static let maxAge: TimeInterval = 14 * 86400
    static let maxCount = 5000

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NetDoctor/health-history.json")
    }

    init(url: URL? = HealthHistory.defaultURL) {
        self.url = url
        load()
    }

    func add(verdict: String, at time: Date = Date(), gap: TimeInterval? = nil) {
        records = HealthTimeline.pruned(records + [HealthRecord(time: time, verdict: verdict, gap: gap)], now: time,
                                        maxAge: Self.maxAge, maxCount: Self.maxCount)
        save()
    }

    func clear() { records = []; save() }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    private func load() {
        guard let url = url, let data = try? Data(contentsOf: url),
              let r = try? Self.coder().1.decode([HealthRecord].self, from: data) else { return }
        records = HealthTimeline.pruned(r, now: Date(), maxAge: Self.maxAge, maxCount: Self.maxCount)
    }

    private func save() {
        guard let url = url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.coder().0.encode(records) { try? data.write(to: url, options: .atomic) }
    }
}
