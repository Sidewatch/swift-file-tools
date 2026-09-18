//
//  IgnoreGitParityTests.swift
//  FileToolsTests
//
//  The parser against git itself: every pattern corpus is written into a real repository,
//  and the files a parser-driven walk keeps must be exactly the untracked files git lists.
//
//  Created by David Sherlock on 9/18/26.
//

import XCTest
@testable import FileTools

/// The parser against git itself: every pattern corpus is written into a real repository, and
/// the files a parser-driven walk keeps must be exactly the untracked files git lists. This is
/// the one test that can catch a gitignore rule the table tests never thought to write down —
/// git is the oracle, not the spec as we read it.
final class IgnoreGitParityTests: XCTestCase {

    /// One corpus: the ignore files to write (path → text) and the files to create.
    private struct Corpus {
        let name: String
        let ignoreFiles: [String: String]
        let files: [String]
    }

    private static let files: [String] = [
        "a.log", "1.log", "UP.LOG", "x.txt", "keep.log", "important.log", "#name", "!bang.txt",
        "foo", "sub/foo", "sub/a.log", "sub/keep.log", "sub/deep/foo", "sub/deep/x.txt",
        "build/output.log", "build/keep.txt", "build/nested/y.o", "dist/app.js",
        "doc/frotz/readme", "a/doc/frotz/readme", "frotz/top", "x/frotz/inner",
        "abc/xfile", "abc/x/y", "other/x", "a/b", "a/x/b", "a/x/y/b", "a/c",
        "abz", "a/z", "aXYb", "file.txt", "fiile.txt", "ile.txt", "abc.txt", "XYZ.TXT", "1bc.txt",
        "src/main.swift", "src/gen/out.swift", "src/vendor/lib.js", "trail ", "with space.txt",
        "cache.pyc", "cache.pyo", "module.pyd", "notes.md", "README", "logs/app.log",
        "node_modules/pkg/index.js", "pkg/node_modules/dep.js", "a-b.txt", "a]b.txt", "tab\tname",
    ]

    private static let corpora: [Corpus] = [
        Corpus(name: "comments, blanks, trailing spaces, escapes",
               ignoreFiles: ["": "#foo\n\n   \n\\#name\nfoo   \ntrail\\ \n\\!bang.txt\nabc\\\n"],
               files: files),
        Corpus(name: "negation and anchoring",
               ignoreFiles: ["": "*.log\n!important.log\n/foo\nsub/foo\n"],
               files: files),
        Corpus(name: "directory-only patterns",
               ignoreFiles: ["": "doc/frotz/\nfrotz/\nbuild/\n!build/keep.txt\n"],
               files: files),
        Corpus(name: "wildcards and classes",
               ignoreFiles: ["": "/a*z\n?ile.txt\n[a-z]*.txt\n[!a-z]bc.txt\n*.py[cod]\n[Bb]uild/\na]b.txt\n"],
               files: files),
        Corpus(name: "posix classes",
               ignoreFiles: ["": "[[:alpha:]]*.log\n[[:digit:]]bc.txt\n*[[:space:]]*\n[[:upper:]]*.LOG\n"],
               files: files),
        Corpus(name: "double star forms",
               ignoreFiles: ["": "**/foo\nabc/**\na/**/b\na**b\n**/node_modules/\n"],
               files: files),
        Corpus(name: "everything except src",
               ignoreFiles: ["": "/*\n!/src\n!/src/**\n!.gitignore\n"],
               files: files),
        Corpus(name: "nested ignore files override",
               ignoreFiles: ["": "*.log\n*.txt\n", "sub": "!keep.log\n", "sub/deep": "!x.txt\nfoo\n", "src": "gen/\n"],
               files: files),
        Corpus(name: "nested file re-excludes and dir negation cannot reach inside",
               ignoreFiles: ["": "!important.log\nbuild/\n!build/keep.txt\n", "sub": "*.log\n"],
               files: files),
        Corpus(name: "bare double star and slash-only oddities",
               ignoreFiles: ["": "**\n!*/\n!README\n/\n"],
               files: files),
    ]

    private func run(_ arguments: [String], in directory: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", directory.path] + arguments
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
        return String(decoding: data, as: UTF8.self)
    }

    /// The files git considers untracked and not ignored, relative to the root. `git init`
    /// on a case-insensitive volume sets `core.ignorecase`, which folds case in ignore
    /// matching too; the parser matches case-sensitively (ripgrep, fd and git on Linux),
    /// so the oracle is asked with the option off.
    private func gitKept(in root: URL) throws -> Set<String> {
        let out = try run(["-c", "core.ignorecase=false", "ls-files", "-z", "--others", "--exclude-standard"], in: root)
        return Set(out.split(separator: "\u{0}").map(String.init))
    }

    /// A parser-driven walk with the contract the walkers in this package follow: load the
    /// ignore files of each directory, prune an ignored directory whole, collect the rest.
    private func parserKept(in root: URL) -> Set<String> {
        var kept: Set<String> = []
        func walk(_ dir: URL, rel: String, stack: IgnoreStack) {
            let stack = stack.appending(contentsOf: IgnoreStack.load(directory: dir, relativeDirectory: rel,
                                                                     names: [".gitignore"]))
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for entry in entries {
                let name = entry.lastPathComponent
                if name == ".git" { continue }
                let path = rel.isEmpty ? name : rel + "/" + name
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if stack.isIgnored(relativePath: path, isDirectory: isDir) { continue }
                if isDir { walk(entry, rel: path, stack: stack) } else { kept.insert(path) }
            }
        }
        walk(root, rel: "", stack: IgnoreStack())
        return kept
    }

    func testParserKeepsExactlyWhatGitKeeps() throws {
        for corpus in Self.corpora {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ignore-parity-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            for path in corpus.files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url)
            }
            for (dir, text) in corpus.ignoreFiles {
                let url = root.appendingPathComponent(dir).appendingPathComponent(".gitignore")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            _ = try run(["init", "-q"], in: root)
            let git = try gitKept(in: root)
            let ours = parserKept(in: root)
            XCTAssertEqual(ours, git, "\(corpus.name): parser-only \(ours.subtracting(git).sorted()) git-only \(git.subtracting(ours).sorted())")
        }
    }
}
