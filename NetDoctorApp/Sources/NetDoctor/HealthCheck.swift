import Foundation

/// Runs `netdoctor doctor` in the background (no window), keeps a one-line result for the menu bar and records
/// every result in `HealthHistory`. It can also run by itself every few minutes.
final class HealthCheck: ObservableObject {
    static let shared = HealthCheck()
    static let intervals = [0, 5, 15, 30, 60]       // minutes; 0 = off

    @Published var running = false
    @Published var summary = ""     // e.g. "12:03  Everything looks healthy."
    @Published var healthy: Bool? = nil
    /// Automatic check every N minutes (0 = off). Kept across launches.
    @Published var intervalMinutes: Int = {
        let v = UserDefaults.standard.integer(forKey: "healthIntervalMinutes")
        return HealthCheck.intervals.contains(v) ? v : 0
    }() {
        didSet {
            guard intervalMinutes != oldValue else { return }
            UserDefaults.standard.set(intervalMinutes, forKey: "healthIntervalMinutes")
            reschedule()
            if intervalMinutes > 0 { run(scheduled: true) }     // switching it on checks right away
        }
    }

    private var timer: Timer?
    private let history = HealthHistory.shared

    static func intervalLabel(_ m: Int) -> String {
        switch m {
        case 0: return loc("Off")
        case 60: return loc("Every hour")
        default: return String(format: loc("Every %d minutes"), m)
        }
    }

    /// Call once at launch: starts the timer when automatic checks were switched on earlier.
    func start() {
        reschedule()
        if intervalMinutes > 0 { run(scheduled: true) }     // and once now, so the history has a point from the moment the app starts
    }

    /// How long a record stands for when nothing newer follows: two check intervals (at least 10 minutes).
    static func gap(forIntervalMinutes m: Int) -> TimeInterval { TimeInterval(max(m, 5) * 60 * 2) }

    private func reschedule() {
        timer?.invalidate(); timer = nil
        guard intervalMinutes > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in self?.run(scheduled: true) }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The re-check after a failed scheduled run. If another check is running at that moment (the user pressed
    /// "Run health check", or the timer fired), try again a few seconds later instead of dropping it silently.
    private func retry(left: Int = 6) {
        if running {
            if left > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.retry(left: left - 1) } }
            return
        }
        run(scheduled: true, retried: true)
    }

    /// `scheduled`: a failing result is checked once more after 20 s before it is recorded, because right
    /// after the Mac wakes up the network is often not back yet, and that would be a false alarm in the history.
    func run(scheduled: Bool = false, retried: Bool = false) {
        guard !running else { return }
        guard let script = Runner.scriptPath else { summary = loc("netdoctor script not found"); return }
        running = true; summary = loc(retried ? "Checking again…" : "Running…")
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script, "doctor"]
            var env = Runner.env
            env["NETDOCTOR_COLOR"] = nil          // plain text: we only read the verdict line
            env["NETDOCTOR_NOSUDO"] = "1"
            env["NETDOCTOR_VERDICT_LINE"] = "1"   // adds a last line "verdict=<code>" for the history
            // Reading the Wi-Fi details (system_profiler) takes ~10 s and scans the radio: fine when the user
            // asks for a check, too heavy for a timer that may fire every 5 minutes.
            if scheduled { env["NETDOCTOR_NOWIFI"] = "1" }
            p.environment = env
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            var text = "", code: Int32 = -1
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit(); code = p.terminationStatus
                text = String(decoding: data, as: UTF8.self)
            }
            let verdict = HealthCheck.verdict(from: text)
            let verdictCode = HealthCheck.code(from: text)
            DispatchQueue.main.async {
                self.running = false
                if scheduled, !retried, let c = verdictCode, c != "ok" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.retry() }
                    self.summary = loc("Checking again…")
                    return
                }
                let t = DateFormatter(); t.timeStyle = .short; t.dateStyle = .none
                if code < 0 || verdict.isEmpty {
                    self.healthy = nil
                    self.summary = loc("Could not run the health check")
                } else {
                    self.healthy = (code == 0)
                    self.summary = "\(t.string(from: Date()))  \(verdict)"
                    if let c = verdictCode { self.history.add(verdict: c, gap: HealthCheck.gap(forIntervalMinutes: self.intervalMinutes)) }
                }
            }
        }
    }

    /// The first line after "== Verdict ==" (or "== 结论 ==") without the [ OK ] / [FAIL] marker.
    static func verdict(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.hasPrefix("== ") && ($0.contains("Verdict") || $0.contains("结论")) }) else { return "" }
        for l in lines.dropFirst(i + 1) {
            var s = l.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if s.hasPrefix("["), let r = s.range(of: "]") { s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
            return s
        }
        return ""
    }

    /// The machine-readable "verdict=<code>" line (only lowercase letters and underscores are accepted).
    static func code(from text: String) -> String? {
        for l in text.components(separatedBy: "\n").reversed() where l.hasPrefix("verdict=") {
            let c = String(l.dropFirst("verdict=".count)).trimmingCharacters(in: .whitespaces)
            if !c.isEmpty, c.range(of: "^[a-z_]+$", options: .regularExpression) != nil { return c }
        }
        return nil
    }
}
