import Foundation

/// A runnable task discovered in a project manifest — the command to type at the
/// terminal, plus where it came from.
public struct ProjectScript: Equatable {
    public let name: String       // e.g. "build"
    public let command: String    // e.g. "npm run build"
    public let source: String     // e.g. "package.json"

    public init(name: String, command: String, source: String) {
        self.name = name
        self.command = command
        self.source = source
    }
}

/// Reads the popular project manifests at a folder root and lists what can be run —
/// npm/pnpm/yarn/bun scripts, Makefile targets, composer scripts. Read-only: a
/// Scripts view reflects the project, it doesn't manage it.
public enum ProjectScripts {

    public static func detect(root: URL) -> [ProjectScript] {
        npm(root) + composer(root) + make(root)
    }

    // MARK: package.json

    private static func npm(_ root: URL) -> [ProjectScript] {
        let file = root.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any] else { return [] }
        let runner = npmRunner(root)   // "npm run" / "pnpm run" / "yarn" / "bun run"
        return scripts.keys.sorted().map {
            ProjectScript(name: $0, command: "\(runner) \($0)", source: "package.json")
        }
    }

    /// The package-manager invocation, chosen from the lockfile present.
    private static func npmRunner(_ root: URL) -> String {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(name).path) }
        if has("bun.lockb") { return "bun run" }
        if has("pnpm-lock.yaml") { return "pnpm run" }
        if has("yarn.lock") { return "yarn" }   // `yarn <script>`, no "run"
        return "npm run"
    }

    // MARK: composer.json

    private static func composer(_ root: URL) -> [ProjectScript] {
        let file = root.appendingPathComponent("composer.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any] else { return [] }
        // composer's own reserved lifecycle hooks aren't things you "run" directly.
        let reserved: Set<String> = ["pre-install-cmd", "post-install-cmd", "pre-update-cmd",
                                     "post-update-cmd", "post-autoload-dump", "pre-autoload-dump"]
        return scripts.keys.sorted().filter { !reserved.contains($0) }.map {
            ProjectScript(name: $0, command: "composer run \($0)", source: "composer.json")
        }
    }

    // MARK: Makefile

    private static func make(_ root: URL) -> [ProjectScript] {
        let file = root.appendingPathComponent("Makefile")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var out: [ProjectScript] = []
        for raw in text.components(separatedBy: .newlines) {
            // A target line: "name:" at column 0, not a variable assignment or a
            // special/.PHONY target, and not a comment.
            guard let colon = raw.firstIndex(of: ":"), !raw.hasPrefix("\t"), !raw.hasPrefix(" "),
                  !raw.hasPrefix(".") , !raw.hasPrefix("#") else { continue }
            // `VAR := value` (and `::=`/`:::=`) puts the '=' AFTER the colon, so the
            // name-side guards below never see it — check the assignment forms here.
            let afterColon = raw[raw.index(after: colon)...].drop(while: { $0 == ":" })
            guard afterColon.first != "=" else { continue }
            let name = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains("="), !name.contains(" "), !name.contains("$"),
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }),
                  seen.insert(name).inserted else { continue }
            out.append(ProjectScript(name: name, command: "make \(name)", source: "Makefile"))
        }
        return out
    }
}
