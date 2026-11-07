import Foundation
import SwiftUI

struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let ms: Double?   // nil = loss / timeout
}

/// Pings the target once a second and keeps the latest N samples.
final class LatencyMonitor: ObservableObject {
    @Published var samples: [Sample] = []
    // Samples of the old target must not be mixed into the chart of the new one.
    @Published var target = "1.1.1.1" { didSet { if target != oldValue { clear() } } }
    @Published var running = false
    /// Notify when the connection drops (3 failed pings in a row) and when it comes back.
    @Published var notifyOnLoss = UserDefaults.standard.bool(forKey: "notifyOnLoss") {
        didSet { UserDefaults.standard.set(notifyOnLoss, forKey: "notifyOnLoss"); if notifyOnLoss { Notifier.requestAuthorization() } }
    }
    /// Longer than the chart's 180 samples, so an export covers up to two hours.
    private(set) var history: [Sample] = []
    private let maxHistory = 7200
    private var lossStreak = 0
    private var outageStart: Date?

    private var timer: Timer?
    private let maxSamples = 180
    private var inFlight = false

    var last: Double? { samples.last?.ms }
    var values: [Double] { samples.compactMap { $0.ms } }
    var avg: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    var minMs: Double? { values.min() }
    var maxMs: Double? { values.max() }
    var jitter: Double? {
        guard values.count > 1 else { return nil }
        let diffs = zip(values.dropFirst(), values).map { abs($0 - $1) }
        return diffs.reduce(0, +) / Double(diffs.count)
    }
    var lossPercent: Double {
        samples.isEmpty ? 0 : Double(samples.filter { $0.ms == nil }.count) / Double(samples.count) * 100
    }
    var menuTitle: String {
        guard running else { return "—" }
        if let l = samples.last { return l.ms.map { String(format: "%.0f ms", $0) } ?? loc("Loss") }
        return "…"
    }

    func start() {
        guard !running else { return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil; running = false }
    func clear() { samples.removeAll(); history.removeAll(); lossStreak = 0; outageStart = nil }

    /// CSV of everything recorded since the last Clear / target change: ISO-8601 time, target, latency (empty = lost), lost flag.
    func csv() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = "time,target,latency_ms,lost\n"
        let t = target.trimmingCharacters(in: .whitespaces)
        for s in history { out += "\(f.string(from: s.time)),\(t),\(s.ms.map { String(format: "%.3f", $0) } ?? ""),\(s.ms == nil ? 1 : 0)\n" }
        return out
    }

    private func record(_ s: Sample) {
        samples.append(s)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        history.append(s)
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
        if s.ms == nil {
            lossStreak += 1
            if lossStreak == 3 {
                outageStart = s.time
                if notifyOnLoss { Notifier.post(title: loc("Network connection lost"), body: String(format: loc("%@ is not answering."), target)) }
            }
        } else {
            if let t = outageStart, notifyOnLoss {
                Notifier.post(title: loc("Network is back"), body: String(format: loc("%@ answers again after about %d s."), target, Int(s.time.timeIntervalSince(t)) + 3))
            }
            lossStreak = 0; outageStart = nil
        }
    }

    private func tick() {
        guard !inFlight else { return }
        let host = target.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.hasPrefix("-"),
              host.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil else { return }
        inFlight = true
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/sbin/ping")
            p.arguments = ["-c", "1", "-t", "2", host]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            var ms: Double? = nil
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let s = String(decoding: data, as: UTF8.self)
                if let r = s.range(of: "time=[0-9.]+", options: .regularExpression) {
                    ms = Double(s[r].dropFirst(5))
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlight = false
                guard self.running else { return }
                // The target was edited while this ping was in flight: the result belongs to the old target.
                guard self.target.trimmingCharacters(in: .whitespaces) == host else { return }
                self.record(Sample(time: Date(), ms: ms))
            }
        }
    }
}
