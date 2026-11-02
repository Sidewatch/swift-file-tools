//
//  LogLevel+Parsing.swift
//  LogReader
//
//  The words, numbers and letters each log format writes its levels as.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLevel {
    /// The level a word names, in any case: TRACE / VERBOSE / FINEST, DEBUG (DEBUG1–5, DBG, FINE, FINER),
    /// INFO (INFORMATION, INF, CONFIG), NOTICE, WARN / WARNING (WRN), ERROR / ERR / SEVERE (EROR), FATAL / CRITICAL /
    /// CRIT / ALERT / EMERG / EMERGENCY / PANIC (FTL); slog's `ERROR+4` as its named level. nil for any other word.
    public static func named(_ word: some StringProtocol) -> LogLevel? {
        var upper = word.uppercased()
        // Go's slog writes levels between the named ones as an offset: `ERROR+4`, `DEBUG-4`.
        if let sign = upper.firstIndex(where: { $0 == "+" || $0 == "-" }), sign != upper.startIndex,
            upper[upper.index(after: sign)...].allSatisfy(\.isNumber)
        {
            upper = String(upper[..<sign])
        }
        if let level = words[upper] { return level }
        if upper.hasPrefix("DEBUG"), upper.dropFirst(5).allSatisfy(\.isNumber) { return .debug }
        return nil
    }

    private static let words: [String: LogLevel] = [
        // java.util.logging's as SLF4J's bridge maps them: FINEST trace, FINER and FINE debug, CONFIG info.
        "TRACE": .trace, "TRC": .trace, "VERBOSE": .trace, "FINEST": .trace,
        "DEBUG": .debug, "DBG": .debug, "FINE": .debug, "FINER": .debug,
        "INFO": .info, "INF": .info, "INFORMATION": .info, "INFORMATIONAL": .info, "CONFIG": .info,
        "NOTICE": .notice,
        "WARN": .warning, "WARNING": .warning, "WRN": .warning,
        "ERROR": .error, "ERR": .error, "EROR": .error, "SEVERE": .error,
        "FATAL": .fatal, "FTL": .fatal, "CRITICAL": .fatal, "CRIT": .fatal, "ALERT": .fatal, "EMERG": .fatal,
        "EMERGENCY": .fatal, "PANIC": .fatal,
    ]

    /// A syslog severity (0 emergency … 7 debug).
    public static func syslog(severity: Int) -> LogLevel? {
        switch severity {
        case 0...2: return .fatal
        case 3: return .error
        case 4: return .warning
        case 5: return .notice
        case 6: return .info
        case 7: return .debug
        default: return nil
        }
    }

    /// pino's and bunyan's numbers: 10 trace, 20 debug, 30 info, 40 warning, 50 error, 60 fatal.
    public static func numbered(_ n: Int) -> LogLevel? {
        switch n {
        case ..<15: return .trace
        case ..<25: return .debug
        case ..<35: return .info
        case ..<45: return .warning
        case ..<55: return .error
        default: return .fatal
        }
    }

    /// A one-letter level: klog's I W E F, logcat's V D I W E F A, Ruby Logger's D I W E F A U.
    public static func letter(_ c: UInt8) -> LogLevel? {
        switch c {
        case UInt8(ascii: "V"): return .trace
        case UInt8(ascii: "D"): return .debug
        case UInt8(ascii: "I"): return .info
        case UInt8(ascii: "N"): return .notice
        case UInt8(ascii: "W"): return .warning
        case UInt8(ascii: "E"): return .error
        case UInt8(ascii: "F"), UInt8(ascii: "A"): return .fatal
        default: return nil
        }
    }
}
