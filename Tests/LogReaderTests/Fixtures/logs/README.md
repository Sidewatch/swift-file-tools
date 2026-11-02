# Log fixtures

Log files with ground-truth answers, for testing a log parser. Each fixture is a pair:
`<format>/<name>.log` and `<format>/<name>.expected.json`.

Where the tool runs on macOS, the real library or program wrote the `.log`, and the program that produced it
wrote the expected file from what it logged (its own records, clock and line counts), so the answers do not
depend on any parser. Where the tool is not available, the sample follows the format's official documentation,
cited below, and the generator wrote the expected file from the same values it built each line from.

## Expected file

```json
{"source": "how it was made", "referenceDate": "2026-10-01", "entries": [
  {"line": 1, "lines": 1, "level": "info", "time": "2026-10-01T00:00:00.021Z", "zoned": true, "component": "auth"}
]}
```

- One object per entry, in file order. `line` is 1-based; `lines` counts continuation lines (stack traces,
  multi-line messages). Lines no entry covers are banners, dividers or headers (listed below).
- `level` is one of trace, debug, info, notice, warning, error, fatal, or null when the format has none.
- `time` is UTC with milliseconds. Finer fractions are truncated, not rounded. A time written without a zone
  is taken as UTC and has `"zoned": false`. Formats without a year or a date take them from `referenceDate`.
- `component` is the logger, module, tag or program name the format carries, or null.

All generators ran with `TZ=UTC`. Real runs that use the real clock are dated 2 November 2026; runs with a
simulated clock start at 2026-10-01T00:00:00Z.

## Fixtures

Real means the named tool wrote the file. Doc means the file was written to the cited documentation.

