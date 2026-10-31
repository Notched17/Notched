// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Clipboard history (#45): an expanded tab with search, pins and click to
/// copy back. A thin shell around `ClipboardReducer`. It polls only
/// `NSPasteboard.changeCount` through the shared scheduler (an integer
/// compare), reads the pasteboard when that moves, and never auto-pastes.
///
/// Off by default. While off it holds nothing: no poll, hotkey or observer.
/// The saved history stays on disk until it is cleared.
@MainActor
final class ClipboardModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "clipboard",
        name: "Clipboard",
        symbol: "clipboard",
        summary: "Remembers what you copy so you can search it and copy it back. Passwords from password managers are skipped.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let tabID = "clipboard"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(ClipboardSettingsPane(settings: context.settings.clipboard, registry: context.registry))
    }

    let model = ClipboardModel()
    private let context: ModuleContext
    private let pasteboard: any ClipboardPasteboard
    private let store: ClipboardStore
    private let writer: ClipboardStoreWriter
    private let usesHotkey: Bool
    private let saveDebounce = OneShotTimer()
    private let observers = NotificationTokens()
    private var pollToken: RefreshToken?
    private var reducer = ClipboardReducer()
    private var isRunning = false
    private let log = Log.module("clipboard")

    private var settings: ClipboardSettings { context.settings.clipboard }

    convenience init(context: ModuleContext) {
        self.init(context: context, pasteboard: SystemClipboardPasteboard(), store: ClipboardStore(directory: ClipboardStore.defaultDirectory()), usesHotkey: true)
    }

    init(context: ModuleContext, pasteboard: any ClipboardPasteboard, store: ClipboardStore, usesHotkey: Bool) {
        self.context = context
        self.pasteboard = pasteboard
        self.store = store
        self.writer = ClipboardStoreWriter(store: store)
        self.usesHotkey = usesHotkey
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.store = store
        model.actions = ClipboardActions(
            copy: { [weak self] id in self?.copyBack(id) },
            togglePin: { [weak self] id in self?.send(.togglePin(id)) },
            delete: { [weak self] id in self?.send(.delete(id)) }
        )
        let saved = store.load()
        send(.configure(settings.reducerConfig))
        send(.loaded(saved))
        model.entries = reducer.state.entries
        writer.removeOrphanImages(keeping: reducer.state.entries)
        send(.tick(changeCount: pasteboard.changeCount))   // the first look is silent

        pollToken = context.scheduler.register("clipboard.poll", every: .milliseconds(500)) { [weak self] in
            guard let self else { return }
            self.send(.tick(changeCount: self.pasteboard.changeCount))
        }
        saveDebounce.action = { [weak self] in self?.saveNow() }
        observers.observe(NSApplication.willTerminateNotification) { [weak self] in
            self?.send(.quit)
            self?.saveNow()
            self?.writer.waitUntilIdle()
        }
        applyHotkeySetting()
        publishTab()
    }

    func stop() {
        guard isRunning else { return }
        saveNow()
        writer.waitUntilIdle()
        isRunning = false
        if let pollToken { context.scheduler.unregister(pollToken) }
        pollToken = nil
        saveDebounce.schedule(at: nil)
        observers.invalidate()
        if usesHotkey { ClipboardHotkey.remove() }
        model.actions = ClipboardActions()
        model.reset()
        reducer = ClipboardReducer()
        context.activities.setTabs([])
    }

    /// The settings pane changed something this module reads.
    func settingsChanged() {
        guard isRunning else { return }
        send(.configure(settings.reducerConfig))
        applyHotkeySetting()
    }

    func clearHistory(includingPinned: Bool = false) { send(.clear(includingPinned: includingPinned)) }

    /// Opens the island on the Clipboard tab. The hotkey and the status menu call this.
    func showHistory() {
        log.info("Opening the Clipboard tab")
        context.services.islandCommands.showTab(Self.tabID, true)
    }

    // MARK: Events and effects

    func send(_ event: ClipboardReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .read(let count): capture(changeCount: count)
            case .persist(let entries):
                model.entries = entries
                saveDebounce.schedule(at: Date().addingTimeInterval(2))
            case .deleteImage(let hash):
                model.forgetImage(hash)
                writer.deleteImage(hash: hash)
            case .writeToPasteboard(let entry):
                if pasteboard.write(entry, store: store) {
                    send(.wrote(changeCount: pasteboard.changeCount))
                    context.services.islandCommands.collapse()
                } else {
                    log.error("Couldn't copy an item back")
                }
            }
        }
    }

    private func copyBack(_ id: UUID) { send(.copyBack(id)) }

    /// Looks at the pasteboard. The policy runs first, so a private item or an
    /// excluded app's copy is never read.
    private func capture(changeCount: Int) {
        let types = pasteboard.typeIdentifiers
        let source = pasteboard.frontmostApp
        let skip = ClipboardPolicy.skipReason(types: types, sourceBundleID: source.bundleID, excludedApps: reducer.state.config.excludedApps)
        let candidate = skip == nil ? pasteboard.readCandidate(store: store) : nil
        send(.captured(ClipboardCapture(typeIdentifiers: types, sourceBundleID: source.bundleID, sourceName: source.name,
                                        candidate: candidate, newID: UUID())))
    }

    private func saveNow() {
        saveDebounce.schedule(at: nil)
        writer.save(reducer.state.entries)
    }

    private func applyHotkeySetting() {
        guard usesHotkey else { return }
        ClipboardHotkey.remove()
        if settings.hotkeyEnabled {
            ClipboardHotkey.install { [weak self] in self?.showHistory() }
        }
    }

    private func publishTab() {
        let model = model
        context.activities.setTabs([IslandTab(
            id: Self.tabID, moduleID: Self.descriptor.id, title: "Clipboard", symbol: "clipboard",
            accessibilityLabel: "Clipboard history", order: 20,
            onVisibilityChange: { visible in if !visible { model.query = "" } }
        ) { ClipboardTabView(model: model) }])
    }

    // MARK: Status menu

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Clipboard History") { [weak self] in self?.showHistory() }]
    }
}

