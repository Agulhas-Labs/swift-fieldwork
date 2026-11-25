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
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["disabled.plist", "fieldwork-disabled.plist"])
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
    func aLaterWriteSwitchesBackOnWhatItNoLongerLists() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.a", "com.example.b"], for: udid)
        try override.write(["com.example.a"], for: udid)
        #expect(try override.labels(for: udid) == ["com.example.a"])
        #expect(try plist(override).keys.sorted() == ["com.example.a"])
    }

    @Test
    func aLaterWriteRestoresAPriorFalseEntry() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try seed(override, ["com.example.b": false])
        try override.write(["com.example.a", "com.example.b"], for: udid)
        try override.write(["com.example.a"], for: udid)
        #expect(try plist(override)["com.example.b"] == false)
    }

    @Test
    func restorePutsBackExactlyWhatWasThere() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try seed(override, ["com.example.foreign": true, "com.example.b": false, "com.example.c": true])
        try override.write(["com.example.a", "com.example.b", "com.example.c"], for: udid)
        try override.restore(for: udid)
        #expect(try plist(override) == ["com.example.foreign": true, "com.example.b": false, "com.example.c": true])
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path) == ["disabled.plist"])
    }

    @Test
    func restoreOfAnOnlyWrittenFileDeletesThePlistButNotTheDirectory() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.a"], for: udid)
        try override.restore(for: udid)
        let directory = try override.directory(for: udid)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test
    func restoreWithNothingWrittenIsANoOp() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.restore(for: udid)
        try seed(override, ["com.example.foreign": true])
        try override.restore(for: udid)
        #expect(try plist(override) == ["com.example.foreign": true])
    }

    @Test(arguments: [DisabledServicesOverride.WriteStep.recordSaved, .overrideSaved])
    func aWriteInterruptedAtAnyPointStillRestoresExactly(step: DisabledServicesOverride.WriteStep) throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        let original = ["com.example.foreign": true, "com.example.b": false]
        try seed(override, original)
        try override.write(["com.example.a", "com.example.b"], for: udid)
        #expect(throws: Interrupted.self) { try interrupted(at: step, root: root.url).write(["com.example.b", "com.example.c"], for: udid) }
        try override.restore(for: udid)
        #expect(try plist(override) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path) == ["disabled.plist"])
    }

    @Test(arguments: [DisabledServicesOverride.WriteStep.recordSaved, .overrideSaved])
    func aRetriedWriteAfterAnInterruptionStillRestoresExactly(step: DisabledServicesOverride.WriteStep) throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        let original = ["com.example.foreign": true, "com.example.b": false]
        try seed(override, original)
        try override.write(["com.example.a", "com.example.b"], for: udid)
        #expect(throws: Interrupted.self) { try interrupted(at: step, root: root.url).write(["com.example.b", "com.example.c"], for: udid) }
        try override.write(["com.example.b", "com.example.c"], for: udid)
        #expect(try override.labels(for: udid) == ["com.example.foreign", "com.example.b", "com.example.c"])
        try override.restore(for: udid)
        #expect(try plist(override) == original)
    }

    @Test
    func aRepeatedWriteKeepsTheFirstPriorFalse() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try seed(override, ["com.example.b": false])
        try override.write(["com.example.b"], for: udid)
        try override.write(["com.example.b"], for: udid)
        try override.restore(for: udid)
        #expect(try plist(override) == ["com.example.b": false])
    }

    @Test
    func aRepeatedWriteKeepsTheFirstPriorAbsence() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.a"], for: udid)
        try override.write(["com.example.a"], for: udid)
        try override.restore(for: udid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path).isEmpty)
    }

    @Test
    func anEmptyWriteOnAFreshDeviceLeavesNoFiles() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write([], for: udid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path).isEmpty)
    }

    @Test
    func anEmptiedSetThenRestoreLeavesNoFiles() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try override.write(["com.example.a"], for: udid)
        try override.write([], for: udid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path).isEmpty)
        try override.restore(for: udid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path).isEmpty)
    }

    @Test
    func restoreDeletesAnEntrylessFileItDoesNotOwn() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try seed(override, [:])
        try override.restore(for: udid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: override.directory(for: udid).path).isEmpty)
    }

    @Test(arguments: try [
        Data("garbage".utf8),
        PropertyListSerialization.data(fromPropertyList: ["com.example.a"], format: .xml, options: 0),
        PropertyListSerialization.data(fromPropertyList: ["com.example.a": "maybe"], format: .xml, options: 0),
    ])
    func anUnreadableRecordThrowsAndChangesNothing(record: Data) throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        try seed(override, ["com.example.a": true])
        let directory = try override.directory(for: udid)
        let sidecar = directory.appendingPathComponent("fieldwork-disabled.plist")
        try record.write(to: sidecar)
        let before = try Data(contentsOf: directory.appendingPathComponent("disabled.plist"))
        for change in [{ try override.write(["com.example.b"], for: udid) }, { try override.restore(for: udid) }] {
            let error = #expect(throws: SimulatorServicesError.self) { try change() }
            guard case let .unreadableOverride(path, _)? = error else {
                Issue.record("expected unreadableOverride, got \(String(describing: error))")
                continue
            }
            #expect(path == sidecar.path)
            #expect(try Data(contentsOf: directory.appendingPathComponent("disabled.plist")) == before)
            #expect(try Data(contentsOf: sidecar) == record)
        }
    }

    @Test
    func anUnreadableFileThrowsAndChangesNothing() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        let directory = try override.directory(for: udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("disabled.plist")
        try Data("garbage".utf8).write(to: target)
        #expect(throws: SimulatorServicesError.self) { try override.write(["com.example.b"], for: udid) }
        #expect(throws: SimulatorServicesError.self) { try override.restore(for: udid) }
        #expect(try Data(contentsOf: target) == Data("garbage".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["disabled.plist"])
    }

    private struct Interrupted: Error {}

    private func interrupted(at step: DisabledServicesOverride.WriteStep, root: URL) -> DisabledServicesOverride {
        DisabledServicesOverride(root: root) { reached in
            if reached == step {
                throw Interrupted()
            }
        }
    }

    private func seed(_ override: DisabledServicesOverride, _ entries: [String: Bool]) throws {
        let directory = try override.directory(for: udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0).write(to: directory.appendingPathComponent("disabled.plist"))
    }

    private func plist(_ override: DisabledServicesOverride) throws -> [String: Bool] {
        let data = try Data(contentsOf: override.directory(for: udid).appendingPathComponent("disabled.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool])
    }

    @Test
    func anInvalidUDIDIsRefusedEverywhere() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let override = DisabledServicesOverride(root: root.url)
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.directory(for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.write(["a"], for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.remove(for: "../x") }
        #expect(throws: SimulatorServicesError.invalidUDID("../x")) { try override.restore(for: "../x") }
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
