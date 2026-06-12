import Foundation
import GradelyWatchShared
import XCTest
@testable import GradelyWatch

final class GradelyWatchTests: XCTestCase {
    func testSessionStoreSavesLoadsAndClearsAuth() throws {
        let store = WatchSessionStore(service: "GradelyWatchTests.\(UUID().uuidString)")
        let auth = GradelyWatchAuth(
            baseURL: URL(string: "https://demo.gradely.app")!,
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        try store.save(auth)
        XCTAssertEqual(try store.load(), auth)

        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testTimetableCacheSavesLoadsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GradelyWatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "cache.json")
        let cache = WatchTimetableCache(fileURL: fileURL)
        let timetable = GradelyWatchDemoTimetable.make(
            weekStart: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 0)
        )

        try cache.save(timetable)
        XCTAssertEqual(try cache.load(), timetable)

        try cache.clear()
        XCTAssertNil(try cache.load())
    }

    func testDemoAuthIsRecognized() {
        let auth = GradelyWatchAuth(
            baseURL: URL(string: "https://demo.gradely.app")!,
            accessToken: "demo-access",
            refreshToken: "demo-refresh",
            tokenType: "Bearer",
            expiresAt: Date()
        )

        XCTAssertTrue(GradelyWatchDemoAccount.isDemo(auth))
    }

    func testTimetableRequestUsesMondayApiDate() {
        let client = WatchBakalariClient()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let thursday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 6, day: 11, hour: 12))!
        let monday = GradelyWatchTimetableDates.monday(of: thursday)

        let url = client.makeTimetableURL(baseURL: URL(string: "https://school.example")!, date: monday)

        XCTAssertEqual(url.absoluteString, "https://school.example/api/3/timetable/actual?date=2026-06-08")
    }
}
