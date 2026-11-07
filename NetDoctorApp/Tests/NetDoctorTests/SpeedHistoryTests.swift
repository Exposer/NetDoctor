import XCTest
@testable import NetDoctor

final class SpeedHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func rec(_ hours: Double, down: Double = 100, up: Double = 20, rpm: Double? = 800) -> SpeedRecord {
        SpeedRecord(time: t0.addingTimeInterval(hours * 3600), down: down, up: up, rpm: rpm, rtt: 15)
    }

    // MARK: parsing networkQuality -c

    func testParsesThroughputInMbps() throws {
        let json = #"{"dl_throughput": 556831616, "ul_throughput": 18789998, "responsiveness": 845.25, "base_rtt": 17.9}"#
        let r = try XCTUnwrap(SpeedParser.parse(Data(json.utf8), time: t0))
        XCTAssertEqual(r.down, 556.831616, accuracy: 0.0001)
        XCTAssertEqual(r.up, 18.789998, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(r.rpm), 845.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(r.rtt), 17.9, accuracy: 0.0001)
        XCTAssertEqual(r.time, t0)
    }

    func testMissingResponsivenessIsNilNotZero() throws {
        let r = try XCTUnwrap(SpeedParser.parse(Data(#"{"dl_throughput": 1000000, "ul_throughput": 2000000}"#.utf8)))
        XCTAssertNil(r.rpm)
        XCTAssertNil(r.rtt)
    }

    func testZeroResponsivenessIsTreatedAsUnknown() throws {
        let r = try XCTUnwrap(SpeedParser.parse(Data(#"{"dl_throughput": 1000000, "ul_throughput": 2000000, "responsiveness": 0}"#.utf8)))
        XCTAssertNil(r.rpm)
    }

    func testAFailedTestIsNotRecorded() {
        // networkQuality still prints JSON when it fails: an error code and no throughput
        XCTAssertNil(SpeedParser.parse(Data(#"{"error_code": -1200, "error_domain": "NSURLErrorDomain", "dl_throughput": 0}"#.utf8)))
    }

    func testDownloadOnlyIsStillARecord() throws {
        let r = try XCTUnwrap(SpeedParser.parse(Data(#"{"dl_throughput": 5000000}"#.utf8)))
        XCTAssertEqual(r.up, 0)
    }

    func testGarbageIsNotARecord() {
        XCTAssertNil(SpeedParser.parse(Data("not json".utf8)))
        XCTAssertNil(SpeedParser.parse(Data()))
        XCTAssertNil(SpeedParser.parse(Data("[1,2,3]".utf8)))
    }

    // MARK: statistics

    func testSummary() throws {
        let s = try XCTUnwrap(SpeedStats.summary([rec(0, down: 100, up: 10, rpm: 900), rec(1, down: 300, up: 30, rpm: 200), rec(2, down: 200, up: 20, rpm: nil)]))
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.avgDown, 200, accuracy: 0.0001)
        XCTAssertEqual(s.avgUp, 20, accuracy: 0.0001)
        XCTAssertEqual(s.minDown, 100)
        XCTAssertEqual(s.minUp, 10)
        XCTAssertEqual(s.lowestRPM, 200)
        XCTAssertEqual(s.latest.down, 200, "latest is the newest record, not the last in the array")
    }

    func testSummaryLatestIgnoresArrayOrder() throws {
        let s = try XCTUnwrap(SpeedStats.summary([rec(5, down: 50), rec(1, down: 10)]))
        XCTAssertEqual(s.latest.down, 50)
    }

    func testSummaryOfNothingIsNil() { XCTAssertNil(SpeedStats.summary([])) }

    func testLowestRPMIsNilWhenNoneReported() throws {
        XCTAssertNil(try XCTUnwrap(SpeedStats.summary([rec(0, rpm: nil)])).lowestRPM)
    }

    func testWindowKeepsTheRangeAndSortsOldestFirst() {
        let w = SpeedStats.window([rec(10), rec(1), rec(30)], from: t0.addingTimeInterval(0), to: t0.addingTimeInterval(12 * 3600))
        XCTAssertEqual(w.map { $0.time }, [t0.addingTimeInterval(3600), t0.addingTimeInterval(10 * 3600)])
    }

    // MARK: retention

    func testPruningDropsOldRecordsAndKeepsTheNewestWhenTooMany() {
        let now = t0.addingTimeInterval(40 * 86400)
        let old = SpeedRecord(time: t0, down: 1, up: 1, rpm: nil, rtt: nil)                       // 40 days old
        let fresh = (0..<5).map { SpeedRecord(time: now.addingTimeInterval(Double(-$0) * 3600), down: Double($0), up: 1, rpm: nil, rtt: nil) }
        let kept = SpeedStats.pruned([old] + fresh, now: now, maxAge: 30 * 86400, maxCount: 3)
        XCTAssertEqual(kept.count, 3)
        XCTAssertFalse(kept.contains(old))
        XCTAssertEqual(kept.map { $0.down }, [2, 1, 0], "oldest first, the three newest survive")
    }

    // MARK: when an automatic test is due

    func testNothingIsDueWhenOff() {
        XCTAssertFalse(SpeedStats.isDue(last: nil, now: t0, intervalHours: 0))
    }

    func testFirstTestIsDueImmediately() {
        XCTAssertTrue(SpeedStats.isDue(last: nil, now: t0, intervalHours: 6))
    }

    func testNotDueBeforeTheIntervalHasPassed() {
        XCTAssertFalse(SpeedStats.isDue(last: t0, now: t0.addingTimeInterval(5 * 3600), intervalHours: 6), "reopening the app must not start a test")
    }

    func testDueAfterTheInterval() {
        XCTAssertTrue(SpeedStats.isDue(last: t0, now: t0.addingTimeInterval(6 * 3600), intervalHours: 6))
        XCTAssertTrue(SpeedStats.isDue(last: t0, now: t0.addingTimeInterval(6 * 3600 - 30), intervalHours: 6), "a timer firing slightly early still counts")
    }

    // MARK: metered connections

    func testIPhoneHotspotIsRecognised() {
        XCTAssertTrue(SpeedStats.isPhoneHotspot(gateway: "172.20.10.1"))
        XCTAssertFalse(SpeedStats.isPhoneHotspot(gateway: "192.168.1.1"))
        XCTAssertFalse(SpeedStats.isPhoneHotspot(gateway: "172.20.1.1"))
        XCTAssertFalse(SpeedStats.isPhoneHotspot(gateway: ""))
    }

    // MARK: the file

    func testWritingAndReadingTheHistoryFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)/speed-history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date()
        let h = SpeedHistory(url: url)
        h.add(SpeedRecord(time: now.addingTimeInterval(-3600), down: 120.5, up: 22.25, rpm: 640, rtt: 18))
        h.add(SpeedRecord(time: now, down: 99, up: 11, rpm: nil, rtt: nil))
        let again = SpeedHistory(url: url)
        XCTAssertEqual(again.records.count, 2)
        XCTAssertEqual(again.records[0].down, 120.5)
        XCTAssertEqual(again.records[0].rpm, 640)
        XCTAssertNil(again.records[1].rpm)
        again.clear()
        XCTAssertEqual(SpeedHistory(url: url).records.count, 0)
    }

    func testACorruptFileStartsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("speed-history.json")
        try Data("{ broken".utf8).write(to: url)
        XCTAssertEqual(SpeedHistory(url: url).records.count, 0)
    }
}
