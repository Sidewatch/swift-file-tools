//
//  LogTimeParser.swift
//  LogReader
//
//  Every way a log line writes its time, read from the bytes without a date formatter.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The timestamp shapes log formats use, each read at the cursor: it consumes the timestamp and
/// returns the instant, or returns nil and leaves the cursor where it was. No `DateFormatter`: a
/// million lines are read on one pass.
enum LogTimeParser {
    /// `2026-10-01T00:00:00.021Z`, `2026-10-01 00:00:00,123`, `2026-10-01 00:00:00.123456+0100`,
    /// `2026-10-01T00:00:00+00:00`, `2026-10-01 00:00:00.123 UTC`: a date, `T` or a space, a clock,
    /// then an optional zone (`Z`, `±hh:mm`, `±hhmm`, `±hh`, or a space and `UTC` / `GMT`).
    static func iso(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let y = t.digits(4), t.expect("-"), let mo = t.digits(2), t.expect("-"), let d = t.digits(2) else { return nil }
        guard t.expect("T") || t.expect(" ") || t.expect("_") else { return nil }
        guard let clock = clock(&t) else { return nil }
        let zone = self.zone(&t)
        c = t
        return instant(y, mo, d, clock, zone)
    }

    /// `2026/10/01 00:00:00` (Go's log package, nginx's error log), an optional fraction.
    static func slashDate(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let y = t.digits(4), t.expect("/"), let mo = t.digits(2), t.expect("/"), let d = t.digits(2), t.expect(" "),
            let clock = clock(&t)
        else { return nil }
        c = t
        return instant(y, mo, d, clock, nil)
    }

    /// `01/Oct/2026:00:00:00 +0000`, the Common Log Format's.
    static func commonLog(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let d = t.digits(2), t.expect("/"), let mo = t.monthName(), t.expect("/"), let y = t.digits(4), t.expect(":"),
            let clock = clock(&t)
        else { return nil }
        t.skipSpaces()
        let zone = self.zone(&t)
        c = t
        return instant(y, mo, d, clock, zone)
    }

    /// `Oct  1 00:00:00` and `Oct 01 00:00:00` (syslog, journald's short form): the year is the reference's.
    static func syslog(_ c: inout ByteCursor, _ ref: LogReference) -> LogInstant? {
        var t = c
        guard let mo = t.monthName(), t.expect(" ") else { return nil }
        _ = t.expect(" ")
        guard let d = t.someDigits(max: 2)?.value, t.expect(" "), let clock = clock(&t) else { return nil }
        c = t
        return instant(ref.year, mo, d, clock, nil)
    }

    /// `Wed Oct 01 00:00:00.123456 2026` (Apache's error log).
    static func weekdayFirst(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard t.weekdayName(), t.expect(" "), let mo = t.monthName(), t.expect(" ") else { return nil }
        _ = t.expect(" ")
        guard let d = t.someDigits(max: 2)?.value, t.expect(" "), let clock = clock(&t), t.expect(" "), let y = t.digits(4) else {
            return nil
        }
        c = t
        return instant(y, mo, d, clock, nil)
    }

    /// `01-Oct-2026 00:00:00 UTC` (PHP's error log); a zone other than UTC / GMT is read as unzoned.
    static func dayMonthYearDashed(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let d = t.digits(2), t.expect("-"), let mo = t.monthName(), t.expect("-"), let y = t.digits(4), t.expect(" "),
            let clock = clock(&t)
        else { return nil }
        let zone = self.zone(&t)
        c = t
        return instant(y, mo, d, clock, zone)
    }

    /// `01 Oct 2026 00:00:00.123` (Redis).
    static func dayMonthYearSpaced(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let d = t.digits(2), t.expect(" "), let mo = t.monthName(), t.expect(" "), let y = t.digits(4), t.expect(" "),
            let clock = clock(&t)
        else { return nil }
        c = t
        return instant(y, mo, d, clock, nil)
    }

    /// `1001 00:00:00.123456` (klog, no separator) or `10-01 00:00:00.123` (logcat): the year is the reference's.
    static func monthDay(_ c: inout ByteCursor, dashed: Bool, _ ref: LogReference) -> LogInstant? {
        var t = c
        guard let mo = t.digits(2), !dashed || t.expect("-"), let d = t.digits(2), t.expect(" "), let clock = clock(&t) else {
            return nil
        }
        c = t
        return instant(ref.year, mo, d, clock, nil)
    }

