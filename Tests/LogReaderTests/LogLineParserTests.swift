//
//  LogLineParserTests.swift
//  LogReaderTests
//
//  One representative line per format: what the header reader makes of it.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import LogReader

final class LogLineParserTests: XCTestCase {
    let ref = LogReference(year: 2026, month: 10, day: 1)

    func head(_ line: String) -> LogLineHead? { LogLineParser.head(of: line, reference: ref) }

    /// Seconds since the epoch for a UTC date and time.
    func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Double = 0) -> Double {
        Double(LogTimeParser.daysFromCivil(y, mo, d) * 86_400 + h * 3600 + mi * 60) + s
    }

    func check(
        _ line: String, _ format: LogFormat, _ level: LogLevel?, time: Double?, zoned: Bool? = nil, component: String?,
        message: String? = nil, file: StaticString = #filePath, lineNo: UInt = #line
    ) {
        guard let h = head(line) else { return XCTFail("no header in: \(line)", file: file, line: lineNo) }
        XCTAssertEqual(h.format, format, line, file: file, line: lineNo)
        XCTAssertEqual(h.level, level, line, file: file, line: lineNo)
        if let time {
            XCTAssertEqual(h.time?.seconds ?? .nan, time, accuracy: 0.0005, line, file: file, line: lineNo)
        } else {
            XCTAssertNil(h.time, line, file: file, line: lineNo)
        }
        if let zoned { XCTAssertEqual(h.time?.zoned, zoned, line, file: file, line: lineNo) }
        XCTAssertEqual(h.component, component, line, file: file, line: lineNo)
        if let message {
            let text = h.message ?? String(line.utf8.dropFirst(h.messageStart))!
            XCTAssertEqual(text, message, line, file: file, line: lineNo)
        }
    }

    func testPlainServiceLines() {
        check(
            "2026-10-01T00:00:00.021Z INFO  [auth] req=89ffccf2edcc cache miss key=fresh:31698", .plain, .info,
            time: utc(2026, 10, 1, 0, 0, 0.021), zoned: true, component: "auth", message: "req=89ffccf2edcc cache miss key=fresh:31698")
        check(
            "2026-10-01T00:00:00.174Z DEBUG [mailer] req=99680088e812 customer note=\"Москва\"", .plain, .debug,
            time: utc(2026, 10, 1, 0, 0, 0.174), component: "mailer")
    }

    func testJSONLines() {
        check(
            #"{"ts":"2026-10-01T00:00:00.057Z","level":"info","service":"auth","msg":"Magnet carbon quiet.","latency_ms":6.0}"#, .json,
            .info, time: utc(2026, 10, 1, 0, 0, 0.057), component: "auth", message: "Magnet carbon quiet.")
        // pino: numeric level, epoch milliseconds, `name`.
        check(
            #"{"level":50,"time":1790812800000,"pid":1,"hostname":"web-01","name":"api","msg":"boom"}"#, .json, .error,
            time: 1_790_812_800, component: "api", message: "boom")
        // Docker's json-file: the stream is the component, the carried line's level the level.
        check(
            #"{"log":"2026-10-01T00:00:01Z WARN [db] slow query\n","stream":"stderr","time":"2026-10-01T00:00:01.5Z"}"#, .dockerJSON,
            .warning, time: utc(2026, 10, 1, 0, 0, 1.5), component: "stderr")
    }

    func testLogfmt() {
        check(
            #"time=2026-10-01T00:00:00Z level=warn msg="disk nearly full" component=storage"#, .logfmt, .warning,
            time: utc(2026, 10, 1), component: "storage", message: "disk nearly full")
        check(#"time=2026-10-01T00:00:00.000Z level=INFO msg=started port=8080"#, .logfmt, .info, time: utc(2026, 10, 1), component: nil)
    }

    func testPythonAndJavaFamilies() {
        check(
            "2026-10-01 00:00:00,123 - app.db - WARNING - pool exhausted", .plain, .warning, time: utc(2026, 10, 1, 0, 0, 0.123),
            zoned: false, component: "app.db", message: "pool exhausted")
        check("WARNING:root:disk nearly full", .pythonBasic, .warning, time: nil, component: "root", message: "disk nearly full")
        check(
            "2026-10-01 00:00:00,123 INFO  [main] com.example.Main - started", .plain, .info, time: utc(2026, 10, 1, 0, 0, 0.123),
            component: "com.example.Main", message: "started")
        check(
            "00:00:01.500 [main] ERROR c.e.Service - failed", .plain, .error, time: utc(2026, 10, 1, 0, 0, 1.5), component: "c.e.Service",
            message: "failed")
        check(
            "Oct 01, 2026 12:05:00 AM com.example.Main run", .javaUtilLogging, nil, time: utc(2026, 10, 1, 0, 5),
            component: "com.example.Main")
        XCTAssertEqual(LogLineParser.javaUtilLoggingLevel(Array("SEVERE: it broke".utf8)[...]), .error)
    }

    func testRustAndGo() {
        check(
            "[2026-10-01T00:00:00Z INFO  my_app::db] connected", .plain, .info, time: utc(2026, 10, 1), component: "my_app::db",
            message: "connected")
        check(
            "2026-10-01T00:00:00.123456Z  WARN my_app::http: slow request", .plain, .warning, time: utc(2026, 10, 1, 0, 0, 0.123456),
            component: "my_app::http", message: "slow request")
        check("2026/10/01 00:00:00 listening on :8080", .goLog, nil, time: utc(2026, 10, 1), component: nil, message: "listening on :8080")
    }

    func testRubyLaravelPHP() {
        check(
            "I, [2026-10-01T00:00:00.123456 #4242]  INFO -- : Started GET \"/\"", .rubyLogger, .info,
            time: utc(2026, 10, 1, 0, 0, 0.123456),
            component: nil, message: "Started GET \"/\"")
        check(
            "E, [2026-10-01T00:00:00.000001 #1] ERROR -- worker: job failed", .rubyLogger, .error, time: utc(2026, 10, 1, 0, 0, 0.000001),
            component: "worker")
        check(
            "[2026-10-01 00:00:00] production.ERROR: Undefined variable $user {\"exception\":\"[object]\"}", .monolog, .error,
            time: utc(2026, 10, 1), component: "production", message: "Undefined variable $user {\"exception\":\"[object]\"}")
        check(
            "[01-Oct-2026 00:00:00 UTC] PHP Warning:  Undefined array key \"id\" in /srv/app/index.php on line 4", .phpError, .warning,
            time: utc(2026, 10, 1), zoned: true, component: nil, message: "Undefined array key \"id\" in /srv/app/index.php on line 4")
        check(
            "[01-Oct-2026 00:00:00 UTC] PHP Fatal error:  Uncaught Exception: boom", .phpError, .fatal, time: utc(2026, 10, 1),
            component: nil)
    }

    func testWebServers() {
        check(
            #"192.0.2.10 - - [01/Oct/2026:00:00:00 +0000] "GET /missing HTTP/1.1" 404 196 "-" "curl/8.7.1""#, .accessLog, .warning,
            time: utc(2026, 10, 1), zoned: true, component: nil, message: #""GET /missing HTTP/1.1" 404 196 "-" "curl/8.7.1""#)
        check(
            #"2001:db8::1 - - [01/Oct/2026:01:00:00 +0100] "POST /api HTTP/2.0" 502 0"#, .accessLog, .error, time: utc(2026, 10, 1),
            component: nil)
        check(
            "[Wed Oct 01 00:00:00.123456 2026] [core:error] [pid 123:tid 456] [client 192.0.2.1:5000] AH00126: Invalid URI", .apacheError,
            .error, time: utc(2026, 10, 1, 0, 0, 0.123456), component: "core", message: "AH00126: Invalid URI")
        check(
            "2026/10/01 00:00:00 [error] 1234#0: *5 open() failed (2: No such file)", .nginxError, .error, time: utc(2026, 10, 1),
            component: nil, message: "1234#0: *5 open() failed (2: No such file)")
    }

    func testSyslogFamily() {
        check(
            "Oct  1 00:00:00 web-01 sshd[123]: Accepted publickey", .syslog, nil, time: utc(2026, 10, 1), component: "sshd",
            message: "Accepted publickey")
        check(
            "<34>1 2026-10-01T00:00:00.000Z web-01 su - ID47 - 'su root' failed", .syslog5424, .fatal, time: utc(2026, 10, 1),
            component: "su", message: "'su root' failed")
        check(
            #"<165>1 2026-10-01T00:00:00Z web-01 evntslog - ID47 [exampleSDID@32473 iut="3" eventSource="App"] An event"#, .syslog5424,
            .notice, time: utc(2026, 10, 1), component: "evntslog", message: "An event")
        check(
            "2026-10-01T00:00:00+00:00 heroku[router]: at=error code=H12 desc=\"Request timeout\"", .syslog, .error, time: utc(2026, 10, 1),
            component: "heroku")
        check(
            "2026-10-01 00:00:00.123456+0100 0x1a2b     Error       0x0                  321    0    myapp: disk failure", .appleUnified,
            .error,
            time: utc(2026, 9, 30, 23, 0, 0.123456), component: "myapp", message: "disk failure")
    }

    func testDataStoresAndRuntimes() {
        check(
            "2026-10-01 00:00:00.123 UTC [4321] ERROR:  relation \"users\" does not exist", .plain, .error,
            time: utc(2026, 10, 1, 0, 0, 0.123),
            zoned: true, component: nil, message: "relation \"users\" does not exist")
        XCTAssertNil(head("2026-10-01 00:00:00.123 UTC [4321] STATEMENT:  SELECT * FROM users"), "a DETAIL-kind line continues the entry")
        check(
            "2026-10-01T00:00:00.123456Z 0 [Warning] [MY-010068] [Server] CA certificate is self signed.", .plain, .warning,
            time: utc(2026, 10, 1, 0, 0, 0.123456), component: "Server", message: "CA certificate is self signed.")
        check(
            "4321:M 01 Oct 2026 00:00:00.123 * Ready to accept connections", .redis, .notice, time: utc(2026, 10, 1, 0, 0, 0.123),
            component: nil)
        check("00:00:00.123 [error] GenServer terminating", .elixir, .error, time: utc(2026, 10, 1, 0, 0, 0.123), component: nil)
        check(
            "I1001 00:00:00.123456   12345 controller.go:123] Starting workers", .klog, .info, time: utc(2026, 10, 1, 0, 0, 0.123456),
            component: "controller.go", message: "Starting workers")
        check(
            "10-01 00:00:00.123  1234  5678 W ActivityManager: Slow operation", .logcat, .warning, time: utc(2026, 10, 1, 0, 0, 0.123),
            component: "ActivityManager", message: "Slow operation")
    }

    func testLinesWithNoHeaderContinue() {
        for line in [
            "    at com.example.Main.run(Main.java:12)", "Traceback (most recent call last):", "#0 /srv/app/index.php(4): boom()",
            "ValueError: bad value", "", "  File \"app.py\", line 3, in <module>", "Caused by: java.io.IOException",
        ] {
            XCTAssertNil(head(line), line)
        }
    }
}
