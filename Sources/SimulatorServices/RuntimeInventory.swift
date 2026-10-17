// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Whether a launchd job lives in the daemon or the agent directory.
public enum Domain: String, Codable, Sendable {
    case daemon
    case agent
}

/// How a launchd job gets started.
public enum Start: String, Codable, Sendable {
    /// Kept running, so it is up from boot.
    case keepAlive
    /// Started at load.
    case atLoad
    /// Started when something asks one of its Mach services.
    case onDemand
    /// None of the above.
    case other
}

/// One launchd job read from a runtime's property lists.
public struct LaunchJob: Codable, Sendable, Equatable {
    /// The job's `Label`.
    public let label: String
    /// The directory the job came from.
    public let domain: Domain
    /// How the job starts.
    public let start: Start
    /// The program it runs, where the list names one.
    public let program: String?

    public init(label: String, domain: Domain, start: Start, program: String?) {
        self.label = label
        self.domain = domain
        self.start = start
        self.program = program
    }

    /// Classifies one property list, or nil where it has no `Label`.
    static func job(from plist: [String: Any], domain: Domain) -> LaunchJob? {
        guard let label = plist["Label"] as? String, !label.isEmpty else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [Any])?.first as? String
        return LaunchJob(label: label, domain: domain, start: start(of: plist), program: program)
    }

    private static func start(of plist: [String: Any]) -> Start {
        if let keepAlive = plist["KeepAlive"], (keepAlive as? Bool) != false {
            return .keepAlive
        }
        if plist["RunAtLoad"] as? Bool == true {
            return .atLoad
        }
        if let services = plist["MachServices"] as? [String: Any], !services.isEmpty {
            return .onDemand
        }
        return .other
    }
}

/// Every launchd job a runtime ships.
public struct RuntimeInventory: Sendable, Equatable {
    /// The jobs, sorted by label.
    public let jobs: [LaunchJob]
    /// The names of files that did not parse or had no `Label`.
    public let unreadable: [String]

    /// Reads the `*.plist` files of the runtime's launch daemon and launch agent directories; a missing directory is empty.
    public static func read(runtimeRoot: URL) throws -> RuntimeInventory {
        var jobs: [LaunchJob] = []
        var unreadable: [String] = []
        let directories: [(String, Domain)] = [("System/Library/LaunchDaemons", .daemon), ("System/Library/LaunchAgents", .agent)]
        for (path, domain) in directories {
            let directory = runtimeRoot.appendingPathComponent(path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".plist") }
            for name in names.sorted() {
                let data = try? Data(contentsOf: directory.appendingPathComponent(name))
                let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                if let job = plist.flatMap({ LaunchJob.job(from: $0, domain: domain) }) {
                    jobs.append(job)
                } else {
                    unreadable.append(name)
                }
            }
        }
        return RuntimeInventory(jobs: jobs.sorted { $0.label < $1.label }, unreadable: unreadable)
    }
}
