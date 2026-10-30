// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// The file-system side of installing Notched's Claude Code hooks: it reads
/// and backs up `~/.claude/settings.json`, writes it atomically, copies the
/// `notched-hook` helper, and restores exactly what was there on removal.
/// All the JSON editing is `ClaudeSettingsMerger`'s.
struct HookInstaller {
    var settingsURL: URL
    var cliURL: URL
    var bundledCLI: URL?
    var now: @Sendable () -> Date = { Date() }

    static func standard() -> HookInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return HookInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            cliURL: home.appendingPathComponent(".local/bin/notched-hook"),
            bundledCLI: Bundle.main.url(forAuxiliaryExecutable: "notched-hook")
        )
    }

    /// What applying a change would do, shown to the user first.
    struct Plan {
        enum Kind { case install, remove }
        var kind: Kind
        var oldText: String?
        /// The bytes to write; nil deletes the file (it didn't exist before Notched).
        var newData: Data?
        var diff: [LineDiff.Line]
        /// SHA-256 of the file when the plan was made; Apply refuses if it changed since.
        var baseHash: String?
        var backupToTake: Bool
        var isRestore: Bool

        var isNoOp: Bool { diff.isEmpty }
    }

    enum InstallError: Error, Equatable {
        case message(String)
        var text: String { if case .message(let text) = self { text } else { "" } }
    }

    // MARK: Reading

    /// The file's text, nil if it doesn't exist.
    func readSettings() -> Result<String?, InstallError> {
        let url = settingsURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(nil) }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return .failure(.message("Couldn't read \(settingsURL.path) as text, so Notched left it alone."))
        }
        return .success(text)
    }

    func status(approvalWait: Int) -> ClaudeSettingsMerger.Status {
        guard case .success(let text) = readSettings() else { return .notInstalled }
        return ClaudeSettingsMerger.status(of: text, command: cliURL.path, approvalWait: approvalWait)
    }

    var cliIsInstalled: Bool { FileManager.default.isExecutableFile(atPath: cliURL.path) }

    // MARK: Planning

    func planInstall(approvalWait: Int) -> Result<Plan, InstallError> {
        guard case .success(let text) = readSettings() else {
            if case .failure(let error) = readSettings() { return .failure(error) }
            return .failure(.message("Couldn't read settings.json."))
        }
        switch ClaudeSettingsMerger.install(into: text, command: cliURL.path, approvalWait: approvalWait) {
        case .failure(let error): return .failure(.message(error.message))
        case .success(let merged):
            return .success(Plan(kind: .install, oldText: text, newData: Data(merged.utf8),
                                 diff: LineDiff.diff(old: text ?? "", new: merged), baseHash: text.map { Self.hash($0) },
                                 backupToTake: text != nil, isRestore: false))
        }
    }

    /// Removal restores the backup byte for byte when the file is still as
    /// Notched wrote it; otherwise it removes just Notched's entries.
    func planRemove(record: HookInstallRecord?) -> Result<Plan, InstallError> {
        guard case .success(let text) = readSettings() else {
            if case .failure(let error) = readSettings() { return .failure(error) }
            return .failure(.message("Couldn't read settings.json."))
        }
        guard let text else { return .failure(.message("There's no settings.json to change.")) }
        let hash = Self.hash(text)
        if let record, record.writtenHash == hash {
            if let path = record.backupPath {
                if let original = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    let originalText = String(data: original, encoding: .utf8) ?? ""
                    return .success(Plan(kind: .remove, oldText: text, newData: original,
                                         diff: LineDiff.diff(old: text, new: originalText), baseHash: hash, backupToTake: false, isRestore: true))
                }
                // The backup is gone: fall through to editing the file.
            } else {
                // Notched created the file; removing its work removes the file.
                return .success(Plan(kind: .remove, oldText: text, newData: nil, diff: LineDiff.diff(old: text, new: ""),
                                     baseHash: hash, backupToTake: false, isRestore: true))
            }
        }
        switch ClaudeSettingsMerger.remove(from: text) {
        case .failure(let error): return .failure(.message(error.message))
        case .success(let cleaned):
            return .success(Plan(kind: .remove, oldText: text, newData: Data(cleaned.utf8), diff: LineDiff.diff(old: text, new: cleaned),
                                 baseHash: hash, backupToTake: true, isRestore: false))
        }
    }

    // MARK: Applying

    /// Writes the plan. Returns the record to keep (nil after a removal).
    func apply(_ plan: Plan, previous: HookInstallRecord?) -> Result<HookInstallRecord?, InstallError> {
        let fileManager = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()

        // Refuse if the file changed between the preview and now.
        let current = (try? Data(contentsOf: target)).flatMap { String(data: $0, encoding: .utf8) }
        guard current.map({ Self.hash($0) }) == plan.baseHash else {
            return .failure(.message("settings.json changed while you were looking at the preview. Try again."))
        }

        var backupPath = previous?.backupPath
        do {
            if plan.kind == .install {
                guard let bundledCLI else { return .failure(.message("This copy of Notched doesn't include the notched-hook helper.")) }
                try installCLI(from: bundledCLI)
            }
            if plan.backupToTake, current != nil {
                let backup = try takeBackup(of: target)
                // Remember only the first backup of an untouched file: that's "what was there".
                if plan.kind == .install, previous == nil || previous?.writtenHash != plan.baseHash { backupPath = backup.path }
            }
            let mode = (try? fileManager.attributesOfItem(atPath: target.path)[.posixPermissions]) as? NSNumber

            if let data = plan.newData {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                if let mode { try? fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
                // Check what we wrote still parses.
                if case .failure = OrderedJSON.parse(String(decoding: data, as: UTF8.self)) {
                    return .failure(.message("The written file didn't parse; restore it from the backup next to it."))
                }
            } else {
                try fileManager.removeItem(at: target)
            }
        } catch {
            return .failure(.message("Couldn't write settings.json: \(error.localizedDescription)"))
        }

        guard plan.kind == .install, let data = plan.newData else { return .success(nil) }
        let hadFile = plan.oldText != nil
        return .success(HookInstallRecord(backupPath: hadFile ? backupPath : nil, writtenHash: Self.hash(data)))
    }

    private func takeBackup(of file: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = file.deletingLastPathComponent().appendingPathComponent("settings.json.notched-backup-\(formatter.string(from: now()))")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
        try fileManager.copyItem(at: file, to: backup)
        // Keep the newest five.
        let prefix = "settings.json.notched-backup-"
        let backups = ((try? fileManager.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? [])
            .filter { $0.hasPrefix(prefix) }.sorted()
        for old in backups.dropLast(5) {
            try? fileManager.removeItem(at: file.deletingLastPathComponent().appendingPathComponent(old))
        }
        return backup
    }

    /// Copies the helper next to the user's other command-line tools, replacing an older copy.
    func installCLI(from bundled: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: cliURL), let new = try? Data(contentsOf: bundled), existing == new { return }
        if fileManager.fileExists(atPath: cliURL.path) || (try? cliURL.checkResourceIsReachable()) != nil {
            try fileManager.removeItem(at: cliURL)
        }
        try fileManager.copyItem(at: bundled, to: cliURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
    }

    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
