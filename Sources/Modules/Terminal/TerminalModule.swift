// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Terminal in the notch (#64): an expanded "Terminal" tab hosting a real
/// login shell. A thin shell around `TerminalLifecycleReducer`.
///
/// Off by default, and nothing runs until the tab is first shown. The shell
/// then lives until the module goes off, Notched quits, or the user ends it.
/// Keyboard handling (Esc to the shell, ⌘Esc to collapse, focus only after a
/// click) is `IslandKeyboardPolicy`; see ADR-0026.
@MainActor
final class TerminalModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "terminal",
        name: "Terminal",
        symbol: "terminal",
        summary: "A real shell in the island's Terminal tab. It starts when you first open the tab and keeps running while the island is closed.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let tabID = "terminal"
    /// Content height of the tab; the island grows to fit (the usual limit is 160 pt).
    static let contentHeight: CGFloat = 250

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(TerminalSettingsPane(settings: context.settings.terminal, registry: context.registry))
    }

    let model = TerminalModel()
    private let context: ModuleContext
    private let observers = NotificationTokens()
    private var reducer = TerminalLifecycleReducer()
    private var isRunning = false
    private let log = Log.module("terminal")

    private var settings: TerminalSettings { context.settings.terminal }

    required init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.fontSize = settings.fontSize
        model.actions = TerminalActions(
            newSession: { [weak self] in self?.send(.newSession) },
            endSession: { [weak self] in self?.send(.endSession) },
            requestFocus: { [weak self] in self?.context.services.islandCommands.requestKeyFocus() }
        )
        // No orphan shells: end it on quit even if the host doesn't stop modules first.
        observers.observe(NSApplication.willTerminateNotification) { [weak self] in self?.endShellNow() }
        publishTab()
    }

    func stop() {
        guard isRunning else { return }
        send(.stop)
        isRunning = false
        observers.invalidate()
        context.activities.setTabs([])
        model.reset()
        reducer = TerminalLifecycleReducer()
    }

    /// The settings pane changed the font size.
    func settingsChanged() {
        guard isRunning else { return }
        model.fontSize = settings.fontSize
        model.session?.applyFontSize(settings.fontSize)
    }

    /// The shell's process id, for checking that none is left behind.
    var shellPID: pid_t { model.session?.pid ?? 0 }

    func endSession() { send(.endSession) }

    // MARK: Events and effects

    func send(_ event: TerminalLifecycleReducer.Event) {
        guard isRunning || event == .stop else { return }
        let effects = reducer.reduce(event, now: Date())
        model.phase = reducer.state.phase
        model.givenUp = reducer.isGivenUp
        for effect in effects {
            switch effect {
            case .start(let generation): startShell(generation: generation)
            case .terminate: endShellNow()
            }
        }
    }

    private func startShell(generation: Int) {
        let session = TerminalSession()
        session.applyFontSize(settings.fontSize)
        session.onExit = { [weak self] code in self?.send(.processExited(code: code, generation: generation)) }
        let shell = ShellLauncher.resolveShell(environmentShell: ProcessInfo.processInfo.environment["SHELL"]) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        session.start(shell: shell, home: NSHomeDirectory())
        model.session = session
        model.shellName = (shell as NSString).lastPathComponent
        log.info("Started a \(self.model.shellName, privacy: .public) session")
    }

    /// Ends the running shell now, and waits briefly for it to go.
    private func endShellNow() {
        model.session?.terminate()
    }

    private func publishTab() {
        let model = model
        context.activities.setTabs([IslandTab(
            id: Self.tabID, moduleID: Self.descriptor.id, title: "Terminal", symbol: "terminal",
            accessibilityLabel: "Terminal", order: 30,
            onVisibilityChange: { [weak self] visible in if visible { self?.send(.tabShown) } },
            capturesKeyboard: true,
            maxContentHeight: Self.contentHeight + 60,
            keepsIslandOpen: { model.isPinned }
        ) { TerminalTabView(model: model) }])
    }
}

// MARK: Model

@MainActor
struct TerminalActions {
    var newSession: () -> Void = {}
    var endSession: () -> Void = {}
    var requestFocus: () -> Void = {}
}

@MainActor
@Observable
final class TerminalModel {
    var session: TerminalSession?
    var phase: TerminalLifecycleReducer.Phase = .notStarted
    var givenUp = false
    /// Keep the island open when the pointer leaves.
    var isPinned = false
    var fontSize = TerminalSettings.defaultFontSize
    var shellName = ""
    @ObservationIgnored var actions = TerminalActions()

    func reset() {
        session = nil
        phase = .notStarted
        givenUp = false
        isPinned = false
        shellName = ""
    }
}

// MARK: Views

