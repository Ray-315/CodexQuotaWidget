import Foundation
import XCTest
@testable import CodexQuotaWidget

final class SessionLogParserTests: XCTestCase {
    func testParsesLatestQuotaSnapshot() throws {
        let rootURL = try makeTempDirectory()
        let logsURL = rootURL.appendingPathComponent("2026/03/21", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

        let fileURL = logsURL.appendingPathComponent("rollout.jsonl")
        let content = [
            #"{"timestamp":"2026-03-21T00:32:00.000Z","type":"event_msg","payload":{"type":"other"}}"#,
            #"{"timestamp":"2026-03-21T00:33:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":9.0,"window_minutes":300,"resets_at":1774033623},"secondary":{"used_percent":15.0,"window_minutes":10080,"resets_at":1774494909},"plan_type":"plus"}}}"#
        ].joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = try SessionLogParser().loadLatestSnapshot(from: rootURL)

        XCTAssertEqual(snapshot?.primary?.roundedRemainingPercent, 91)
        XCTAssertEqual(snapshot?.secondary?.roundedRemainingPercent, 85)
        XCTAssertEqual(snapshot?.tightestRemainingPercent, 85)
        XCTAssertEqual(snapshot?.planType, "plus")
    }

    func testSkipsBrokenAndIrrelevantLines() throws {
        let rootURL = try makeTempDirectory()
        let fileURL = rootURL.appendingPathComponent("log.jsonl")
        let content = [
            #"{not-json}"#,
            #"{"timestamp":"2026-03-21T00:32:00.000Z","type":"response_item","payload":{"type":"token_count"}}"#,
            #"{"timestamp":"2026-03-21T00:34:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1774033623},"plan_type":"team"}}}"#
        ].joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = try SessionLogParser().parseLatestSnapshot(in: fileURL)

        XCTAssertEqual(snapshot?.primary?.roundedRemainingPercent, 60)
        XCTAssertNil(snapshot?.secondary)
        XCTAssertEqual(snapshot?.tightestRemainingPercent, 60)
    }

    func testPrefersNewestValidFile() throws {
        let rootURL = try makeTempDirectory()
        let firstURL = rootURL.appendingPathComponent("old.jsonl")
        let secondURL = rootURL.appendingPathComponent("new.jsonl")

        try #"{"timestamp":"2026-03-21T00:34:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":70.0,"window_minutes":300,"resets_at":1774033623},"secondary":{"used_percent":25.0,"window_minutes":10080,"resets_at":1774494909},"plan_type":"plus"}}}"#
            .write(to: firstURL, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 1.1)

        try #"{"timestamp":"2026-03-21T00:35:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":18.0,"window_minutes":300,"resets_at":1774033623},"secondary":{"used_percent":22.0,"window_minutes":10080,"resets_at":1774494909},"plan_type":"pro"}}}"#
            .write(to: secondURL, atomically: true, encoding: .utf8)

        let snapshot = try SessionLogParser().loadLatestSnapshot(from: rootURL)

        XCTAssertEqual(snapshot?.planType, "pro")
        XCTAssertEqual(snapshot?.primary?.roundedRemainingPercent, 82)
        XCTAssertEqual(snapshot?.secondary?.roundedRemainingPercent, 78)
        XCTAssertEqual(snapshot?.sourceFile.lastPathComponent, "new.jsonl")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
