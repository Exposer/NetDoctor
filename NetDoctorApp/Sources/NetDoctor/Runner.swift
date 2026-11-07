import SwiftUI
import AppKit

/// Run state of one tool: inputs, output, process.
final class Runner: ObservableObject {
    let tool: Tool
    @Published var values: [String: String] = [:]
    @Published var useAdmin = false
    @Published var output = AttributedString()
    @Published var plain = ""
    @Published var running = false
    @Published var status = ""

    private var process: Process?
    private var parser = AnsiParser()
    private var pending = Data()
    private var startedAt = Date()
    private var stopped = false

    init(tool: Tool) {
        self.tool = tool
        for i in tool.inputs { values[i.name] = i.defaultValue }
        useAdmin = tool.admin == .required
    }

    // MARK: Locate the netdoctor script
    static var scriptPath: String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["NETDOCTOR_PATH"] { candidates.append(env) }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("netdoctor").path { candidates.append(r) }
        candidates.append(fm.currentDirectoryPath + "/netdoctor")
        candidates.append(fm.currentDirectoryPath + "/../netdoctor")
        return candidates.first { fm.isReadableFile(atPath: $0) }
    }

    /// "zh" when the app is running in a Chinese localization, otherwise "en".
    static var language: String {
        let l = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return l.hasPrefix("zh") ? "zh" : "en"
    }

    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:" + (e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        e["NETDOCTOR_COLOR"] = "1"
        e["NETDOCTOR_LANG"] = Runner.language
        e["LANG"] = "en_US.UTF-8"
        return e
    }()

    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/?&=%@~+,[]-")

    private func buildArgs() throws -> [String] {
        var args: [String] = []
        for i in tool.inputs {
            let v = (values[i.name] ?? "").trimmingCharacters(in: .whitespaces)
            if v.isEmpty {
                if i.required { throw NSError(domain: "netdoctor", code: 1, userInfo: [NSLocalizedDescriptionKey: String(format: loc("Please fill in: %@"), loc(i.label))]) }
                break
            }
            if v.hasPrefix("-") || v.count > 300 || v.unicodeScalars.contains(where: { !Self.allowed.contains($0) }) {
                throw NSError(domain: "netdoctor", code: 2, userInfo: [NSLocalizedDescriptionKey: String(format: loc("Invalid parameter: %@"), loc(i.label))])
            }
            args.append(v)
        }
        return args
    }

    // MARK: Run
    func run() {
        guard !running else { return }
        output = AttributedString(); plain = ""; parser = AnsiParser(); pending = Data(); stopped = false
        guard let script = Runner.scriptPath else {
            status = loc("netdoctor script not found"); return
        }
        let args: [String]
        do { args = try buildArgs() } catch { status = error.localizedDescription; return }

        running = true; status = loc("Running…"); startedAt = Date()
        if useAdmin || tool.admin == .required {
            runAdmin(script: script, args: args)
        } else {
            runStreaming(script: script, args: args)
        }
    }

    private func runStreaming(script: String, args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, tool.id] + args
        p.environment = Runner.env
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.ingest(d) }
        }
        p.terminationHandler = { [weak self] proc in
            // wait for the last data to be read
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.finish(code: proc.terminationStatus)
            }
        }
        do { try p.run(); process = p }
        catch { running = false; status = String(format: loc("Failed to start: %@"), error.localizedDescription) }
    }

    private func runAdmin(script: String, args: [String]) {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let home = NSHomeDirectory()
        let inner = "HOME=\(q(home)) PATH=\(q(Runner.env["PATH"] ?? "")) NETDOCTOR_COLOR=1 NETDOCTOR_LANG=\(Runner.language) /bin/bash "
            + ([script, tool.id] + args).map(q).joined(separator: " ") + " 2>&1"
        let esc = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(esc)\" with administrator privileges"
        append(loc("(Waiting for the system administrator password prompt…)") + "\n")
        DispatchQueue.global().async { [weak self] in
            var err: NSDictionary?
            let script = NSAppleScript(source: src)
            let res: NSAppleEventDescriptor? = script?.executeAndReturnError(&err)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if err == nil, let s = res?.stringValue {
                    self.append(s + "\n"); self.finish(code: 0)
                } else {
                    let msg = (err?["NSAppleScriptErrorMessage"] as? String) ?? loc("Cancelled")
                    self.append("\u{1B}[31m\(msg)\u{1B}[0m\n"); self.finish(code: 1)
                }
            }
        }
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        stopped = true
        // The script starts helpers (ping, nc, perl, …) and background subshells, so end the whole
        // process tree, children first, not just the direct children.
        for pid in Runner.descendants(of: p.processIdentifier).reversed() { kill(pid, SIGTERM) }
        p.terminate()
    }

    /// All descendant pids of `root` (breadth-first), read from `ps`.
    private static func descendants(of root: Int32) -> [Int32] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid="]
        let pipe = Pipe(); ps.standardOutput = pipe; ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); ps.waitUntilExit()
        var kids: [Int32: [Int32]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let f = line.split(separator: " ").compactMap { Int32($0) }
            if f.count == 2 { kids[f[1], default: []].append(f[0]) }
        }
        var out: [Int32] = [], queue: [Int32] = [root]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for c in kids[cur] ?? [] { out.append(c); queue.append(c) }
        }
        return out
    }

    // MARK: Output handling (flush by line so multi-byte characters and escape sequences are not cut)
    private func ingest(_ d: Data) {
        pending.append(d)
        guard let nl = pending.lastIndex(of: 0x0A) else { return }
        let chunk = pending.subdata(in: pending.startIndex..<pending.index(after: nl))
        pending = pending.subdata(in: pending.index(after: nl)..<pending.endIndex)
        append(String(decoding: chunk, as: UTF8.self))
    }

    private func append(_ s: String) {
        output += parser.parse(s)
        plain += AnsiParser.strip(s)
    }

    private func finish(code: Int32) {
        guard running else { return }
        if !pending.isEmpty { append(String(decoding: pending, as: UTF8.self)); pending = Data() }
        running = false; process = nil
        let t = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        status = stopped ? loc("Stopped") : (code == 0 ? String(format: loc("Done in %@s"), t) : String(format: loc("Finished (exit code %@) in %@s"), String(code), t))
    }

    // MARK: Copy / Save
    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
        status = loc("Copied")
    }

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netdoctor-\(tool.id)-\(Int(Date().timeIntervalSince1970)).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? plain.write(to: url, atomically: true, encoding: .utf8)
            status = String(format: loc("Saved: %@"), url.lastPathComponent)
        }
    }
}

final class RunnerStore: ObservableObject {
    private var runners: [String: Runner] = [:]
    func runner(for tool: Tool) -> Runner {
        if let r = runners[tool.id] { return r }
        let r = Runner(tool: tool); runners[tool.id] = r; return r
    }
}
