//
//  ProjectScripts.swift
//  FileTools
//
//  Reads the popular project manifests at a folder root and lists what can be run —
//  npm/pnpm/yarn/bun scripts, Makefile targets, composer scripts.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

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
              let json = JSONObject.parse(data),
              let scripts = json["scripts"] as? [String: Any] else { return [] }
        let runner = npmRunner(root, packageManager: json["packageManager"] as? String)
        return scripts.keys.sorted().map {
            ProjectScript(name: $0, command: "\(runner) \($0)", source: "package.json")
        }
    }

    /// The package-manager invocation: the manifest's `packageManager` field (Corepack's
    /// `"pnpm@9.1.0"`) when it names one, else the lockfile present. Bun has written the
    /// text `bun.lock` since 1.2 and `bun.lockb` before that.
    static func npmRunner(_ root: URL, packageManager: String?) -> String {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(name).path) }
        let declared = packageManager?.split(separator: "@", maxSplits: 1).first.map(String.init)
        switch declared {
        case "bun": return "bun run"
        case "pnpm": return "pnpm run"
        case "yarn": return "yarn"
        case "npm": return "npm run"
        default: break
        }
        if has("bun.lock") || has("bun.lockb") { return "bun run" }
        if has("pnpm-lock.yaml") { return "pnpm run" }
        if has("yarn.lock") { return "yarn" }   // `yarn <script>`, no "run"
        return "npm run"
    }

    // MARK: composer.json

    private static func composer(_ root: URL) -> [ProjectScript] {
        let file = root.appendingPathComponent("composer.json")
        guard let data = try? Data(contentsOf: file),
              let json = JSONObject.parse(data),
              let scripts = json["scripts"] as? [String: Any] else { return [] }
        // composer's own reserved lifecycle hooks aren't things you "run" directly.
        let reserved: Set<String> = ["pre-install-cmd", "post-install-cmd", "pre-update-cmd",
                                     "post-update-cmd", "post-autoload-dump", "pre-autoload-dump"]
        return scripts.keys.sorted().filter { !reserved.contains($0) }.map {
            ProjectScript(name: $0, command: "composer run \($0)", source: "composer.json")
        }
    }

    // MARK: Makefile

    /// The names GNU make tries, in its order.
    static let makefileNames = ["GNUmakefile", "makefile", "Makefile"]

    private static func make(_ root: URL) -> [ProjectScript] {
        // Matched against the directory's own names, not `fileExists`: on a
        // case-insensitive volume every spelling exists, and `source` must read the way
        // the file is actually named.
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
        guard let source = makefileNames.first(where: { present.contains($0) }),
              let text = try? String(contentsOf: root.appendingPathComponent(source), encoding: .utf8) else { return [] }
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
            let names = String(raw[..<colon]).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            // `a b: dep` declares both a and b; a name with `=`, `$` or `%` is a variable,
            // an expansion or a pattern rule, and one such name disqualifies the line.
            guard !names.isEmpty, names.allSatisfy({ name in
                name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
            }) else { continue }
            for name in names where seen.insert(name).inserted {
                out.append(ProjectScript(name: name, command: "make \(name)", source: source))
            }
        }
        return out
    }
}
