// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// The override file is what a simulator reads at start, so it must be merged, atomic, world-readable and built only from a real UDID.
struct DisabledServicesOverrideTests {
    private let udid = UUID().uuidString

    @Test
    func writtenLabelsReadBack() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.gizmod", "com.example.loadd"], for: udid)
        #expect(try override.labels(for: udid) == ["com.example.gizmod", "com.example.loadd"])
        #expect(try override.directory(for: udid).lastPathComponent == "com.apple.CoreSimulator.SimDevice.\(udid)")
    }

    @Test
    func mergeKeepsForeignEntries() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        let directory = try override.directory(for: udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try PropertyListSerialization.data(fromPropertyList: ["com.example.foreign": true, "com.example.enabled": false], format: .xml, options: 0)
        try existing.write(to: directory.appendingPathComponent("disabled.plist"))

        try override.write(["com.example.gizmod"], for: udid)

        #expect(try override.labels(for: udid) == ["com.example.foreign", "com.example.gizmod"])
        let data = try Data(contentsOf: directory.appendingPathComponent("disabled.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool])
        #expect(plist["com.example.enabled"] == false)
    }

    @Test
    func fileModeIsWorldReadableAndNoTemporaryFileRemains() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.gizmod"], for: udid)
        try override.write(["com.example.loadd"], for: udid)
        let directory = try override.directory(for: udid)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("disabled.plist").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["disabled.plist"])
    }

    @Test
    func missingFileMeansNoLabels() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        #expect(try DisabledServicesOverride(root: root.url).labels(for: udid).isEmpty)
    }

    @Test
    func removeDeletesTheDirectoryAndToleratesAbsence() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.gizmod"], for: udid)
        let directory = try override.directory(for: udid)
        try override.remove(for: udid)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try override.remove(for: udid)
    }

    @Test
    func anInvalidUDIDIsRefusedEverywhere() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.directory(for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.write(["a"], for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.remove(for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try DisabledServicesOverride.readBack(udid: "../x") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path).isEmpty)
    }

    @Test
    func parsesTheNamedFormat() {
        let output = "disabled services = {\n\t\"com.example.gizmod\" => disabled\n\t\"com.example.loadd\" => enabled\n}\n"
        #expect(DisabledServicesOverride.disabledLabels(fromPrintDisabled: output) == ["com.example.gizmod"])
    }

    @Test
    func parsesTheBooleanFormat() {
        let output = "disabled services = {\n\t\"com.example.gizmod\" => true\n\t\"com.example.loadd\" => false\n}\n"
        #expect(DisabledServicesOverride.disabledLabels(fromPrintDisabled: output) == ["com.example.gizmod"])
    }
}
