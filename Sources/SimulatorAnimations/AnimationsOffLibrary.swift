// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// A compiled simulator library that switches UIKit animations off in the app it is inserted into, through `DYLD_INSERT_LIBRARIES`.
///
/// The consumer names the environment variable and the cache directory. A launch whose environment sets the variable to `on` keeps its animations, and the library sets the variable's name followed by `_LOADED` to `1` in the app's environment, so the app can tell it was loaded. SwiftUI `withAnimation` animations are not affected.
public struct AnimationsOffLibrary: Sendable {
    /// Compiles with an executable and its arguments; the default runs the real compiler.
    public typealias Compile = (_ executable: String, _ arguments: [String]) throws -> Subprocess.Output

    /// The lowest iOS version the library loads on.
    public static var minimumIOS: String {
        "15.0"
    }

    /// The variable whose value `on` keeps animations for a launch.
    public let environmentVariable: String
    /// The consumer's cache directory, where the built library lives.
    public let directory: URL

    /// A library for the variable, which must be upper-case letters, digits and underscores and not start with a digit.
    public init(environmentVariable: String, directory: URL) throws {
        guard environmentVariable.range(of: "^[A-Z_][A-Z0-9_]*$", options: .regularExpression) != nil else {
            throw AnimationsOffLibraryError.invalidEnvironmentVariable(environmentVariable)
        }
        self.environmentVariable = environmentVariable
        self.directory = directory
    }

    /// The Objective-C source of the library.
    public var source: String {
        """
        #import <UIKit/UIKit.h>

        // Switches UIKit animations off in the app it is loaded into; `\(environmentVariable)=on` in a launch's environment keeps them for that launch.
        __attribute__((constructor))
        static void FieldworkAnimationsOff(void) {
            setenv("\(environmentVariable)_LOADED", "1", 1);
            const char *animations = getenv("\(environmentVariable)");
            if (animations && strcmp(animations, "on") == 0) return;
            [UIView setAnimationsEnabled:NO];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                [UIView setAnimationsEnabled:NO];
            }];
        }

        """
    }

    /// The arguments to `xcrun` that compile the source into a universal simulator library.
    public static func compileArguments(output: String, sourceFile: String) -> [String] {
        [
            "--sdk", "iphonesimulator", "clang", "-dynamiclib", "-fobjc-arc",
            "-arch", "arm64", "-arch", "x86_64", "-mios-simulator-version-min=\(minimumIOS)",
            "-framework", "UIKit", "-framework", "Foundation",
            "-o", output, sourceFile,
        ]
    }

    /// The `DYLD_INSERT_LIBRARIES` value with the library added after what is already there.
    public static func insertingLibrary(_ library: URL, into existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return library.path }
        return existing + ":" + library.path
    }

    /// The file the library is built to; it reads and creates nothing.
    ///
    /// The name is a hash of the source and the whole compile command minus its temporary paths, so a changed flag or variable names a new file.
    public var path: URL {
        directory.appendingPathComponent("animations-\(hash).dylib")
    }

    /// The built library, compiling it first when its file is not there yet.
    ///
    /// The source is written and compiled under names of their own and renamed into place, so a run that finds the final name never finds a half-written file, and a failed compile leaves nothing under it.
    public func built(compile: Compile = { try Subprocess.run($0, $1, deadline: 120) }) throws -> URL {
        let library = path
        let manager = FileManager.default
        if manager.fileExists(atPath: library.path) {
            return library
        }
        do { try manager.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
            throw AnimationsOffLibraryError.notBuilt("\(directory.path) could not be created: \(error.localizedDescription)")
        }
        let stem = "animations-\(hash).\(UUID().uuidString)"
        let sourceFile = directory.appendingPathComponent("\(stem).m")
        let scratch = directory.appendingPathComponent("\(stem).dylib")
        defer {
            try? manager.removeItem(at: sourceFile)
            try? manager.removeItem(at: scratch)
        }
        do { try source.write(to: sourceFile, atomically: true, encoding: .utf8) } catch {
            throw AnimationsOffLibraryError.notBuilt("\(sourceFile.path) could not be written: \(error.localizedDescription)")
        }
        let output: Subprocess.Output
        do {
            output = try compile("/usr/bin/xcrun", Self.compileArguments(output: scratch.path, sourceFile: sourceFile.path))
        } catch {
            throw AnimationsOffLibraryError.notBuilt("the compiler could not run: \(error.localizedDescription)")
        }
        guard output.succeeded else {
            let lines = output.standardError.split(whereSeparator: \.isNewline).map(String.init)
            let line = lines.first { $0.contains("the spawn timed out") } ?? lines.first ?? "the compiler exited non-zero"
            throw AnimationsOffLibraryError.notBuilt(line)
        }
        do { try manager.moveItem(at: scratch, to: library) } catch {
            // A concurrent run renamed its own copy into place first; the file there is the same library.
            guard manager.fileExists(atPath: library.path) else {
                throw AnimationsOffLibraryError.notBuilt("\(library.path) could not be written: \(error.localizedDescription)")
            }
        }
        return library
    }

    /// The hash of the source and the compile command that names the file.
    private var hash: String {
        let command = (["/usr/bin/xcrun"] + Self.compileArguments(output: "OUTPUT", sourceFile: "SOURCE")).joined(separator: "\u{1F}")
        return Self.fnv1a64(source + "\u{1E}" + command)
    }

    /// The FNV-1a 64-bit hash of `text`'s UTF-8 bytes, as 16 lowercase hex digits.
    static func fnv1a64(_ text: String) -> String {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
