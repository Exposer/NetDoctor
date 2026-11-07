import Foundation
import Network
import AppKit

/// One finished speed test (`networkQuality`). Speeds are in Mbps, `rpm` is the responsiveness (round trips per
/// minute under load: >= 1000 is good, < 300 is poor), `rtt` the idle latency in ms. Both are nil when macOS did
/// not report them.
struct SpeedRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    let time: Date
    let down: Double
    let up: Double
    let rpm: Double?
    let rtt: Double?
}

enum SpeedParser {
    /// Reads the JSON that `networkQuality -c` prints. nil when it holds no throughput at all (a failed test
    /// still prints JSON, with an error code and zero throughput).
    static func parse(_ data: Data, time: Date = Date()) -> SpeedRecord? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        let dl = num("dl_throughput"), ul = num("ul_throughput")
        guard (dl ?? 0) + (ul ?? 0) > 0 else { return nil }
        let rpm = num("responsiveness")
        return SpeedRecord(time: time, down: (dl ?? 0) / 1_000_000, up: (ul ?? 0) / 1_000_000,
                           rpm: (rpm ?? 0) > 0 ? rpm : nil, rtt: num("base_rtt"))
    }
}

struct SpeedStats: Equatable {
    let count: Int
    let avgDown: Double
    let avgUp: Double
    let minDown: Double
    let minUp: Double
    let lowestRPM: Double?
    let latest: SpeedRecord

    static func summary(_ records: [SpeedRecord]) -> SpeedStats? {
        guard let latest = records.max(by: { $0.time < $1.time }) else { return nil }
        let n = Double(records.count)
        return SpeedStats(count: records.count,
                          avgDown: records.reduce(0) { $0 + $1.down } / n,
                          avgUp: records.reduce(0) { $0 + $1.up } / n,
                          minDown: records.map { $0.down }.min() ?? 0,
                          minUp: records.map { $0.up }.min() ?? 0,
                          lowestRPM: records.compactMap { $0.rpm }.min(),
                          latest: latest)
    }

    /// Records inside [from, to], oldest first.
    static func window(_ records: [SpeedRecord], from: Date, to: Date) -> [SpeedRecord] {
        records.filter { $0.time >= from && $0.time <= to }.sorted { $0.time < $1.time }
    }

    static func pruned(_ records: [SpeedRecord], now: Date, maxAge: TimeInterval, maxCount: Int) -> [SpeedRecord] {
        var r = records.filter { now.timeIntervalSince($0.time) <= maxAge }.sorted { $0.time < $1.time }
        if r.count > maxCount { r.removeFirst(r.count - maxCount) }
        return r
    }

    /// Whether an automatic test is due: the interval is on and the last test is at least one interval old
    /// (a minute of slack, so a timer that fires a little early still runs). Used at launch, so quitting and
    /// reopening the app does not start a test (they use a lot of data) every time.
    static func isDue(last: Date?, now: Date, intervalHours: Int) -> Bool {
        guard intervalHours > 0 else { return false }
        guard let last = last else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(intervalHours * 3600 - 60)
    }

    /// When the next automatic test should fire: one interval after the last test (so relaunching the app does not
    /// push it back), but never in the past: when it is already overdue (a failed or skipped run) try again
    /// after `retryAfter`.
    static func nextRun(last: Date?, now: Date, intervalHours: Int, retryAfter: TimeInterval = 1800) -> Date {
        let due = (last ?? now).addingTimeInterval(TimeInterval(intervalHours * 3600))
        return due > now ? due : now.addingTimeInterval(retryAfter)
    }

    /// Default gateways of phone hotspots: an iPhone Personal Hotspot hands out 172.20.10.x, Android hotspots
    /// usually 192.168.43.x. Both are metered connections, where a scheduled speed test must not run.
    static func isPhoneHotspot(gateway: String) -> Bool { gateway.hasPrefix("172.20.10.") || gateway.hasPrefix("192.168.43.") }
}

/// The recorded speed tests, kept on disk (Application Support) for 30 days.
final class SpeedHistory: ObservableObject {
    static let shared = SpeedHistory()
    @Published private(set) var records: [SpeedRecord] = []
    private let url: URL?
    static let maxAge: TimeInterval = 30 * 86400
    static let maxCount = 2000

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NetDoctor/speed-history.json")
    }

    init(url: URL? = SpeedHistory.defaultURL) {
        self.url = url
        load()
    }

    func add(_ record: SpeedRecord) {
        records = SpeedStats.pruned(records + [record], now: record.time, maxAge: Self.maxAge, maxCount: Self.maxCount)
        save()
    }

    func clear() { records = []; save() }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func load() {
        guard let url = url, let data = try? Data(contentsOf: url),
              let r = try? Self.decoder.decode([SpeedRecord].self, from: data) else { return }
        records = SpeedStats.pruned(r, now: Date(), maxAge: Self.maxAge, maxCount: Self.maxCount)
    }

    private func save() {
        guard let url = url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(records) { try? data.write(to: url, options: .atomic) }
    }
}

