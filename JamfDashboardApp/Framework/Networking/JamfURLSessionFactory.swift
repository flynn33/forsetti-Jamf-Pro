import Foundation

// "End of Line"

/// Builds a pre-configured `URLSession` for Jamf Pro API traffic.
///
/// `URLSession.shared` has no request timeout, no resource timeout, no
/// connection budget, and no metrics plumbing. In an enterprise tool
/// that talks to a live Jamf Pro server over potentially flaky VPNs,
/// that default produces two failure modes that are painful to diagnose:
///
/// 1. **Hung requests that never time out** — a dropped TCP connection
///    or a silently-crashed Jamf Pro node leaves the task waiting
///    indefinitely; whatever UI spawned the call freezes until the
///    operator force-quits.
/// 2. **Invisible tail latency** — "slow but working" requests give no
///    visibility into DNS, TCP, TLS, or first-byte timing, so an
///    operator who reports "Jamf Dashboard feels sluggish today" has
///    no artifact we can point at to confirm or refute.
///
/// This factory addresses both. Every session it produces:
///
/// - Times out a single request at 30 s, bounds the whole resource
///   lifetime at 120 s.
/// - Caps concurrent TCP connections at 5 per host (matches the
///   gateway's 5-permit semaphore — no point letting URLSession open
///   more sockets than we're willing to multiplex work across).
/// - Accepts cookies from the main document domain only, supporting
///   Jamf Cloud's session-affinity cookies for multi-step write
///   sequences without leaking cookies across redirects.
/// - Disables URL caching — Jamf Pro's ETag support is inconsistent
///   across versions, and a cached stale response for a resource
///   we just mutated would mislead the operator.
/// - Enforces a TLS floor of 1.2.
/// - Forwards `URLSessionTaskMetrics` to the shared diagnostics
///   reporter on every task completion, so tail-latency investigations
///   don't require external tooling.
enum JamfURLSessionFactory {
    /// Builds a new `URLSession` with the Jamf-optimized configuration
    /// and a metrics delegate wired to the given reporter.
    ///
    /// - Parameter diagnosticsReporter: Destination for `request-metrics`
    ///   events emitted by the session's task delegate.
    /// - Returns: A configured session ready to hand to `JamfAPIGateway`.
    static func make(diagnosticsReporter: any DiagnosticsReporting) -> URLSession {
        let configuration = URLSessionConfiguration.default

        // Per-request timeout: from the moment the request hits the
        // wire to the moment a response byte arrives. 30 s is long
        // enough for slow inventory filters and prestage scope
        // mutations, short enough that a hung endpoint doesn't brick
        // the UI.
        configuration.timeoutIntervalForRequest = 30.0

        // Whole-operation cap: 120 s from task start to finish,
        // including retries and redirects. Beyond this we want a
        // clean cancellation rather than an indefinite wait — the
        // gateway's caller can choose to re-issue if desired.
        configuration.timeoutIntervalForResource = 120.0

        // Match the gateway's `AsyncSemaphore(maxConcurrency: 5)`.
        // URLSession's default is 6 per host, which is one more
        // connection than our concurrency cap would ever use — bring
        // it in line so the socket budget matches the task budget.
        configuration.httpMaximumConnectionsPerHost = 5

        // Jamf Cloud's load balancer uses session-affinity cookies
        // for multi-step write chains (prestage scope mutation with
        // versionLock, package deployments, etc.). Accept cookies
        // from the primary host only so redirects don't leak cookies
        // into unrelated domains.
        configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        configuration.httpShouldSetCookies = true

        // Authenticated API responses must not be cached — Jamf Pro's
        // ETag behavior is inconsistent across versions, and a stale
        // cached response for a freshly-mutated resource would show
        // the operator out-of-date data with no indication of
        // staleness.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Refuse to downgrade below TLS 1.2. The platform default is
        // already 1.2, but pinning this explicitly means a future OS
        // change (if Apple ever lowered the floor) can't silently
        // regress Jamf traffic.
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12

        // Allow cellular and expensive networks — Jamf Dashboard runs
        // in the field where tech accounts may not be on corporate
        // Wi-Fi. `waitsForConnectivity` lets the task queue while the
        // device transitions between networks instead of failing
        // immediately.
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        let delegate = JamfURLSessionMetricsDelegate(diagnosticsReporter: diagnosticsReporter)
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

/// Forwards `URLSessionTaskMetrics` to diagnostics on every task
/// completion, so tail-latency investigations have concrete data
/// rather than operator impressions.
///
/// One event per task — `framework.api-gateway`/`request-metrics` —
/// carrying DNS, secure-connection, and response-start timings,
/// count of intermediate redirects, and whether the connection was
/// reused. These land in `jamf-dashboard-telemetry.ndjson` and surface
/// in the Diagnostics export.
///
/// `@unchecked Sendable` because `NSObject` isn't Sendable under Swift 6
/// strict concurrency. Our stored state is a single immutable reporter
/// reference, so the absence of compiler-checked sendability is safe in
/// practice. URLSession manages its own delegate thread dispatch.
final class JamfURLSessionMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let diagnosticsReporter: any DiagnosticsReporting

    init(diagnosticsReporter: any DiagnosticsReporting) {
        self.diagnosticsReporter = diagnosticsReporter
        super.init()
    }

    /// Emits a single `request-metrics` telemetry event per completed
    /// task. Only the final transaction is summarized (redirect chains
    /// produce multiple entries; we focus on the one the caller
    /// received a response from).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        // Snapshot the values off the metrics object immediately —
        // the metrics object is not Sendable, so we can't move it
        // into the Task below. Extracting plain Doubles/Strings is safe.
        guard let finalTransaction = metrics.transactionMetrics.last else { return }

        let method = task.originalRequest?.httpMethod ?? "UNKNOWN"
        let urlString = task.originalRequest?.url?.absoluteString ?? "<no-url>"
        let redirectCount = metrics.redirectCount
        let totalMs = Int(metrics.taskInterval.duration * 1000)

        let dnsMs = durationMilliseconds(
            from: finalTransaction.domainLookupStartDate,
            to: finalTransaction.domainLookupEndDate
        )
        let tcpMs = durationMilliseconds(
            from: finalTransaction.connectStartDate,
            to: finalTransaction.connectEndDate
        )
        let tlsMs = durationMilliseconds(
            from: finalTransaction.secureConnectionStartDate,
            to: finalTransaction.secureConnectionEndDate
        )
        let requestMs = durationMilliseconds(
            from: finalTransaction.requestStartDate,
            to: finalTransaction.requestEndDate
        )
        let ttfbMs = durationMilliseconds(
            from: finalTransaction.requestEndDate,
            to: finalTransaction.responseStartDate
        )

        let connectionReused = finalTransaction.isReusedConnection ? "true" : "false"
        let networkProtocol = finalTransaction.networkProtocolName ?? ""
        let statusCode = (finalTransaction.response as? HTTPURLResponse)?.statusCode ?? 0

        let reporter = diagnosticsReporter
        Task {
            await reporter.report(
                source: "framework.api-gateway",
                category: "request-metrics",
                severity: .info,
                message: "URLSessionTaskMetrics collected.",
                metadata: [
                    "method": method,
                    "url": urlString,
                    "status_code": String(statusCode),
                    "total_ms": String(totalMs),
                    "dns_ms": dnsMs.map { String($0) } ?? "",
                    "tcp_ms": tcpMs.map { String($0) } ?? "",
                    "tls_ms": tlsMs.map { String($0) } ?? "",
                    "request_ms": requestMs.map { String($0) } ?? "",
                    "ttfb_ms": ttfbMs.map { String($0) } ?? "",
                    "redirect_count": String(redirectCount),
                    "connection_reused": connectionReused,
                    "network_protocol": networkProtocol
                ]
            )
        }
    }

    /// Returns the duration in whole milliseconds between two optional
    /// dates, or `nil` if either is missing (some phases are skipped
    /// for reused connections).
    private func durationMilliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }
}

//endofline
