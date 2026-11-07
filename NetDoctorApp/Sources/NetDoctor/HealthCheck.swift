import Foundation

/// Runs `netdoctor doctor` in the background (no window) and keeps a one-line result for the menu bar.
final class HealthCheck: ObservableObject {
    @Published var running = false
    @Published var summary = ""     // e.g. "12:03  Everything looks healthy."
    @Published var healthy: Bool? = nil

    func run() {
        guard !running else { return }
        guard let script = Runner.scriptPath else { summary = loc("netdoctor script not found"); return }
        running = true; summary = loc("Running…")
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script, "doctor"]
            var env = Runner.env
            env["NETDOCTOR_COLOR"] = nil          // plain text: we only read the verdict line
            env["NETDOCTOR_NOSUDO"] = "1"
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
            DispatchQueue.main.async {
                self.running = false
                let t = DateFormatter(); t.timeStyle = .short; t.dateStyle = .none
                if code < 0 || verdict.isEmpty {
                    self.healthy = nil
                    self.summary = loc("Could not run the health check")
                } else {
                    self.healthy = (code == 0)
                    self.summary = "\(t.string(from: Date()))  \(verdict)"
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
}