/// The Terminal tab: the shell, a small control strip, and a message when the
/// shell has ended.
struct TerminalTabView: View {
    @Bindable var model: TerminalModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let session = model.session, model.phase == .running {
                TerminalHostView(session: session, requestFocus: model.actions.requestFocus)
                    .id(ObjectIdentifier(session))
            } else {
                Color.black.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if case .ended(let code, let reason) = model.phase {
                EndedOverlay(code: code, reason: reason, givenUp: model.givenUp) { model.actions.newSession() }
            } else if model.phase == .running {
                Controls(model: model)
            }
        }
        .frame(height: TerminalModule.contentHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Terminal")
    }
}

private struct Controls: View {
    @Bindable var model: TerminalModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text("⌘⎋ closes")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Button(model.isPinned ? "Unpin" : "Keep Open", systemImage: model.isPinned ? "pin.fill" : "pin") { model.isPinned.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(model.isPinned ? Color.orange : Color.secondary)
                .help(model.isPinned ? "The island stays open until you press ⌘Esc" : "Keep the island open when the pointer leaves")
                .accessibilityLabel(model.isPinned ? "Unpin the island" : "Keep the island open")
            Button("End Session", systemImage: "xmark.circle") { model.actions.endSession() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("End this shell")
                .accessibilityLabel("End the shell session")
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(Spacing.xs)
    }
}

private struct EndedOverlay: View {
    let code: Int32?
    let reason: TerminalLifecycleReducer.EndReason
    let givenUp: Bool
    let newSession: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            Text(message)
                .font(IslandFont.subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Session", systemImage: "plus", action: newSession)
                .buttonStyle(.island)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        if givenUp { return "The shell keeps closing straight away. Check your shell and its startup files, then start a new session." }
        switch reason {
        case .userEnded: return "Session ended."
        case .shellExited: return code.map { $0 == 0 ? "The shell exited." : "The shell exited with status \($0)." } ?? "The shell exited."
        }
    }
}

/// Hosts the session's terminal view. The view belongs to the session, so it
/// is moved in and out of the container as the tab is built and torn down.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    let requestFocus: () -> Void

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView(terminal: session.view, requestFocus: requestFocus)
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {}

    static func dismantleNSView(_ nsView: TerminalContainerView, coordinator: ()) {
        nsView.detach()
    }
}

/// A rounded container around the terminal view. Its job is focus: the hosting
/// view never sees a click on the terminal (the terminal is a subview that takes
/// it), so the click is noticed here and the island is asked for keyboard focus;
/// the terminal is then made first responder. Focus is never taken on hover.
final class TerminalContainerView: NSView {
    private let terminal: NSView
    private let requestFocus: () -> Void
    private var keyObserver: (any NSObjectProtocol)?

    init(terminal: NSView, requestFocus: @escaping () -> Void) {
        self.terminal = terminal
        self.requestFocus = requestFocus
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: TerminalModule.contentHeight))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        terminal.removeFromSuperview()
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
    }

    required init?(coder: NSCoder) { nil }

    func detach() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        if terminal.superview === self { terminal.removeFromSuperview() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        // If the panel already has focus (the user clicked the Terminal tab), type straight away.
        if window.isKeyWindow { window.makeFirstResponder(terminal) }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self.terminal)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, NSApp.currentEvent?.type == .leftMouseDown {
            requestFocus()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self.terminal)
            }
        }
        return hit
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: Settings

struct TerminalSettingsPane: View {
    @Bindable var settings: TerminalSettings
    let registry: ModuleRegistry

    private var module: TerminalModule? { registry.module(TerminalModule.descriptor.id) as? TerminalModule }

    var body: some View {
        Form {
            Section {
                LabeledContent("Shell", value: ProcessInfo.processInfo.environment["SHELL"] ?? ShellLauncher.fallbackShell)
                LabeledContent("Starts in", value: "Your home folder, as a login shell")
                Picker("Font size", selection: $settings.fontSize) {
                    ForEach(TerminalSettings.fontSizes, id: \.self) { Text("\($0) pt").tag($0) }
                }
                Button("End Session", role: .destructive) { module?.endSession() }
                    .disabled(module == nil)
            } footer: {
                Text("The shell runs with your own permissions, like Terminal.app. It starts the first time you open the tab and keeps running while the island is closed; it ends when you turn Terminal off or quit Notched.")
            }

            Section {
                LabeledContent("Click the terminal", value: "Focus; the island never takes the keyboard on hover")
                LabeledContent("Esc, arrow keys, Ctrl-C", value: "Go to the shell")
                LabeledContent("⌘Esc", value: "Closes the island")
                LabeledContent("⌘C, ⌘V, ⌘A", value: "Copy, paste, select all")
                LabeledContent("Keep Open", value: "Stops the island closing when the pointer leaves")
            } header: {
                Text("Keys")
            } footer: {
                Text("While the Terminal has focus the island stays open when the pointer leaves, and closes when you click another app (unless kept open).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
        .onChange(of: settings.fontSize) { module?.settingsChanged() }
    }
}
