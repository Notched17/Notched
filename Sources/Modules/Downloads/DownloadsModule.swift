// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Downloads (#35): progress for browser downloads into `~/Downloads`, as one
/// activity, and a banner when they finish. A thin shell around `DownloadsReducer`
/// over `DownloadsWatcher`.
///
/// Needs the Files & Folders (Downloads) permission, asked only when the module
/// is turned on. Until it's allowed, nothing is watched. Turn it off, or lose
/// the permission, and the stream is removed.
@MainActor
final class DownloadsModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "downloads",
        name: "Downloads",
        symbol: "arrow.down.circle.fill",
        summary: "Progress for your browser downloads beside the notch, and a note when one finishes. Needs access to your Downloads folder.",
        permissions: [.downloadsFolder],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let activityID: ActivityID = "downloads"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(DownloadsSettingsPane(permissions: context.permissions))
    }

    private let context: ModuleContext
    private let directory: String
    private let requiresPermission: Bool
    private let deadline = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = DownloadsReducer()
    private(set) var isRunning = false
    /// The stream on the folder; kept (stopped) after `stop()` so tests can see it was removed.
    private(set) var watcher: DownloadsWatcher?
    private var isWatching = false
    private let log = Log.module("downloads")

    convenience init(context: ModuleContext) {
        self.init(context: context, directory: NSHomeDirectory() + "/Downloads", requiresPermission: true)
    }

    /// - Parameters:
    ///   - directory: the folder to watch (a temporary one in tests).
    ///   - requiresPermission: false in tests, where no permission is involved.
    init(context: ModuleContext, directory: String, requiresPermission: Bool) {
        self.context = context
        self.directory = directory
        self.requiresPermission = requiresPermission
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reducer = DownloadsReducer()
        deadline.action = { [weak self] in self?.send(.tick) }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.send(.wake)
        }
        followPermission()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.invalidate()
        deadline.schedule(at: nil)
        isWatching = false
        watcher?.stop()
        context.activities.endAll()
    }

    #if DEBUG
    /// A simulated look at the folder, as if the watcher had delivered it.
    func simulate(_ scan: DownloadsScan) { handle(scan) }
    #endif

    // MARK: Permission

    /// Watches the folder while the permission is allowed, and only then.
    private func followPermission() {
        guard isRunning else { return }
        let permissions = context.services.permissions
        let status = withObservationTracking {
            requiresPermission ? (permissions?.status(.downloadsFolder) ?? .granted) : PermissionStatus.granted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followPermission() }
        }
        if status == .granted {
            startWatching()
        } else {
            stopWatching()
        }
    }

    private func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        let next = DownloadsWatcher(directory: directory) { [weak self] scan in
            MainActor.assumeIsolated { self?.handle(scan) }
        }
        watcher = next
        next.start()
    }

    private func stopWatching() {
        // Nothing to take down if it never watched (the permission isn't allowed).
        guard isWatching else { return }
        isWatching = false
        watcher?.stop()
        reducer = DownloadsReducer()
        deadline.schedule(at: nil)
        context.activities.endAll()
    }

    // MARK: Events

    private func handle(_ scan: DownloadsScan) {
        guard isRunning else { return }
        log.debug("Looked at the folder: \(scan.entries.count) in progress, \(scan.finals.count) finished")
        send(.scan(scan))
        watcher?.setWatchedNames(reducer.watchedNames)
    }

    private func send(_ event: DownloadsReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .post(let model, let staleDate):
                context.activities.post(DownloadsPresentation.activity(model: model, staleDate: staleDate, open: { [directory] in
                    NSWorkspace.shared.open(URL(fileURLWithPath: directory))
                }))
            case .end:
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .completed(let names):
                context.activities.show(banner(for: names))
            case .schedule(let date):
                deadline.schedule(at: date)
            }
        }
    }

    private func banner(for names: [String]) -> TransientBanner {
        let content = BannerContent(
            symbol: "checkmark.circle.fill", symbolTint: .green, label: "Done",
            value: names.count == 1 ? names[0] : "\(names.count) files"
        )
        let directory = directory
        return TransientBanner.standard(
            id: "downloads.done", moduleID: Self.descriptor.id, content: content, duration: .seconds(4),
            accessibilityLabel: names.count == 1 ? "Downloaded \(names[0]). Click to show in Finder." : "\(names.count) downloads finished. Click to show in Finder.",
            openAction: { Self.reveal(names, in: directory) }
        )
    }

    /// Selects the finished files in Finder, or opens the folder if they've moved.
    private static func reveal(_ names: [String], in directory: String) {
        let urls = names.map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: directory))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

/// Downloads' regions (#35): `.live`, hideable. The ring is Core Animation
/// (`DownloadRing`); nothing here runs a timer of its own.
@MainActor
enum DownloadsPresentation {
    static let tint = Color.cyan

    static func activity(model: DownloadsReducer.Model, staleDate: Date, open: @escaping @MainActor () -> Void) -> LiveActivity {
        LiveActivity(
            id: DownloadsModule.activityID,
            moduleID: DownloadsModule.descriptor.id,
            kind: .live,
            title: "Downloads",
            relevance: 20,
            staleDate: staleDate,
            keylineTint: tint,
            accessibilityLabel: DownloadText.accessibilityLabel(model),
            openAction: open,
            staleNote: StaleNote(text: "No progress for a minute", symbol: "pause.circle"),
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { DownloadRing(progress: model.overall, lineWidth: 2.5).frame(width: 18, height: 18) },
                compactTrailing: IslandRegion {
                    Text(DownloadText.compact(model))
                        .font(IslandFont.compact)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                },
                minimal: IslandRegion {
                    ZStack {
                        DownloadRing(progress: model.overall, lineWidth: 2.5)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 22, height: 22)
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        ZStack {
                            DownloadRing(progress: model.overall, lineWidth: 4)
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(tint)
                        }
                        .frame(width: 40, height: 40)
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion {
                        Text(model.overall.map(DownloadText.percent) ?? DownloadText.compact(model))
                            .font(IslandFont.hero)
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    },
                    bottom: ExpandedRegion { DownloadRows(model: model) }
                )
            )
        )
    }
}

/// A bar for each of up to three downloads; with more, two and "and N more".
/// The expanded island has 160 pt of content, so this is what fits.
private struct DownloadRows: View {
    let model: DownloadsReducer.Model
    private var shown: Int { model.items.count <= 3 ? 3 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(DownloadText.title(count: model.items.count)).font(IslandFont.title)
            ForEach(model.items.prefix(shown), id: \.key) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Spacing.s)
                        Text(DownloadText.detail(item)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(IslandFont.subtitle)
                    if let fraction = item.fraction {
                        ProgressView(value: fraction).progressViewStyle(.linear).controlSize(.mini).tint(DownloadsPresentation.tint)
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.mini).tint(DownloadsPresentation.tint)
                    }
                }
            }
            if model.items.count > shown {
                Text("and \(model.items.count - shown) more")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
