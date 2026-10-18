// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation
@testable import SimulatorAnimations
import Testing

struct AnimationsOffLibraryTests {
    private func library(_ variable: String = "GIZMO_ANIMATIONS", in directory: URL) throws -> AnimationsOffLibrary {
        try AnimationsOffLibrary(environmentVariable: variable, directory: directory)
    }

    @Test func `a cache miss compiles once and leaves only the named library`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        var calls: [(String, [String])] = []
        let built = try library(in: directory.url).built { executable, arguments in
            calls.append((executable, arguments))
            let output = try #require(arguments.firstIndex(of: "-o").map { arguments[$0 + 1] })
            try Data("dylib".utf8).write(to: URL(fileURLWithPath: output))
            return Subprocess.Output(succeeded: true, standardOutput: "", standardError: "")
        }
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "/usr/bin/xcrun")
        #expect(Array(calls.first?.1.prefix(5) ?? []) == ["--sdk", "iphonesimulator", "clang", "-dynamiclib", "-fobjc-arc"])
        #expect(calls.first?.1[9] == "-mios-simulator-version-min=15.0")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        #expect(names == [built.lastPathComponent])
        #expect(names.first?.range(of: "^animations-[0-9a-f]{16}\\.dylib$", options: .regularExpression) != nil)
    }

    @Test func `a library already built is not compiled again`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let subject = try library(in: directory.url)
        try Data("dylib".utf8).write(to: subject.path)
        var compiled = false
        let built = try subject.built { _, _ in
            compiled = true
            return Subprocess.Output(succeeded: true, standardOutput: "", standardError: "")
        }
        #expect(!compiled)
        #expect(built == subject.path)
    }

    @Test func `a failed compile throws its first error line and leaves nothing`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        #expect(throws: AnimationsOffLibraryError.notBuilt("a.m:1:1: error: boom")) {
            try library(in: directory.url).built { _, _ in
                Subprocess.Output(succeeded: false, standardOutput: "", standardError: "a.m:1:1: error: boom\nsecond line\n")
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
    }

    @Test func `a timed-out compile reports the timeout rather than the first line`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let timeout = "the spawn timed out: xcrun did not finish within 120s and was ended"
        #expect(throws: AnimationsOffLibraryError.notBuilt(timeout)) {
            try library(in: directory.url).built { _, _ in
                Subprocess.Output(succeeded: false, standardOutput: "", standardError: "warning: x\n\(timeout)\n")
            }
        }
    }

    @Test func `a run that loses the rename returns the winner's library`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let subject = try library(in: directory.url)
        let built = try subject.built { _, arguments in
            let output = try #require(arguments.firstIndex(of: "-o").map { arguments[$0 + 1] })
            try Data("loser".utf8).write(to: URL(fileURLWithPath: output))
            try Data("winner".utf8).write(to: subject.path)
            return Subprocess.Output(succeeded: true, standardOutput: "", standardError: "")
        }
        #expect(built == subject.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [subject.path.lastPathComponent])
        #expect(try String(contentsOf: subject.path, encoding: .utf8) == "winner")
    }

    @Test func `the hash is FNV-1a 64 and names the file`() throws {
        #expect(AnimationsOffLibrary.fnv1a64("") == "cbf29ce484222325")
        #expect(AnimationsOffLibrary.fnv1a64("a") == "af63dc4c8601ec8c")
        #expect(AnimationsOffLibrary.fnv1a64("foobar") == "85944171f73967e8")
        let name = try library(in: URL(fileURLWithPath: "/x")).path.lastPathComponent
        #expect(name == "animations-c34e4fb26dc7a3fc.dylib")
    }

    @Test func `path creates nothing and the compile builds both architectures`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let missing = directory.url.appendingPathComponent("absent", isDirectory: true)
        _ = try library(in: missing).path
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(AnimationsOffLibrary.compileArguments(output: "o", sourceFile: "s.m").contains("x86_64"))
    }

    @Test func `the source names the variable`() throws {
        let source = try library(in: URL(fileURLWithPath: "/x")).source
        #expect(source.contains("getenv(\"GIZMO_ANIMATIONS\")"))
        #expect(source.contains("setenv(\"GIZMO_ANIMATIONS_LOADED\""))
    }

    @Test func `two variables name two files`() throws {
        let directory = URL(fileURLWithPath: "/x")
        #expect(try library("GIZMO_ANIMATIONS", in: directory).path != library("WIDGET_ANIMATIONS", in: directory).path)
    }

    @Test(arguments: ["GIZMO-ANIMATIONS", "gizmo", "", "A\");"])
    func `an invalid variable is refused`(variable: String) {
        #expect(throws: AnimationsOffLibraryError.invalidEnvironmentVariable(variable)) {
            try AnimationsOffLibrary(environmentVariable: variable, directory: URL(fileURLWithPath: "/x"))
        }
    }

    @Test func `the library is added to the inserted libraries`() {
        let library = URL(fileURLWithPath: "/x/lib.dylib")
        #expect(AnimationsOffLibrary.insertingLibrary(library, into: nil) == "/x/lib.dylib")
        #expect(AnimationsOffLibrary.insertingLibrary(library, into: "") == "/x/lib.dylib")
        #expect(AnimationsOffLibrary.insertingLibrary(library, into: "/a.dylib") == "/a.dylib:/x/lib.dylib")
    }

    @Test func `a real compile makes a universal library`() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let built = try library(in: directory.url).built()
        let archs = try Subprocess.run("/usr/bin/lipo", ["-archs", built.path], deadline: 30)
        #expect(archs.succeeded)
        #expect(archs.standardOutput.contains("arm64"))
        #expect(archs.standardOutput.contains("x86_64"))
    }
}