| File | Entries | Kind | How it was made |
|---|---|---|---|
| plain/plain.log | 80 | real | Python 3.14.10 logging, format `%(asctime)s.%(msecs)03dZ %(levelname)-5s [%(name)s] req=%(req)s %(message)s`, gmtime, WARNING and CRITICAL renamed WARN and FATAL with addLevelName, simulated clock. Paths scrubbed |
| plain/mixed.log | 90 | real | Same Python run. Text lines plus JSON lines `{ts, level, service, msg, err}` from two loggers in one file. Paths scrubbed |
| python/basicconfig.log | 70 | real | Python 3.14.10 logging, `logging.BASIC_FORMAT` (`%(levelname)s:%(name)s:%(message)s`, no time), with logger.exception tracebacks and chained exceptions. Paths scrubbed |
| python/asctime.log | 90 | real | Python 3.14.10 logging, `%(asctime)s - %(name)s - %(levelname)s - %(message)s`, default datefmt, simulated clock, tracebacks. Paths scrubbed |
| python/structlog.log | 60 | real | structlog 26.1.0: add_log_level, TimeStamper(fmt="iso", utc=True), format_exc_info, JSONRenderer; real clock. Paths scrubbed |
| node/pino.log | 90 | real | pino 9.14.0, Node 26.13.0, default JSON (numeric levels, epoch-ms time). `base` set to `{pid, hostname: "web-01"}` so the machine's hostname is not written. Simulated clock. Paths in `err.stack` scrubbed |
| node/bunyan.log | 70 | real | bunyan 1.8.15, default JSON, `hostname: "web-01"` option, simulated clock |
| node/winston.log | 80 | real | winston 3.19.0, `combine(timestamp(), errors({stack: true}), json())`, defaultMeta `{service: "user-service"}`, simulated clock. Paths scrubbed |
| ruby/logger.log | 80 | real | Ruby 2.6.10 stdlib Logger 1.3.0, default Formatter, no progname, `Logger.new(path)` so line 1 is the `# Logfile created on` header. Includes logged exceptions with backtraces. Simulated clock |
| ruby/logger-progname.log | 70 | real | Same Logger with progname `mailer` and per-call prognames `scheduler` and `importer` |
| php/error_log.log | 45 | real | PHP 8.5.12 CLI `php -n -d log_errors=1 -d error_log=FILE -d date.timezone=UTC`, one run per warning, notice, deprecation or fatal (uncaught exceptions with `Stack trace:`, TypeError, memory exhaustion). Real clock, second checked. Paths scrubbed |
| php/laravel.log | 70 | real | monolog/monolog 3.12.1, StreamHandler + `LineFormatter(null, 'Y-m-d H:i:s', true, true)` with includeStacktraces(), which is the formatter Laravel's LogManager builds. Channels `production` and `payments`. Exceptions have `[stacktrace]` / `#0 …` lines. Simulated clock passed as Monolog's datetime argument. Paths scrubbed |
| rust/env_logger.log | 60 | real | env_logger 0.11.11 (log 0.4.35) default format, styles off, real clock with a same-second check. Default 4-space indent on continuation lines |
| rust/tracing.log | 80 | real | tracing-subscriber 0.3.23 (tracing 0.1.44) default fmt, ANSI off, spans on some lines, real clock with a same-millisecond check |
| java/jul-simpleformatter.log | 48 | doc | java.util.logging.SimpleFormatter default format, two-line records, throwables: https://docs.oracle.com/en/java/javase/21/docs/api/java.logging/java/util/logging/SimpleFormatter.html. No JDK here (`/usr/bin/java` is the stub) |
| java/logback.log | 70 | doc | logback default pattern `%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n`: https://logback.qos.ch/manual/configuration.html#automaticConf. Stack traces: https://logback.qos.ch/manual/layouts.html#ex |
| java/spring-boot.log | 60 | doc | Spring Boot default console format: https://docs.spring.io/spring-boot/reference/features/logging.html#features.logging.log-format |
| apache/access.log | 100 | real | Apache httpd 2.4.67 (macOS /usr/sbin/httpd, prefork, own config on a high port, started and stopped with its own pid file), `combined` LogFormat, requests sent with curl (200/206/301/403/404/500). Expected from a second CustomLog `%{msec}t %>s` that httpd wrote for the same requests. 127.0.0.1 rewritten to 203.0.113.7, ::1 to 2001:db8::7, the referer host to web-01.example.com |
| apache/error.log | 70 | real | Same run, built-in default ErrorLog format, `LogLevel info` with `authz_core:debug` inside /private/. Expected made by a strict regex of https://httpd.apache.org/docs/2.4/mod/core.html#errorlogformat (see below). Same IP rewrite. Document root, CGI, config and pid-file paths rewritten to /srv/www, /srv/cgi-bin, /etc/httpd, /run/httpd |
| nginx/access.log | 120 | doc | nginx `combined` log_format: https://nginx.org/en/docs/http/ngx_http_log_module.html#log_format. `$time_local` in a +0200 zone |
| nginx/error.log | 65 | doc | nginx error log levels https://nginx.org/en/docs/ngx_core_module.html#error_log, line shape https://nginx.org/en/docs/debugging_log.html |
| syslog/rfc3164.log | 80 | doc | RFC 3164 header and TAG https://www.rfc-editor.org/rfc/rfc3164#section-4.1.2, as syslog daemons store it (no `<PRI>`, so no level) |
| syslog/rfc3164-pri.log | 75 | real | monolog 3.12.1 SyslogUdpHandler RFC3164 mode, idents sshd/billing/cron/mailer/api. Datagrams were appended to a file through a UdpSocket subclass. The machine hostname that gethostname() wrote was replaced with `web-01`. Monolog zero-pads the day (`Oct 01`) |
| syslog/rfc5424.log | 75 | real | monolog 3.12.1 SyslogUdpHandler RFC5424e mode, same capture and hostname replacement |
| syslog/rfc5424-examples.log | 40 | doc | The four examples of https://www.rfc-editor.org/rfc/rfc5424#section-6.5 verbatim (BOM as real U+FEFF bytes), then lines built to the section 6 ABNF: NILVALUE timestamp, hostname and app-name, +02:00 offsets, structured data |
| macos/show-syslog.log | 63 | real | macOS 27.2 `log show --timezone UTC --info --debug --predicate 'subsystem == "com.example.logfixture" AND processID == …' --style syslog`. Messages came from a tiny os.Logger program (subsystem com.example.logfixture). Expected from `log show --style ndjson` of the same query. Debug messages are not persisted, so none appear. The host column reads `localhost` as written |
| macos/show-default.log | 63 | real | Same query, default style |
| macos/stream-default.log | 70 | real | `log stream --level debug` with the same predicate, captured live during the same run, so Debug messages are present. Expected from a parallel `log stream --style ndjson` |
| journald/short.log | 70 | doc | `journalctl -o short`, journalctl(1): https://www.freedesktop.org/software/systemd/man/latest/journalctl.html#-o |
| journald/short-iso.log | 70 | doc | `journalctl -o short-iso`, same page, +02:00 zone |
| logfmt/logfmt.log | 90 | real | logfmt 1.4.0 (Heroku's npm package) `logfmt.stringify()`, keys time/level/msg/component |
| logfmt/heroku-router.log | 80 | doc | Heroku log format https://devcenter.heroku.com/articles/logging#log-format, router fields https://devcenter.heroku.com/articles/http-routing#heroku-router-log-format, H10/H12 https://devcenter.heroku.com/articles/error-codes |
| docker/json-file.log | 60 | doc | json-file driver https://docs.docker.com/engine/logging/drivers/json-file/ |
| kubernetes/klog.log | 73 | doc | klog header `Lmmdd hh:mm:ss.uuuuuu threadid file:line] msg` (header comment of https://github.com/kubernetes/klog/blob/main/klog.go). Structured values and multi-line `key=<` blocks: https://github.com/kubernetes/community/blob/master/contributors/devel/sig-instrumentation/migration-to-structured-logging.md. Ends with a fatal followed by a goroutine dump |
| android/logcat-threadtime.log | 87 | doc | `logcat -v threadtime` https://developer.android.com/tools/logcat#outputFormat, with a crash block |
| postgres/postgresql.log | 95 | doc | Default `log_line_prefix = '%m [%p] '` https://www.postgresql.org/docs/current/runtime-config-logging.html#GUC-LOG-LINE-PREFIX, severities https://www.postgresql.org/docs/current/runtime-config-logging.html#RUNTIME-CONFIG-SEVERITY-LEVELS |
| mysql/error.log | 64 | doc | MySQL 8.4 error log format https://dev.mysql.com/doc/refman/8.4/en/error-log-format.html |
| redis/redis.log | 72 | doc | serverLogRaw line format in https://github.com/redis/redis/blob/7.4/src/server.c, start-up messages of a stock 7.4 server |
| elixir/logger-default.log | 56 | doc | Elixir Logger default format `"\n$time $metadata[$level] $message\n"` https://hexdocs.pm/logger/Logger.Formatter.html (time only) |
| elixir/phoenix.log | 60 | doc | Phoenix generator config `"$time $metadata[$level] $message\n"`, `metadata: [:request_id]`: https://hexdocs.pm/phoenix/up_and_running.html and the Logger.Formatter page |
| go/log.log | 64 | doc | Go `log` with LstdFlags: https://pkg.go.dev/log#pkg-constants |
| go/slog-text.log | 70 | doc | `log/slog` TextHandler https://pkg.go.dev/log/slog#TextHandler, including levels like `ERROR+4` |
| go/slog-json.log | 70 | doc | `log/slog` JSONHandler https://pkg.go.dev/log/slog#JSONHandler. Time written as time.RFC3339Nano, which drops trailing zeros (the handler's appendJSONTime), in a -05:00 zone |
| rails/production.log | 93 | real Logger, doc content | Ruby 2.6.10 Logger with Logger::Formatter (the formatter Rails' production.rb sets). Request-id tags are prefixed to every line the way ActiveSupport::TaggedLogging does, and request lines come from https://guides.rubyonrails.org/debugging_rails_applications.html and https://guides.rubyonrails.org/action_controller_overview.html. Rails itself is not installed |

## Post-processing

- Paths: the generators ran from a scratch directory. Its path in tracebacks and stack traces became `/srv/app/`
  (python, plain, node, php). Apache paths are listed in the table. Line counts are unchanged.
- Hostnames: pino and bunyan were given `web-01` through their own options. Monolog's syslog lines had the
  gethostname() value replaced with `web-01`. httpd ran with `ServerName web-01.example.com`. `log show` and
  `log stream` write `localhost` themselves.
- Addresses: Apache's loopback clients were rewritten to documentation ranges, as listed in the table. Every
  other address in these files is from 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24 or 2001:db8::/32.
  0.0.0.0 and `[::]` appear only as listen addresses.
- Process IDs are the real ones from each run.

## Lines that are not entries

- ruby/logger.log line 1: `# Logfile created on … by logger.rb/66358`.
- android/logcat-threadtime.log: the `--------- beginning of main` / `beginning of crash` dividers.
- journald/*.log: the `-- Boot … --` separators.
- macos/*.log: `log show`'s column header, and `log stream`'s `Filtering the log data using …` line plus its
  column header.
- elixir/logger-default.log: the empty line before every entry, which comes from the leading `\n` of the default format.

## Unsure how to map

- The Apache error log expected file is the one answer key here that is not independent of parsing. httpd can
  write only one error log, so a strict regex of the documented format made it. Every line had to match the
  regex, and all 70 did.
- PHP: `Deprecated` maps to notice, as Monolog's ErrorHandler maps E_DEPRECATED. `Fatal error` maps to fatal,
  including uncaught exceptions, TypeError and memory exhaustion.
- java.util.logging: CONFIG maps to info, FINER to debug and FINEST to trace. The component is the source
  class from the first line; the method name after it is dropped.
- winston: `http` maps to info, and `verbose` and `silly` map to trace.
- MySQL: `[System]` and `[Note]` both map to info.
- slog levels between the named ones (`DEBUG-4`, `INFO+2`, `WARN+2`, `ERROR+4`) map to the named base level.
- Heroku: the component is the source without the dyno (`heroku`, `app`), following the syslog rule. Router
  lines take their level from `at=`. `heroku[web.1]` and app lines carry no level (null).
- Docker json-file: the level is null even for `stderr`, and the component is the stream.
- pino: `name` comes before `component` in the key order, so child loggers with `component: "db"` still answer
  `api`. In go/slog-json.log, `service` likewise beats `component` on the lines that have both.
- Rails: the `[request-id]` tag is not treated as a component (null). Continuation lines of a FATAL entry
  repeat the tag.
- PostgreSQL: DETAIL/HINT/CONTEXT/STATEMENT lines repeat the full prefix but continue the entry above them, as
  do tab-indented lines.
- logcat writes each line of a multi-line message (the AndroidRuntime crash) as its own entry, so each is
  counted separately.
- Spring Boot leaves an empty line between the message and the exception, and SimpleFormatter ends a record
  that has a throwable with an empty line. Both empty lines are counted as part of the entry.
- macOS: `log show` and `log stream` gave the same message timestamps about 23 ms apart. Each file's answers
  come from its own tool's ndjson. The component is the process name, not the subsystem or category.
- RFC 3164 lines from Monolog are written in UTC but carry no zone, so they are `"zoned": false`. PHP's
  `[… UTC]` and PostgreSQL's `… UTC` zone abbreviations are `"zoned": true`.
- Ruby Logger `A`/`ANY` (Logger::UNKNOWN) maps to fatal.

## Corrections made when the reader was checked against these answers (2 Nov 2026)

- `macos/show-syslog`: every level is null. `log show --style syslog` prints no level; the answers had taken theirs from
  `--style ndjson`, which the lines themselves do not carry.
- `journald/short` and `journald/short-iso`: a line whose message is logfmt with a `level=` (dockerd's) takes that level,
  as a Heroku router line takes its `at=`. People filter these logs for errors.
- `java/jul-simpleformatter`: SimpleFormatter prints whole seconds, so a reader can only know the time to the second;
  the test allows that truncation rather than changing the answers.
- `java/jul-simpleformatter`: a record with an exception ends with a blank line; that line belongs to no entry, by the
  reader's one rule for every format (a blank line before the next entry is no entry's; one followed by more of the same
  entry, as Spring Boot's before its exception, is that entry's).
