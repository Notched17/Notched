// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// A scratch home folder with a settings.json, a bundled helper and a place for the installed copy.
private struct Sandbox {
    let root: URL
    let settings: URL
    let cli: URL
    let bundled: URL
    let counter = Counter()

    final class Counter: @unchecked Sendable { var seconds: TimeInterval = 0 }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("notched-installer-\(UUID().uuidString)")
        settings = root.appendingPathComponent(".claude/settings.json")
        cli = root.appendingPathComponent(".local/bin/notched-hook")
        bundled = root.appendingPathComponent("bundle/notched-hook")
        try FileManager.default.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("helper v1".utf8).write(to: bundled)
    }

    var installer: HookInstaller {
        let counter = counter
        return HookInstaller(settingsURL: settings, cliURL: cli, bundledCLI: bundled,
                             now: { Date(timeIntervalSince1970: 1_793_000_000 + counter.seconds) })
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settings)
    }

    func read() -> String? { try? String(contentsOf: settings, encoding: .utf8) }
    func data() -> Data? { try? Data(contentsOf: settings) }

    func backups() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)) ?? [])
            .filter { $0.hasPrefix("settings.json.notched-backup-") }.sorted()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func install(previous: HookInstallRecord? = nil) throws -> HookInstallRecord? {
        let plan = try installer.planInstall(approvalWait: 90).get()
        return try installer.apply(plan, previous: previous).get()
    }
}

@Suite("HookInstaller")
struct HookInstallerTests {
    private let original = """
    {
        "model": "opus",   "env": {"A": "1"},
        "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}
    }

    """

    @Test("Installing with no settings.json creates it, copies the helper, and removing deletes it again")
    func noFile() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let record = try box.install()
        #expect(record?.backupPath == nil)
        #expect(box.installer.status(approvalWait: 90) == .installed)
        #expect(box.installer.cliIsInstalled)
        let mode = try FileManager.default.attributesOfItem(atPath: box.cli.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o755)
        #expect(String(decoding: try Data(contentsOf: box.cli), as: UTF8.self) == "helper v1")

