// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

/// Covers what the tree may say about its own history: no reference into a tracker a reader cannot open, and no dated comment.
///
/// A comment ships with the code and is read by strangers. The one tracker they can open is this repository's own, so `swift-fieldwork` followed by `#` and digits is allowed, as a whole name (at the start of the line or after a character that cannot be part of a repository name), and every other `#` and digits is not.
struct IssueReferenceTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // FieldworkTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    private static var ownTracker: String {
        "swift-fieldwork"
    }

    /// A calendar date in ISO form, bounded by digits so a joined `T` or `_` does not hide it.
    nonisolated(unsafe) static let isoDate = /(?:^|[^0-9])(?:19|20)\d{2}-[01]\d-[0-3]\d(?![0-9])/

    /// A `#` followed by digits that end the token, so a hex colour such as `#1b1d1f` is not a reference.
    ///
    /// A run of exactly six or eight digits (`#000000`) and a run of three or four of one repeated digit (`#333`) are colours too and are set aside. The preceding character is left to ``references(in:)``, which allows the repository's own tracker.
    nonisolated(unsafe) static let issueReference = /#(?!\d{6}\b|\d{8}\b|(\d)\1{2,3}\b)\d+\b/

    /// The line numbers and text of every reference in `text` that does not point at this repository's own tracker.
    static func references(in text: String) -> [(line: Int, text: String)] {
        var found: [(line: Int, text: String)] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let offending = line.matches(of: issueReference).contains { match in
                !isOwnTracker(before: line[..<match.range.lowerBound])
            }
            if offending {
                found.append((line: offset + 1, text: line.trimmingCharacters(in: .whitespaces)))
            }
        }

        return found
    }

    /// Whether `prefix` ends in this repository's name, whole: `other-swift-fieldwork` ends in it too, but names another repository.
    static func isOwnTracker(before prefix: Substring) -> Bool {
        guard prefix.hasSuffix(ownTracker) else { return false }
        guard let previous = prefix.dropLast(ownTracker.count).last else { return true }

        return !(previous.isLetter || previous.isNumber || "_-.".contains(previous))
    }

    /// The comment text of one line, or `nil` when it has none: a `//` comment in Swift, a `#` comment in shell (never a `#!` line).
    static func comment(in line: Substring, shell: Bool) -> Substring? {
        let trimmed = line.drop(while: \.isWhitespace)
        if shell {
            guard trimmed.hasPrefix("#"), !trimmed.hasPrefix("#!") else { return nil }

            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return trimmed
        }

        return line.range(of: " //").map { line[$0.lowerBound...] }
    }

    /// The line numbers and text of every comment in `text` that carries an ISO date.
    static func datedComments(in text: String, shell: Bool) -> [(line: Int, text: String)] {
        var found: [(line: Int, text: String)] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if let comment = comment(in: line, shell: shell), comment.contains(isoDate) {
                found.append((line: offset + 1, text: String(comment)))
            }
        }

        return found
    }

    /// Every file git tracks plus every file it neither tracks nor ignores, less what it reports deleted.
    ///
    /// A new file is inside the check before it is staged. The child's environment has every `GIT_*` variable removed, so a run from a git hook reads this repository and not the one being committed to.
    private static func tree() throws -> [String] {
        let listed = try git(["ls-files", "--cached", "--others", "--exclude-standard"])
        let deleted = try Set(git(["ls-files", "--deleted"]))

        return listed.filter { !deleted.contains($0) }
    }

    private static func git(_ arguments: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", repository.path(percentEncoded: false)] + arguments
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitFailure(arguments: arguments, status: process.terminationStatus)
        }

        return (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
    }

    private static func text(of path: String) -> String? {
        let url = repository.appending(path: path)

        return (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    // MARK: - The tree

    /// No tracked text file carries a `#` and digits that is not this repository's own tracker.
    @Test
    func noFileInTheTreeCarriesAnIssueReference() throws {
        let files = try Self.tree()
        #expect(!files.isEmpty, "git listed no files, so nothing was checked")
        var found: [String] = []
        for path in files {
            guard let text = Self.text(of: path) else { continue }
            for hit in Self.references(in: text) {
                found.append("\(path):\(hit.line): \(hit.text)")
            }
        }
        #expect(found.isEmpty, "issue references:\n\(found.joined(separator: "\n"))")
    }

    /// No comment in a Swift or shell file carries an ISO date.
    @Test
    func noCommentInTheTreeCarriesADate() throws {
        var found: [String] = []
        for path in try Self.tree() {
            let shell = path.hasSuffix(".sh") || path.hasPrefix("githooks/")
            guard shell || path.hasSuffix(".swift"), let text = Self.text(of: path) else { continue }
            for hit in Self.datedComments(in: text, shell: shell) {
                found.append("\(path):\(hit.line): \(hit.text)")
            }
        }

        #expect(found.isEmpty, "dated comments:\n\(found.joined(separator: "\n"))")
    }

    // MARK: - The checks themselves

    /// A reference is found, and the own tracker and a hex colour are not.
    ///
    /// The fixtures are built at run time so this file does not trip its own check.
    @Test
    func theReferenceCheckBites() {
        let number = "12"

        #expect(Self.references(in: "// see #" + number).count == 1)
        #expect(Self.references(in: "// see other-repo#" + number).count == 1)
        #expect(Self.references(in: "// see swift-fieldwork#" + number).isEmpty)
        #expect(Self.references(in: "colour: #1b" + "1d1f").isEmpty)
        #expect(Self.references(in: "colour: #000" + "000").isEmpty)
        #expect(Self.references(in: "one\ntwo #" + number).first?.line == 2)
    }

    /// The own tracker is allowed only as a whole name: at the start of a line or after an owner's `/`, and not as the tail of another repository's name.
    @Test
    func theOwnTrackerIsAWholeName() {
        let number = "5"

        #expect(Self.references(in: "swift-fieldwork#" + number).isEmpty)
        #expect(Self.references(in: "see Agulhas-Labs/swift-fieldwork#" + number).isEmpty)
        #expect(Self.references(in: "// see other-swift-fieldwork#" + number).count == 1)
        #expect(Self.references(in: "// see myswift-fieldwork#" + number).count == 1)
    }

    /// A date is found in a comment and not in a string literal, in Swift and in shell.
    @Test
    func theDateCheckBites() {
        let date = "2026" + "-01-02"

        #expect(Self.datedComments(in: "// on " + date, shell: false).count == 1)
        #expect(Self.datedComments(in: "let a = 1 // " + date, shell: false).count == 1)
        #expect(Self.datedComments(in: "let a = \"" + date + "\"", shell: false).isEmpty)
        #expect(Self.datedComments(in: "# on " + date, shell: true).count == 1)
        #expect(Self.datedComments(in: "#!/bin/sh", shell: true).isEmpty)
    }
}

private extension IssueReferenceTests {
    struct GitFailure: Error {
        let arguments: [String]
        let status: Int32
    }
}
