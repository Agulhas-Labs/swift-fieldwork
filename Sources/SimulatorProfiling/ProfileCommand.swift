// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation
import SimulatorServices

/// The `simulator-profile` command: inventory a runtime, boot a stock device, measure what each service costs and write the profile.
public enum ProfileCommand {
    /// Runs the command on `arguments` (after the program name) and answers the exit status; every device it created is deleted before it returns.
    public static func run(arguments: [String], registry: DeviceRegistry = .shared) -> Int32 {
        let options: ProfileOptions
        do {
            options = try ProfileOptions.parse(arguments)
        } catch let error as ProfileUsageError {
            log("simulator-profile: \(error.message)\n\(ProfileOptions.usage)")
            return 64
        } catch {
            return 64
        }
        defer {
            let left = registry.deleteAll()
            if !left.isEmpty {
                log("could not delete the simulators \(left.joined(separator: ", ")); delete each with: xcrun simctl delete <udid>")
            }
        }
        do {
            try profile(options, registry: registry)
            return 0
        } catch {
            log("simulator-profile: \(error)")
            return 1
        }
    }

    /// Deletes every device in `registry` and exits with `128 + signal`, when the process is interrupted, terminated or hung up.
    ///
    /// The returned sources must be kept alive for the handlers to run.
    public static func installSignalCleanup(registry: DeviceRegistry = .shared) -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: DispatchQueue.global())
            source.setEventHandler {
                log("received signal \(number); deleting the simulators created")
                registry.deleteAll()
                exit(128 + number)
            }
            source.resume()
            return source
        }
    }

    private static func profile(_ options: ProfileOptions, registry: DeviceRegistry) throws {
        guard let runtime = try SimulatorRuntime.installed().first(where: { $0.identifier == options.runtime }) else {
            throw ProfileUsageError(message: "the runtime \(options.runtime) is not installed")
        }
        guard runtime.isAvailable else {
            throw ProfileUsageError(message: "the runtime \(options.runtime) is installed but not available on this machine")
        }
        let inventory = try RuntimeInventory.read(runtimeRoot: URL(fileURLWithPath: runtime.runtimeRoot))
        log("inventory: \(inventory.jobs.count) jobs, \(inventory.unreadable.count) unreadable")
        if !options.allowBooted {
            let booted = try bootedDevices()
            if !booted.isEmpty {
                throw ProfileUsageError(message: "a measurement beside another simulator is not a measurement; shut these down or pass --allow-booted: \(booted.joined(separator: ", "))")
            }
        }
        var profile: ServiceProfile
        if options.stage == .health, let path = options.from {
            profile = try JSONDecoder().decode(ServiceProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            guard profile.runtime.identifier == options.runtime else {
                throw ProfileUsageError(message: "the profile \(path) is for \(profile.runtime.identifier), not \(options.runtime)")
            }
        } else {
            profile = try costStage(options, runtime: runtime, inventory: inventory, registry: registry)
        }
        if options.stage != .cost {
            profile = try HealthStage.run(profile, options: options, registry: registry)
        }
        let url = URL(fileURLWithPath: options.output)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(ProfileSwiftSource.json(profile).utf8).write(to: url)
        let counts = Dictionary(grouping: profile.services, by: \.disposition).mapValues(\.count)
        let summary = [Disposition.core, .infrastructure, .disable, .keptByHealth, .belowThreshold, .notRunning].map { "\(counts[$0] ?? 0) \($0.rawValue)" }
        log("wrote \(options.output): \(profile.services.count) services, \(summary.joined(separator: ", "))")
        if let swift = options.swift {
            let swiftURL = URL(fileURLWithPath: swift)
            try FileManager.default.createDirectory(at: swiftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(ProfileSwiftSource.render(profile).utf8).write(to: swiftURL)
            try log("wrote \(swift); add this line to ServiceProfiles.sources: \(ProfileSwiftSource.registryLine(profile))")
        }
    }

    /// Boots a stock device, measures what each service costs and classifies them.
    private static func costStage(_ options: ProfileOptions, runtime: SimulatorRuntime, inventory: RuntimeInventory, registry: DeviceRegistry) throws -> ServiceProfile {
        log("load average at start: \(loadAverage())")
        let device = try ProfileDevice.create(deviceType: options.deviceType, runtime: options.runtime, registry: registry)
        log("created device \(device.udid); booting")
        let measurement: CostMeasurement
        let bootSeconds: Double
        do {
            (measurement, bootSeconds) = try measure(device, window: options.window)
            try device.delete()
        } catch {
            try? device.delete()
            throw error
        }
        log("load average at end: \(loadAverage())")
        logSummary(measurement, inventory: inventory, bootSeconds: bootSeconds)
        let entries = Dispositions.classify(
            jobs: inventory.jobs, cost: measurement.costs,
            footprintThresholdMB: options.footprintThresholdMB, cpuThresholdSeconds: options.cpuThresholdSeconds
        )
        return ServiceProfile(
            profileVersion: options.profileVersion,
            runtime: ProfileRuntime(identifier: runtime.identifier, version: runtime.version, build: runtime.buildversion),
            deviceType: options.deviceType,
            generated: today(),
            method: ProfileMethod(costWindowSeconds: options.window, footprintThresholdMB: options.footprintThresholdMB, cpuThresholdSeconds: options.cpuThresholdSeconds, checks: []),
            services: entries,
            capabilities: capabilities(of: inventory)
        )
    }

    /// Boots the device while sampling it, and answers what it cost and how long the boot took.
    private static func measure(_ device: ProfileDevice, window: Int) throws -> (CostMeasurement, Double) {
        let source = DeviceSamplingSource(device: device)
        try device.boot()
        let booted = DispatchSemaphore(value: 0)
        let outcome = Outcome()
        DispatchQueue.global().async {
            do {
                try device.waitUntilBooted()
                outcome.finish(seconds: source.elapsed(), failure: nil)
            } catch {
                outcome.finish(seconds: source.elapsed(), failure: error)
            }
            booted.signal()
        }
        let measurement = CostSampler(udid: device.udid, window: window).measure(using: source)
        booted.wait()
        let (seconds, failure) = outcome.result
        if let failure {
            throw failure
        }
        return (measurement, seconds)
    }

    private static func logSummary(_ measurement: CostMeasurement, inventory: RuntimeInventory, bootSeconds: Double) {
        log("boot: \(String(format: "%.1f", bootSeconds)) s; samples: \(measurement.samples); failed reads: \(measurement.failures); most processes: \(measurement.maxProcessCount)")
        let outside = measurement.labelsOutside(Set(inventory.jobs.map(\.label)))
        log("running labels outside the inventory: \(outside.count)")
        for byFootprint in [false, true] {
            log("top 15 by \(byFootprint ? "footprint" : "cpu"):")
            for entry in measurement.top(15, byFootprint: byFootprint) {
                let footprint = entry.cost.peakFootprintMB.map { String(format: "%.1f MB", $0) } ?? "no footprint"
                log("  \(entry.label)  \(String(format: "%.2f", entry.cost.cpuSeconds)) s  \(footprint)")
            }
        }
        for label in outside {
            if let cost = measurement.costs[label] {
                log("outside: \(label)  \(String(format: "%.2f", cost.cpuSeconds)) s  \(cost.peakFootprintMB.map { String(format: "%.1f MB", $0) } ?? "no footprint")")
            }
        }
    }

    /// The capabilities that have at least one label in the inventory.
    private static func capabilities(of inventory: RuntimeInventory) -> [Capability: [String]] {
        var result: [Capability: [String]] = [:]
        for capability in Capability.allCases {
            let labels = Capability.labels(for: capability, in: inventory.jobs)
            if !labels.isEmpty {
                result[capability] = labels
            }
        }
        return result
    }

    /// The name and UDID of every device that is booted.
    private static func bootedDevices() throws -> [String] {
        let output = try Subprocess.run("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"], deadline: 30)
        guard output.succeeded else { throw ProfileDeviceError(command: "simctl list devices booted", detail: output.standardError) }
        return try booted(fromListing: Data(output.standardOutput.utf8))
    }

    /// The `name (udid)` of each device in the JSON `simctl list devices booted -j` prints.
    static func booted(fromListing json: Data) throws -> [String] {
        struct Listing: Decodable {
            struct Entry: Decodable {
                let name: String
                let udid: String
            }

            let devices: [String: [Entry]]
        }
        return try JSONDecoder().decode(Listing.self, from: json).devices.values.flatMap(\.self).map { "\($0.name) (\($0.udid))" }.sorted()
    }

    private static func loadAverage() -> String {
        let output = try? Subprocess.run("/usr/sbin/sysctl", ["-n", "vm.loadavg"], deadline: 5)
        return output?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// How the boot wait ended, written on one thread and read on another.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds = 0.0
        private var failure: Error?

        func finish(seconds: Double, failure: Error?) {
            lock.withLock {
                self.seconds = seconds
                self.failure = failure
            }
        }

        var result: (Double, Error?) {
            lock.withLock { (seconds, failure) }
        }
    }
}

extension ProfileUsageError: CustomStringConvertible {
    public var description: String {
        message
    }
}
