// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The Downloads folder permission (Files & Folders). macOS has no call to read
/// its status without trying: the first read of the folder shows the prompt and
/// blocks until the user answers. `PermissionCenter.refresh()` runs on the main
/// actor, on every activation, so the status probe only reports the answer the
/// last read left behind, and the read itself runs off the main thread.
///
/// Foundation only, so it's tested with a fake opener.
enum DownloadsAccess {
    static let defaultsKey = "permissions.downloadsFolder"

    enum Result: String, Sendable {
        case granted
        case denied
    }

    /// What the last read found, or not determined if there hasn't been one.
    /// Never touches the file system.
    static func status(defaults: UserDefaults = .standard) -> PermissionStatus {
        switch defaults.string(forKey: defaultsKey).flatMap(Result.init(rawValue:)) {
        case .granted: .granted
        case .denied: .denied
        case nil: .notDetermined
        }
    }

    /// Opens the folder and reports what happened. This is what shows the
    /// prompt, and it blocks until it's answered: call it off the main thread.
    /// An error other than a refusal (the folder missing) says nothing.
    static func read(directory: String = NSHomeDirectory() + "/Downloads",
                     open: (String) -> Int32 = openDirectory) -> Result? {
        result(forOpenError: open(directory))
    }

    /// Remembers an answer for `status`.
    static func record(_ result: Result, defaults: UserDefaults = .standard) {
        defaults.set(result.rawValue, forKey: defaultsKey)
    }

    /// `read` then `record`.
    @discardableResult
    static func check(defaults: UserDefaults = .standard,
                      directory: String = NSHomeDirectory() + "/Downloads",
                      open: (String) -> Int32 = openDirectory) -> Result? {
        guard let result = read(directory: directory, open: open) else { return nil }
        record(result, defaults: defaults)
        return result
    }

    static func result(forOpenError error: Int32) -> Result? {
        switch error {
        case 0: .granted
        case EPERM, EACCES: .denied
        default: nil
        }
    }

    /// 0 if the directory opens, otherwise the error number.
    static func openDirectory(_ path: String) -> Int32 {
        guard let handle = opendir(path) else { return errno }
        closedir(handle)
        return 0
    }
}
