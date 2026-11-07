import XCTest
@testable import NetDoctor

final class HealthTimelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func r(_ minutes: Double, _ v: String) -> HealthRecord { HealthRecord(time: t0.addingTimeInterval(minutes * 60), verdict: v) }
    private let gap: TimeInterval = 30 * 60

    func testSameVerdictMergesIntoOneEpisode() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(5, "ok"), r(10, "ok")], gapLimit: gap, now: t0.addingTimeInterval(15 * 60))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].start, t0)
        XCTAssertEqual(e[0].duration, 15 * 60)
    }

    func testVerdictChangeStartsANewEpisode() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(5, "dns"), r(10, "ok")], gapLimit: gap, now: t0.addingTimeInterval(15 * 60))
        XCTAssertEqual(e.map { $0.verdict }, ["ok", "dns", "ok"])
        XCTAssertEqual(e[1].duration, 5 * 60)
    }

    func testDifferentProblemsAreSeparateEpisodes() {
        let e = HealthTimeline.episodes([r(0, "dns"), r(5, "http")], gapLimit: gap, now: t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(e.map { $0.verdict }, ["dns", "http"])
    }

    func testAGapLeavesTheTimeEmpty() {
        // checks at 0 and 120 min with a 30 min limit: 0–30 is covered, 30–120 is unknown
        let e = HealthTimeline.episodes([r(0, "ok"), r(120, "ok")], gapLimit: gap, now: t0.addingTimeInterval(125 * 60))
        XCTAssertEqual(e.count, 2, "records across a gap must not merge")
        XCTAssertEqual(e[0].duration, 30 * 60)
        XCTAssertEqual(e[1].duration, 5 * 60)
    }

    func testTheLastRecordStopsAtTheGapLimitWhenItIsOld() {
        let e = HealthTimeline.episodes([r(0, "ok")], gapLimit: gap, now: t0.addingTimeInterval(10 * 3600))
        XCTAssertEqual(e[0].duration, 30 * 60)
    }

    func testTheLastRecordReachesNowWhenRecent() {
        let e = HealthTimeline.episodes([r(0, "dns")], gapLimit: gap, now: t0.addingTimeInterval(7 * 60))
        XCTAssertEqual(e[0].duration, 7 * 60)
    }

    func testRecordsInAnyOrder() {
        let e = HealthTimeline.episodes([r(10, "ok"), r(0, "dns"), r(5, "dns")], gapLimit: gap, now: t0.addingTimeInterval(15 * 60))
        XCTAssertEqual(e.map { $0.verdict }, ["dns", "ok"])
        XCTAssertEqual(e[0].duration, 10 * 60)
    }

    func testNoRecordsNoEpisodes() {
        XCTAssertTrue(HealthTimeline.episodes([], gapLimit: gap, now: t0).isEmpty)
        XCTAssertNil(HealthTimeline.healthyShare([]))
    }

    func testHealthyShare() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(30, "dns"), r(40, "ok")], gapLimit: 3600, now: t0.addingTimeInterval(50 * 60))
        // ok 0–30, dns 30–40, ok 40–50: 40 of 50 minutes healthy
        XCTAssertEqual(HealthTimeline.healthyShare(e)!, 0.8, accuracy: 0.0001)
    }

    func testUnstableIsNotHealthy() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(10, "wifi")], gapLimit: 3600, now: t0.addingTimeInterval(20 * 60))
        XCTAssertEqual(HealthTimeline.healthyShare(e)!, 0.5, accuracy: 0.0001)
    }

    func testSeverity() {
        XCTAssertEqual(HealthRecord.severity(of: "ok"), .good)
        XCTAssertEqual(HealthRecord.severity(of: "wifi"), .warning)
        XCTAssertEqual(HealthRecord.severity(of: "unstable"), .warning)
        for v in ["dns", "dns_all", "gateway", "internet", "link", "dhcp", "captive", "clock", "http", "never-heard-of-it"] {
            XCTAssertEqual(HealthRecord.severity(of: v), .problem, v)
        }
    }

    func testClippingCutsEpisodesAtTheEdges() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(60, "dns")], gapLimit: 7200, now: t0.addingTimeInterval(120 * 60))
        let c = HealthTimeline.clipped(e, from: t0.addingTimeInterval(30 * 60), to: t0.addingTimeInterval(90 * 60))
        XCTAssertEqual(c.map { $0.verdict }, ["ok", "dns"])
        XCTAssertEqual(c[0].start, t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(c[0].end, t0.addingTimeInterval(60 * 60))
        XCTAssertEqual(c[1].end, t0.addingTimeInterval(90 * 60))
    }

    func testClippingDropsEpisodesOutsideTheRange() {
        let e = HealthTimeline.episodes([r(0, "dns"), r(10, "ok")], gapLimit: 3600, now: t0.addingTimeInterval(20 * 60))
        let c = HealthTimeline.clipped(e, from: t0.addingTimeInterval(15 * 60), to: t0.addingTimeInterval(20 * 60))
        XCTAssertEqual(c.map { $0.verdict }, ["ok"])
    }

    func testPruningByAgeAndCount() {
        let now = t0.addingTimeInterval(20 * 86400)
        let old = HealthRecord(time: t0, verdict: "ok")
        let recent = (0..<10).map { HealthRecord(time: now.addingTimeInterval(Double(-$0) * 60), verdict: "ok") }
        let p = HealthTimeline.pruned([old] + recent, now: now, maxAge: 14 * 86400, maxCount: 4)
        XCTAssertEqual(p.count, 4)
        XCTAssertFalse(p.contains(old))
        XCTAssertEqual(p.last!.time, now, "the newest records are the ones kept")
    }

    func testVerdictCodeParsing() {
        XCTAssertEqual(HealthCheck.code(from: "== Verdict ==\n[ OK ] fine\nverdict=ok\n"), "ok")
        XCTAssertEqual(HealthCheck.code(from: "x\nverdict=dns_all\n"), "dns_all")
        XCTAssertNil(HealthCheck.code(from: "no code here"))
        XCTAssertNil(HealthCheck.code(from: "verdict=\n"))
        XCTAssertNil(HealthCheck.code(from: "verdict=DROP TABLE\n"), "only lowercase letters and underscores are accepted")
    }

    func testARecordKeepsItsOwnGapWhenTheSettingChangesLater() {
        // Hourly checks recorded with a 2 h gap; the current setting (10 min) must not shrink them.
        func rec(_ m: Double) -> HealthRecord { HealthRecord(time: t0.addingTimeInterval(m * 60), verdict: "ok", gap: 7200) }
        let e = HealthTimeline.episodes([rec(0), rec(60), rec(120)], gapLimit: 10 * 60, now: t0.addingTimeInterval(130 * 60))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].duration, 130 * 60, accuracy: 1)
    }

    func testRecordsWithoutAGapUseTheCurrentLimit() {
        let e = HealthTimeline.episodes([r(0, "ok"), r(60, "ok")], gapLimit: 10 * 60, now: t0.addingTimeInterval(61 * 60))
        XCTAssertEqual(e.count, 2, "the old behaviour for files written before the gap was stored")
    }

    func testOldHistoryFilesWithoutAGapStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nd-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let when = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        try "[{\"id\":\"\(UUID().uuidString)\",\"time\":\"\(when)\",\"verdict\":\"dns\"}]".write(to: url, atomically: true, encoding: .utf8)
        let h = HealthHistory(url: url)
        XCTAssertEqual(h.records.map { $0.verdict }, ["dns"])
        XCTAssertNil(h.records.first?.gap)
    }

    func testGapIsStoredAndReloaded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nd-gap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        HealthHistory(url: url).add(verdict: "ok", at: Date().addingTimeInterval(-60), gap: 1800)
        XCTAssertEqual(HealthHistory(url: url).records.first?.gap, 1800)
        XCTAssertEqual(HealthCheck.gap(forIntervalMinutes: 60), 7200)
        XCTAssertEqual(HealthCheck.gap(forIntervalMinutes: 0), 600)
    }

    func testHistoryIsSavedAndReloaded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nd-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sub/history.json")
        let h = HealthHistory(url: url)
        h.add(verdict: "ok", at: Date().addingTimeInterval(-120))
        h.add(verdict: "dns", at: Date().addingTimeInterval(-60))
        let again = HealthHistory(url: url)
        XCTAssertEqual(again.records.map { $0.verdict }, ["ok", "dns"])
        again.clear()
        XCTAssertTrue(HealthHistory(url: url).records.isEmpty)
    }

    func testCorruptHistoryFileIsIgnored() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nd-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(HealthHistory(url: url).records.isEmpty)
    }
}