        let plan = try box.installer.planRemove(record: record).get()
        #expect(plan.isRestore)
        #expect(plan.newData == nil)
        _ = try box.installer.apply(plan, previous: record).get()
        #expect(box.read() == nil)
    }

    @Test("Installing over an existing file backs it up, and removing restores it byte for byte")
    func existingFile() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        let before = box.data()
        let record = try #require(try box.install())
        #expect(box.read() != original)
        #expect(box.installer.status(approvalWait: 90) == .installed)
        let backup = try #require(record.backupPath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: backup)) == before)
        #expect(box.backups().count == 1)

        let plan = try box.installer.planRemove(record: record).get()
        #expect(plan.isRestore)
        _ = try box.installer.apply(plan, previous: record).get()
        #expect(box.data() == before)
    }

    @Test("Other settings and hooks survive an install")
    func preserves() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        try box.install()
        let text = try #require(box.read())
        #expect(text.contains("\"model\": \"opus\""))
        #expect(text.contains("say done"))
        #expect(text.contains("notched-hook"))
    }

    @Test("Installing twice changes nothing the second time")
    func twice() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        try box.install()
        let afterFirst = box.data()
        let second = try box.installer.planInstall(approvalWait: 90).get()
        #expect(second.isNoOp)
        try box.install()
        #expect(box.data() == afterFirst)
    }

    @Test("If the user edited the file since, removal takes out only Notched's entries")
    func removeAfterEdit() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        let record = try box.install()
        var text = try #require(box.read())
        text = text.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"sonnet\"")
        try box.write(text)
        let plan = try box.installer.planRemove(record: record).get()
        #expect(!plan.isRestore)
        _ = try box.installer.apply(plan, previous: record).get()
        let result = try #require(box.read())
        #expect(result.contains("\"model\": \"sonnet\""))
        #expect(result.contains("say done"))
        #expect(!result.contains("notched-hook"))
        #expect(box.installer.status(approvalWait: 90) == .notInstalled)
    }

    @Test("Invalid JSON is refused and the file is left exactly as it was")
    func invalidJSON() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let broken = "{ \"model\": \"opus\", oops }"
        try box.write(broken)
        guard case .failure(let error) = box.installer.planInstall(approvalWait: 90) else { Issue.record("accepted invalid JSON"); return }
        #expect(error.text.contains("valid JSON"))
        #expect(box.read() == broken)
        guard case .failure = box.installer.planRemove(record: nil) else { Issue.record("remove accepted invalid JSON"); return }
        #expect(box.backups().isEmpty)
        #expect(!box.installer.cliIsInstalled)
    }

    @Test("Applying refuses if the file changed after the preview")
    func changedSincePreview() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        let plan = try box.installer.planInstall(approvalWait: 90).get()
        try box.write(original.replacingOccurrences(of: "opus", with: "haiku"))
        guard case .failure(let error) = box.installer.apply(plan, previous: nil) else { Issue.record("applied a stale plan"); return }
        #expect(error.text.contains("changed"))
        #expect(box.read()?.contains("haiku") == true)
        #expect(!(box.read()?.contains("notched-hook") ?? true))
    }

    @Test("The file appearing after a no-file preview is also refused")
    func appearedSincePreview() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let plan = try box.installer.planInstall(approvalWait: 90).get()
        try box.write("{\"mine\": true}")
        guard case .failure = box.installer.apply(plan, previous: nil) else { Issue.record("overwrote a new file"); return }
        #expect(box.read() == "{\"mine\": true}")
    }

    @Test("Only the newest five backups are kept, plus the one Remove would restore from")
    func pruning() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        var record: HookInstallRecord?
        for step in 0..<8 {
            box.counter.seconds = Double(step) * 10
            record = try box.install(previous: record)
            // The user changes something, so the next install has a diff and takes a backup.
            try box.write((box.read() ?? "").replacingOccurrences(of: "\"A\": \"\(step)\"", with: "\"A\": \"\(step + 1)\"")
                .replacingOccurrences(of: "\"A\": \"1\"", with: "\"A\": \"0\""))
            try box.write(original.replacingOccurrences(of: "\"A\": \"1\"", with: "\"A\": \"\(step + 2)\""))
        }
        #expect((5...6).contains(box.backups().count))
    }

    @Test("The backup that Remove restores from is never pruned, however many later backups there are")
    func originalBackupProtected() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        let before = box.data()
        let record = try #require(try box.install())
        for step in 1...9 {
            box.counter.seconds = Double(step) * 10
            // The user changes the file, then Notched is updated again (same record kept: the original is still the baseline).
            try box.write((box.read() ?? "").replacingOccurrences(of: "\"A\": \"1\"", with: "\"A\": \"\(step)\""))
            try box.write(original.replacingOccurrences(of: "\"A\": \"1\"", with: "\"A\": \"x\(step)\""))
            _ = try box.install(previous: record)
        }
        let backup = try #require(record.backupPath)
        #expect(FileManager.default.fileExists(atPath: backup))
        #expect(try Data(contentsOf: URL(fileURLWithPath: backup)) == before)
        #expect(box.backups().count <= 6)
    }

    @Test("A symlinked settings.json stays a symlink and its target is updated")
    func symlink() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let dotfiles = box.root.appendingPathComponent("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(original.utf8).write(to: dotfiles)
        try FileManager.default.createDirectory(at: box.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.settings, withDestinationURL: dotfiles)
        try box.install()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: box.settings.path)) == dotfiles.path)
        #expect(try String(contentsOf: dotfiles, encoding: .utf8).contains("notched-hook"))
    }

    @Test("The file's permissions are kept")
    func permissions() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: box.settings.path)
        try box.install()
        let mode = try FileManager.default.attributesOfItem(atPath: box.settings.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test("A newer helper replaces the installed one; an identical one is left alone")
    func helperUpdate() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.installer.installCLI(from: box.bundled)
        let first = try FileManager.default.attributesOfItem(atPath: box.cli.path)[.modificationDate] as? Date
        try box.installer.installCLI(from: box.bundled)
        #expect(try FileManager.default.attributesOfItem(atPath: box.cli.path)[.modificationDate] as? Date == first)
        try Data("helper v2".utf8).write(to: box.bundled)
        try box.installer.installCLI(from: box.bundled)
        #expect(String(decoding: try Data(contentsOf: box.cli), as: UTF8.self) == "helper v2")
    }

    @Test("Without the bundled helper, installing is refused before anything is written")
    func missingHelper() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try box.write(original)
        var installer = box.installer
        installer.bundledCLI = nil
        let plan = try installer.planInstall(approvalWait: 90).get()
        guard case .failure = installer.apply(plan, previous: nil) else { Issue.record("installed without a helper"); return }
        #expect(box.read() == original)
        #expect(box.backups().isEmpty)
    }
}
