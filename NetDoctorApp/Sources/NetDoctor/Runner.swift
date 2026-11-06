import SwiftUI
import AppKit

/// 一个工具的运行状态:输入、输出、进程。
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

    // MARK: 定位 netdoctor 脚本
    static var scriptPath: String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["NETDOCTOR_PATH"] { candidates.append(env) }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("netdoctor").path { candidates.append(r) }
        candidates.append(fm.currentDirectoryPath + "/netdoctor")
        candidates.append(fm.currentDirectoryPath + "/../netdoctor")
        return candidates.first { fm.isReadableFile(atPath: $0) }
    }

    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:" + (e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        e["NETDOCTOR_COLOR"] = "1"
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
                if i.required { throw NSError(domain: "netdoctor", code: 1, userInfo: [NSLocalizedDescriptionKey: "请填写:\(i.label)"]) }
                break
            }
            if v.hasPrefix("-") || v.count > 300 || v.unicodeScalars.contains(where: { !Self.allowed.contains($0) }) {
                throw NSError(domain: "netdoctor", code: 2, userInfo: [NSLocalizedDescriptionKey: "参数不合法:\(i.label)"])
            }
            args.append(v)
        }
        return args
    }

    // MARK: 运行
    func run() {
        guard !running else { return }
        output = AttributedString(); plain = ""; parser = AnsiParser(); pending = Data(); stopped = false
        guard let script = Runner.scriptPath else {
            status = "找不到 netdoctor 脚本"; return
        }
        let args: [String]
        do { args = try buildArgs() } catch { status = error.localizedDescription; return }

        running = true; status = "运行中…"; startedAt = Date()
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
            // 等待最后的数据读完
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.finish(code: proc.terminationStatus)
            }
        }
        do { try p.run(); process = p }
        catch { running = false; status = "启动失败:\(error.localizedDescription)" }
    }

    private func runAdmin(script: String, args: [String]) {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let home = NSHomeDirectory()
        let inner = "HOME=\(q(home)) PATH=\(q(Runner.env["PATH"] ?? "")) NETDOCTOR_COLOR=1 /bin/bash "
            + ([script, tool.id] + args).map(q).joined(separator: " ") + " 2>&1"
        let esc = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(esc)\" with administrator privileges"
        append("(等待系统弹出管理员密码框…)\n")
        DispatchQueue.global().async { [weak self] in
            var err: NSDictionary?
            let script = NSAppleScript(source: src)
            let res: NSAppleEventDescriptor? = script?.executeAndReturnError(&err)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if err == nil, let s = res?.stringValue {
                    self.append(s + "\n"); self.finish(code: 0)
                } else {
                    let msg = (err?["NSAppleScriptErrorMessage"] as? String) ?? "已取消"
                    self.append("\u{1B}[31m\(msg)\u{1B}[0m\n"); self.finish(code: 1)
                }
            }
        }
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        stopped = true
        let pk = Process()
        pk.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pk.arguments = ["-TERM", "-P", String(p.processIdentifier)]
        try? pk.run(); pk.waitUntilExit()
        p.terminate()
    }

    // MARK: 输出处理(按行刷新,避免多字节字符与转义序列被切断)
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
        status = stopped ? "已停止" : (code == 0 ? "完成,用时 \(t)s" : "结束(退出码 \(code)),用时 \(t)s")
    }

    // MARK: 复制 / 保存
    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
        status = "已复制"
    }

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netdoctor-\(tool.id)-\(Int(Date().timeIntervalSince1970)).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? plain.write(to: url, atomically: true, encoding: .utf8)
            status = "已保存:\(url.lastPathComponent)"
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
