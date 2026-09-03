import Foundation
import Network
import os

/// A one-shot HTTP listener on 127.0.0.1 that catches Spotify's redirect after the user approves
/// the app in the browser. It answers the single request with a small "you can close this tab"
/// page and shuts down.
///
/// Only the loopback interface is bound, the port is fixed (it is part of the redirect URI
/// registered with Spotify), and the listener lives for one callback or until the timeout.
nonisolated enum SpotifyLoopbackServer {
    static func awaitCallback(port: UInt16 = SpotifyPKCE.callbackPort, timeout: Duration = .seconds(300)) async throws -> SpotifyPKCE.Callback {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        // A second attempt right after a failed one must be able to bind the same port.
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "com.emre.mynotch.spotify-callback")
        let box = ContinuationBox()

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? ""
                let callback = SpotifyPKCE.callback(fromRequestLine: requestLine)
                let body = callback == nil
                    ? "<html><body style='font-family:-apple-system'><h3>MyNotch</h3><p>Unexpected request.</p></body></html>"
                    : "<html><body style='font-family:-apple-system'><h3>MyNotch</h3><p>Spotify connected. You can close this tab.</p></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                    if let callback {
                        box.resume(with: .success(callback))
                    } else if let error {
                        box.resume(with: .failure(error))
                    }
                })
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                box.resume(with: .failure(error))
            }
        }

        listener.start(queue: queue)
        defer { listener.cancel() }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: SpotifyPKCE.Callback.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        box.store(continuation)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw SpotifyLibraryError.timedOut
                }
                // Whatever finished first, the other child must end too or the group never returns.
                defer {
                    group.cancelAll()
                    box.resume(with: .failure(CancellationError()))
                }
                return try await group.next()!
            }
        } onCancel: {
            box.resume(with: .failure(CancellationError()))
        }
    }

    /// Resumes a continuation exactly once, from whichever Network callback gets there first.
    private final class ContinuationBox: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<State>(initialState: State())

        private struct State {
            var continuation: CheckedContinuation<SpotifyPKCE.Callback, any Error>?
            var pending: Result<SpotifyPKCE.Callback, any Error>?
        }

        func store(_ continuation: CheckedContinuation<SpotifyPKCE.Callback, any Error>) {
            let pending: Result<SpotifyPKCE.Callback, any Error>? = lock.withLock { state in
                if let pending = state.pending {
                    state.pending = nil
                    return pending
                }
                state.continuation = continuation
                return nil
            }
            if let pending { continuation.resume(with: pending) }
        }

        func resume(with result: Result<SpotifyPKCE.Callback, any Error>) {
            let continuation: CheckedContinuation<SpotifyPKCE.Callback, any Error>? = lock.withLock { state in
                if let continuation = state.continuation {
                    state.continuation = nil
                    return continuation
                }
                if state.pending == nil { state.pending = result }
                return nil
            }
            continuation?.resume(with: result)
        }
    }
}