/// Writes happen off the main thread, one at a time and in order, so a big
/// history never stalls the island. `waitUntilIdle` is for quitting.
final class ClipboardStoreWriter: @unchecked Sendable {
    private let store: ClipboardStore
    private let queue = DispatchQueue(label: "me.rkck.Notched.clipboard.store", qos: .utility)

    init(store: ClipboardStore) { self.store = store }

    func save(_ entries: [ClipboardEntry]) {
        let store = store
        queue.async { try? store.save(entries) }
    }

    func deleteImage(hash: String) {
        let store = store
        queue.async { store.deleteImage(hash: hash) }
    }

    func removeOrphanImages(keeping entries: [ClipboardEntry]) {
        let store = store
        queue.async { store.removeOrphanImages(keeping: entries) }
    }

    func waitUntilIdle() { queue.sync {} }
}

// MARK: Model

@MainActor
struct ClipboardActions {
    var copy: (UUID) -> Void = { _ in }
    var togglePin: (UUID) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
}

@MainActor
@Observable
final class ClipboardModel {
    var entries: [ClipboardEntry] = []
    var query = ""
    @ObservationIgnored var actions = ClipboardActions()
    @ObservationIgnored var store: ClipboardStore?
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()

    init() { thumbnails.countLimit = 60 }

    /// What the list shows: the search applied, pinned items first.
    var visible: [ClipboardEntry] {
        ClipboardSearch.displayOrder(ClipboardSearch.filter(entries, query: query))
    }

    func reset() {
        entries = []
        query = ""
        icons.removeAll()
        thumbnails.removeAllObjects()
    }

    /// The source app's icon, found once per app.
    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        icons[bundleID] = icon
        return icon
    }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let store else { return nil }
        if let cached = thumbnails.object(forKey: entry.contentHash as NSString) { return cached }
        guard let image = NSImage(contentsOf: store.thumbnailURL(hash: entry.contentHash)) else { return nil }
        thumbnails.setObject(image, forKey: entry.contentHash as NSString)
        return image
    }

    func forgetImage(_ hash: String) {
        thumbnails.removeObject(forKey: hash as NSString)
    }
}