/// Runs `networkQuality` in the background, on demand or on a schedule, and records the result.
final class SpeedCheck: ObservableObject {
    static let shared = SpeedCheck()
    static let intervals = [0, 3, 6, 12, 24]        // hours; 0 = off

    @Published var running = false
    @Published var summary = ""
    /// Automatic test every N hours (0 = off). Kept across launches. Off by default: a test uses a lot of data.
    @Published var intervalHours: Int = {
        let v = UserDefaults.standard.integer(forKey: "speedIntervalHours")
        return SpeedCheck.intervals.contains(v) ? v : 0
    }() {
        didSet {
            guard intervalHours != oldValue else { return }
            UserDefaults.standard.set(intervalHours, forKey: "speedIntervalHours")
            reschedule()
            runIfDue()
        }
    }

    private func runIfDue() {
        if SpeedStats.isDue(last: history.records.last?.time, now: Date(), intervalHours: intervalHours) { run(scheduled: true) }
    }

    /// Changing the interval from the UI. Turning the automatic test on from "Off" asks first: a test uses a lot
    /// of data and starts right away.
    func requestInterval(_ hours: Int) {
        guard hours != intervalHours else { return }
        if intervalHours == 0, hours > 0 {
            let a = NSAlert()
            a.messageText = loc("Turn on automatic speed tests?")
            a.informativeText = loc("Each test uses a lot of data (often several hundred MB, a few GB on a fast line) and the first one starts now. Tests are skipped on metered connections such as a phone hotspot or Low Data Mode.")
            a.addButton(withTitle: loc("Turn on"))
            a.addButton(withTitle: loc("Cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { objectWillChange.send(); return }
        }
        intervalHours = hours
    }

    private var timer: Timer?
    private let history = SpeedHistory.shared

    static func intervalLabel(_ h: Int) -> String {
        switch h {
        case 0: return loc("Off")
        case 24: return loc("Every day")
        default: return String(format: loc("Every %d hours"), h)
        }
    }

    /// Call once at launch.
    func start() {
        reschedule()
        runIfDue()
    }

    private func reschedule() {
        timer?.invalidate(); timer = nil
        guard intervalHours > 0 else { return }
        // One shot at "last test + interval", re-armed when a run finishes: a repeating timer started at launch would
        // be pushed back by every relaunch (and drifts over sleep / wake).
        let due = SpeedStats.nextRun(last: history.records.last?.time, now: Date(), intervalHours: intervalHours)
        let t = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in self?.run(scheduled: true) }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Network.framework knows about Personal Hotspot and cellular ("expensive") and Low Data Mode ("constrained").
    /// No answer within 2 s counts as metered ("unknown"): the test is skipped and tried again later, rather than
    /// risking gigabytes on a hotspot.
    private static func pathIsMetered() -> Bool {
        let monitor = NWPathMonitor()
        let sem = DispatchSemaphore(value: 0)
        var metered = false
        monitor.pathUpdateHandler = { path in metered = path.isExpensive || path.isConstrained; sem.signal() }
        monitor.start(queue: DispatchQueue(label: "netdoctor.speed.path"))
        let answered = sem.wait(timeout: .now() + 2) == .success
        monitor.cancel()
        return !answered || metered
    }

    private static func defaultGateway() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/route")
        p.arguments = ["-n", "get", "default"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        for l in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            let s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("gateway:") { return s.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces) }
        }
        return ""
    }

    func run(scheduled: Bool = false) {
        guard !running else { return }
        let tool = "/usr/bin/networkQuality"
        guard FileManager.default.isExecutableFile(atPath: tool) else { summary = loc("Could not run the speed test (macOS 12+ is required)"); return }
        running = true; summary = loc("Testing…")
        DispatchQueue.global().async {
            if scheduled, SpeedCheck.pathIsMetered() || SpeedStats.isPhoneHotspot(gateway: SpeedCheck.defaultGateway()) {
                DispatchQueue.main.async { self.running = false; self.summary = loc("Skipped: this connection is metered (phone hotspot or Low Data Mode)"); self.reschedule() }
                return
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = ["-c", "-M", "30"]      // JSON output, at most 30 s per run
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var record: SpeedRecord?
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                record = SpeedParser.parse(data)
            }
            DispatchQueue.main.async {
                self.running = false
                defer { self.reschedule() }      // the next automatic test is one interval after this one
                if let r = record {
                    self.history.add(r)
                    self.summary = String(format: loc("Speed test: down %.0f Mbps, up %.0f Mbps"), r.down, r.up)
                } else {
                    self.summary = loc("The speed test failed (no connection, or Apple's test server is not reachable)")
                }
            }
        }
    }
}
