// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Network
import Observation

/// The loopback HTTP listener behind `APIGateway`. It binds 127.0.0.1 only,
/// reads one request per connection with hard limits, and hands it to the
/// gateway. It exists only while a module has registered a route.
@MainActor
@Observable
final class LocalAPIServer {
    enum Status: Equatable, Sendable {
        case stopped
        case listening(UInt16)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    @ObservationIgnored var handler: (@Sendable (HTTPRequest, UInt16) async -> HTTPResponse)?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [ObjectIdentifier: APIConnection] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "me.rkck.Notched.localapi")
    private static let maxConnections = 16

    func start(port: UInt16) {
        if case .listening(let current) = status, current == port { return }
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        // Loopback only: never reachable from another machine.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state, port: port) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection, port: port) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            status = .failed("Couldn't listen on port \(port).")
            Log.module("activityapi").error("Listener failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        APIDiscoveryFile.remove()
        status = .stopped
    }

    private func listenerChanged(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            status = .listening(port)
            APIDiscoveryFile.write(port: port)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            status = .failed(error == .posix(.EADDRINUSE) ? "Port \(port) is already in use." : "The listener failed.")
            APIDiscoveryFile.remove()
            Log.module("activityapi").error("Listener failed: \(error.localizedDescription, privacy: .public)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection, port: UInt16) {
        // Defence in depth: only loopback peers.
        guard Self.isLoopback(connection.endpoint), connections.count < Self.maxConnections, let handler else {
            connection.cancel()
            return
        }
        let wrapper = APIConnection(connection: connection, queue: queue) { request in
            await handler(request, port)
        }
        let key = ObjectIdentifier(wrapper)
        connections[key] = wrapper
        wrapper.onFinish = { [weak self] in
            Task { @MainActor in self?.connections[key] = nil }
        }
        wrapper.start()
    }

    nonisolated private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        default: return false
        }
    }
}

/// One connection: reads a request (5 s limit), runs the handler, writes the
/// response and closes. While the handler runs it watches for the peer
/// hanging up and cancels the handler (an approval the client gave up on).
final class APIConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handle: @Sendable (HTTPRequest) async -> HTTPResponse
    private var buffer = Data()
    private var task: Task<Void, Never>?
    private var finished = false
    private var gotRequest = false
    var onFinish: (@Sendable () -> Void)?
    private static let readTimeout: TimeInterval = 5

    init(connection: NWConnection, queue: DispatchQueue, handle: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.connection = connection
        self.queue = queue
        self.handle = handle
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish() }
            if case .cancelled = state { self?.finish() }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.readTimeout) { [weak self] in
            guard let self, !self.gotRequest else { return }
            self.finish()
        }
        receiveRequest()
    }

    func cancel() {
        queue.async { self.finish() }
    }

    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data { self.buffer.append(data) }
            if error != nil { return self.finish() }
            switch HTTPRequestParser.parse(self.buffer) {
            case .needMore:
                if isComplete { self.finish() } else { self.receiveRequest() }
            case .failure(let failure):
                self.gotRequest = true
                self.send(failure.response)
            case .request(let request):
                self.gotRequest = true
                self.run(request)
            }
        }
    }

    private func run(_ request: HTTPRequest) {
        task = Task { [weak self] in
            guard let self else { return }
            let response = await self.handle(request)
            self.queue.async {
                guard !self.finished else { return }
                self.send(response)
            }
        }
        watchForHangup()
    }

    /// Reads one more byte: end-of-stream means the client went away.
    private func watchForHangup() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            guard let self, !self.finished else { return }
            if isComplete || error != nil {
                self.task?.cancel()
                self.finish()
            } else {
                self.watchForHangup()
            }
        }
    }

    private func send(_ response: HTTPResponse) {
        guard !finished else { return }
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        connection.cancel()
        onFinish?()
    }
}

/// Tells local helpers (`notched-hook`) which port the server uses. Holds no
/// secret; the file is private to the user.
enum APIDiscoveryFile {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notched", isDirectory: true)
            .appendingPathComponent("api.json")
    }

    static func write(port: UInt16) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "port": Int(port)])
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.module("activityapi").error("Couldn't write the discovery file")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
