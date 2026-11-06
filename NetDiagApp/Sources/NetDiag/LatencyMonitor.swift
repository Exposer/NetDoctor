import Foundation
import SwiftUI

struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let ms: Double?   // nil = 丢包/超时
}

/// 每秒 ping 一次目标,保留最近 N 个样本。
final class LatencyMonitor: ObservableObject {
    @Published var samples: [Sample] = []
    @Published var target = "1.1.1.1"
    @Published var running = false

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
        if let l = samples.last { return l.ms.map { String(format: "%.0f ms", $0) } ?? "丢包" }
        return "…"
    }

    func start() {
        guard !running else { return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil; running = false }
    func clear() { samples.removeAll() }

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
                self.samples.append(Sample(time: Date(), ms: ms))
                if self.samples.count > self.maxSamples { self.samples.removeFirst(self.samples.count - self.maxSamples) }
            }
        }
    }
}
