import Foundation
import Network

/// Apple-native TCP reachability probe for the Screen Sharing port, used as an **optional**
/// readiness enhancement. It is deliberately separate from Jamf command status: a `.unreachable`
/// result is surfaced as a network condition ("not reachable from this network"), never as a
/// Jamf command failure, and it never blocks Open Screen Sharing — the technician can always
/// attempt the connection.
///
/// Uses `Network.framework` (`NWConnection`), not `URLSession`, so no module-local HTTP/auth
/// stack is introduced. The result resolves exactly once (first of: connection ready, connection
/// failed, or timeout) via a lock-guarded session box.
nonisolated struct SupportRemoteSupportReachabilityProbe: Sendable {
    /// Apple Screen Sharing / Remote Management default port.
    let port: UInt16
    /// How long to wait before treating a still-connecting target as not reachable now.
    let timeout: TimeInterval

    init(port: UInt16 = 5900, timeout: TimeInterval = 2.0) {
        self.port = port
        self.timeout = timeout
    }

    func probe(host rawHost: String) async -> SupportRemoteSupportReachability {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false, let nwPort = NWEndpoint.Port(rawValue: port) else {
            return .unknown
        }

        let parameters = NWParameters.tcp
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: parameters
        )
        let session = Session(connection: connection)
        let queue = DispatchQueue(label: "support.remote-support.reachability")

        return await withCheckedContinuation { (continuation: CheckedContinuation<SupportRemoteSupportReachability, Never>) in
            queue.asyncAfter(deadline: .now() + timeout) {
                session.finish { connection.cancel(); continuation.resume(returning: .unreachable) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    session.finish { connection.cancel(); continuation.resume(returning: .reachable) }
                case .failed:
                    session.finish { connection.cancel(); continuation.resume(returning: .unreachable) }
                default:
                    // .waiting (no route / off-VPN) is resolved by the timeout above; .cancelled
                    // only follows our own cancel, after the box is already finished.
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Owns the connection and guarantees the continuation resumes exactly once across the
    /// timeout and the connection state handler (which run on the same probe queue).
    private final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let connection: NWConnection

        init(connection: NWConnection) { self.connection = connection }

        /// Runs `resolve` only for the first caller; later callers are ignored.
        func finish(_ resolve: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard finished == false else { return }
            finished = true
            resolve()
        }
    }
}

//endofline