final class BuildArgsTests: XCTestCase {
    private func tool(_ id: String) -> Tool { Tool.all.first { $0.id == id }! }
    private func args(_ id: String, _ v: [String: String]) throws -> [String] { try Runner.buildArgs(tool: tool(id), values: v) }

    func testBothCheckboxes() throws { XCTAssertEqual(try args("report", ["redact": "redact", "html": "html"]), ["redact", "html"]) }
    func testOnlyTheSecondCheckboxIsKept() throws { XCTAssertEqual(try args("report", ["redact": "", "html": "html"]), ["html"]) }
    func testOnlyTheFirstCheckbox() throws { XCTAssertEqual(try args("report", ["redact": "redact", "html": ""]), ["redact"]) }
    func testNoCheckbox() throws { XCTAssertEqual(try args("report", ["redact": "", "html": ""]), []) }
    func testEmptyOptionalFieldDoesNotDropATickedBox() throws { XCTAssertEqual(try args("dnsbench", ["domain": "", "yes": "yes"]), ["yes"]) }
    func testFilledFieldAndTickedBox() throws { XCTAssertEqual(try args("dnsbench", ["domain": "example.org", "yes": "yes"]), ["example.org", "yes"]) }

    func testPositionalFieldsAfterAnEmptyOneAreLeftOut() throws {
        let t = Tool(id: "t", title: "t", icon: "x", summary: "",
                     inputs: [ToolInput(name: "a", label: "a"), ToolInput(name: "b", label: "b"), ToolInput(name: "f", label: "f", flag: "go")])
        XCTAssertEqual(try Runner.buildArgs(tool: t, values: ["a": "", "b": "2", "f": "go"]), ["go"])
        XCTAssertEqual(try Runner.buildArgs(tool: t, values: ["a": "1", "b": "2", "f": ""]), ["1", "2"])
    }

    func testCommasAreAccepted() throws { XCTAssertEqual(try args("dnsset", ["servers": "1.1.1.1,8.8.8.8"]), ["1.1.1.1,8.8.8.8"]) }
    func testSpacesLeadingDashesAndMissingRequiredAreRefused() {
        XCTAssertThrowsError(try args("dnsset", ["servers": "1.1.1.1 8.8.8.8"]))
        XCTAssertThrowsError(try args("dnsset", ["servers": "-x"]))
        XCTAssertThrowsError(try args("mtr", ["host": ""]))
    }
}