    /// `00:00:00.123` alone (Elixir's Logger): the date is the reference's.
    static func timeOnly(_ c: inout ByteCursor, _ ref: LogReference) -> LogInstant? {
        var t = c
        guard let clock = clock(&t) else { return nil }
        c = t
        return instant(ref.year, ref.month, ref.day, clock, nil)
    }

    /// `Oct 01, 2026 12:00:00 AM` (java.util.logging's SimpleFormatter).
    static func monthNameCommaYear(_ c: inout ByteCursor) -> LogInstant? {
        var t = c
        guard let mo = t.monthName(), t.expect(" "), let d = t.someDigits(max: 2)?.value, t.expect(", "), let y = t.digits(4),
            t.expect(" "), var clock = clock(&t), t.expect(" ")
        else { return nil }
        if t.expect("PM") {
            if clock.hour < 12 { clock.hour += 12 }
        } else if t.expect("AM") {
            if clock.hour == 12 { clock.hour = 0 }
        } else {
            return nil
        }
        c = t
        return instant(y, mo, d, clock, nil)
    }

    /// A number of seconds or milliseconds since the epoch (JSON logs): past 1e11 it is milliseconds.
    static func epoch(_ value: Double) -> LogInstant? {
        guard value.isFinite, value > 0 else { return nil }
        return LogInstant(seconds: value > 1e11 ? value / 1000 : value, zoned: true)
    }

    // MARK: - Pieces

    struct Clock {
        var hour: Int
        let minute: Int
        let second: Int
        let fraction: Double
    }

    /// `hh:mm[:ss[.fff | ,fff]]`, the hour one or two digits.
    static func clock(_ c: inout ByteCursor) -> Clock? {
        var t = c
        guard let h = t.someDigits(max: 2)?.value, t.expect(":"), let m = t.digits(2) else { return nil }
        var s = 0
        var fraction = 0.0
        if t.expect(":") {
            guard let sec = t.digits(2) else { return nil }
            s = sec
            if t.peek() == UInt8(ascii: ".") || t.peek() == UInt8(ascii: ","), let b = t.peek(1), ByteCursor.isDigit(b) {
                t.i += 1
                let frac = t.someDigits(max: 9)!
                fraction = Double(frac.value) / pow(10, Double(frac.count))
            }
        }
        guard h < 25, m < 60, s < 61 else { return nil }
        c = t
        return Clock(hour: h, minute: m, second: s, fraction: fraction)
    }

    /// A zone's offset from UTC in seconds: `Z`, `±hh:mm`, `±hhmm`, `±hh`, or (after a space) `UTC`, `GMT`,
    /// `+0000`. nil when there is none (the cursor stays put).
    static func zone(_ c: inout ByteCursor) -> Int? {
        var t = c
        if t.expect("Z") || t.expect("z") {
            c = t
            return 0
        }
        if t.peek() == UInt8(ascii: " ") {
            t.i += 1
            if t.expect("UTC") || t.expect("GMT") {
                c = t
                return 0
            }
        }
        guard let sign = t.peek(), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") else { return nil }
        t.i += 1
        guard let hh = t.digits(2) else { return nil }
        var mm = 0
        if t.expect(":") {
            guard let m = t.digits(2) else { return nil }
            mm = m
        } else if let m = t.digits(2) {
            mm = m
        }
        c = t
        return (sign == UInt8(ascii: "-") ? -1 : 1) * (hh * 3600 + mm * 60)
    }

    static func instant(_ y: Int, _ mo: Int, _ d: Int, _ clock: Clock, _ zone: Int?) -> LogInstant? {
        guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
        let days = daysFromCivil(y, mo, d)
        let local = Double(days * 86_400 + clock.hour * 3600 + clock.minute * 60 + clock.second) + clock.fraction
        return LogInstant(seconds: local - Double(zone ?? 0), zoned: zone != nil)
    }

    /// Days from 1970-01-01 to the given proleptic Gregorian date (Howard Hinnant's `days_from_civil`).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
