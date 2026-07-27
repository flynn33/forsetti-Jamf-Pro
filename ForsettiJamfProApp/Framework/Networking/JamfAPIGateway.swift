import Foundation

/// Standard HTTP methods used by the Jamf Pro API gateway.
///
/// Only the verbs actually invoked by the app are declared here. PATCH was
/// removed after an audit found no call sites — Jamf Pro's v2 endpoints the
/// app exercises use PUT semantics (whole-resource overwrite) rather than
/// PATCH (partial update). If a future feature needs PATCH, add the case
/// back here and reference it at a live call site in the same change.
enum HTTPMethod: String, Sendable {
    /// Retrieve a resource.
    case get = "GET"
    /// Create a new resource.
    case post = "POST"
    /// Replace an existing resource entirely.
    case put = "PUT"
    /// Remove a resource.
    case delete = "DELETE"
}

/// A single `multipart/form-data` part for authenticated Jamf API uploads.
///
/// Keeping multipart encoding in the shared gateway avoids caller-local upload
/// logic and gives every upload the same authentication, retry, and diagnostic
/// behavior as normal JSON requests.
struct JamfMultipartFormPart: Equatable, Sendable {
    let name: String
    let filename: String?
    let contentType: String?
    let data: Data

    nonisolated init(
        name: String,
        filename: String? = nil,
        contentType: String? = nil,
        data: Data
    ) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

/// A decoded page from a Jamf paged endpoint.
struct JamfPage<Element: Sendable>: Sendable {
    let items: [Element]
    let totalCount: Int?

    nonisolated init(items: [Element], totalCount: Int? = nil) {
        self.items = items
        self.totalCount = totalCount
    }
}

/// The accumulated result of walking one Jamf paged endpoint.
struct JamfPagedFetchResult<Element: Sendable>: Sendable {
    let items: [Element]
    let totalCount: Int?
    let pagesFetched: Int
}

/// Shared pagination stop rules for Jamf endpoints that use `page` and `page-size` query items.
enum JamfPaginationPolicy {
    nonisolated static let defaultPageSize = 200
    nonisolated static let safetyPageLimit = 50

    nonisolated static func shouldStop(
        pageRecordCount: Int,
        page: Int,
        pageSize: Int = defaultPageSize,
        totalCount: Int? = nil,
        accumulatedCount: Int? = nil,
        safetyPageLimit: Int = Self.safetyPageLimit
    ) -> Bool {
        if pageRecordCount == 0 || pageRecordCount < pageSize {
            return true
        }
        if let totalCount, let accumulatedCount, accumulatedCount >= totalCount {
            return true
        }
        return page + 1 >= safetyPageLimit
    }
}

// "Would you like to play a game?"

/// An actor-isolated gateway that authenticates and dispatches HTTP requests to the Jamf Pro API.
///
/// `JamfAPIGateway` handles bearer-token injection, automatic 401 retry with token refresh,
/// query parameter assembly, and diagnostic reporting. It delegates credential storage and
/// token lifecycle to `JamfCredentialsStore` and `JamfAuthenticationService` respectively,
/// keeping networking concerns cleanly separated from authentication logic.
///
/// All public methods are `async` and isolated to this actor, ensuring that concurrent
/// callers never race on shared mutable state.
actor JamfAPIGateway {
    /// The store from which saved server credentials are loaded.
    private let credentialsStore: JamfCredentialsStore
    /// The service responsible for obtaining and refreshing bearer tokens.
    private let authenticationService: JamfAuthenticationService
    /// The reporter used to log networking diagnostics (errors, 401 retries, etc.).
    private let diagnosticsReporter: any DiagnosticsReporting
    /// The URL session used for all HTTP requests; defaults to `.shared`.
    private let session: URLSession
    /// Semaphore limiting concurrent Jamf API connections to 5, per Jamf's operational guidance.
    private let connectionSemaphore = AsyncSemaphore(maxConcurrency: 5)

    /// Acquires a semaphore permit, runs `work`, and guarantees the permit is
    /// released on every exit path (success, throw, task cancellation).
    ///
    /// The explicit acquire/release pair that used to live at each call site
    /// leaked permits when `session.data(for:)` threw (DNS failure, cancelled
    /// task, dropped connection): release ran only on the success branch. After
    /// five concurrent failures the gateway soft-deadlocked because no permits
    /// remained to hand out. `defer` inside this helper keeps the permit count
    /// honest.
    private func withPermit<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await connectionSemaphore.acquire()
        defer {
            // Fire-and-forget release. The actor's release() is async but we
            // cannot `await` inside defer; this Task is effectively immediate
            // since release() only mutates actor state without I/O.
            Task { [connectionSemaphore] in
                await connectionSemaphore.release()
            }
        }
        return try await work()
    }

    /// Creates a new API gateway wired to the given dependencies.
    ///
    /// - Parameters:
    ///   - credentialsStore: Provides saved Jamf Pro credentials.
    ///   - authenticationService: Manages bearer token acquisition and refresh.
    ///   - diagnosticsReporter: Receives diagnostic events for observability.
    ///   - session: The URL session to use; defaults to `.shared`.
    init(
        credentialsStore: JamfCredentialsStore,
        authenticationService: JamfAuthenticationService,
        diagnosticsReporter: any DiagnosticsReporting,
        session: URLSession = .shared
    ) {
        self.credentialsStore = credentialsStore
        self.authenticationService = authenticationService
        self.diagnosticsReporter = diagnosticsReporter
        self.session = session
    }

    /// Sends an authenticated HTTP request to the Jamf Pro API and returns the response body.
    ///
    /// The method automatically handles:
    /// 1. Loading credentials from the store
    /// 2. Obtaining a valid bearer token
    /// 3. Building the full URL from the base URL + path + query items
    /// 4. Retrying once with a fresh token if the server responds with 401 Unauthorized
    /// 5. Reporting all failures to the diagnostics subsystem
    ///
    /// - Parameters:
    ///   - path: The API path relative to the Jamf Pro base URL (e.g., "api/v1/computers").
    ///   - method: The HTTP method; defaults to `.get`.
    ///   - queryItems: Optional URL query parameters.
    ///   - body: Optional request body data (typically JSON).
    ///   - additionalHeaders: Extra HTTP headers merged into the request.
    /// - Returns: The raw response body data on success.
    /// - Throws: `JamfFrameworkError` variants for auth, network, or configuration failures.
    func request(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        var retryCount = 0
        let maxRetries = 3

        while true {
            do {
                let credentials = try await currentCredentials()
                guard let baseURL = credentials.normalizedServerURL else {
                    throw JamfFrameworkError.invalidServerURL
                }

                let token = try await authenticationService.accessToken(for: credentials)
                var request = try buildRequest(
                    baseURL: baseURL,
                    path: path,
                    method: method,
                    queryItems: queryItems,
                    body: body,
                    token: token,
                    additionalHeaders: additionalHeaders
                )

                // Verbose per-request trace. Info severity so it lands in the
                // telemetry log, not the error log. Covers every outbound
                // Jamf API call with enough metadata to reconstruct what was
                // sent — body size, retry count, and any non-default headers
                // (but NOT the Authorization header, per privacy rules).
                let requestStart = Date()
                await diagnosticsReporter.report(
                    source: "framework.api-gateway",
                    category: "request-start",
                    severity: .info,
                    message: "Sending Jamf API request.",
                    metadata: [
                        "method": method.rawValue,
                        "path": path,
                        "query_item_count": String(queryItems.count),
                        "body_byte_count": String(body?.count ?? 0),
                        "retry_count": String(retryCount),
                        "has_additional_headers": String(additionalHeaders.isEmpty == false)
                    ]
                )

                // Wrap the network I/O in withPermit so the semaphore count is
                // returned on any path out — success, thrown error, task
                // cancellation. The previous code released only on success;
                // a throw from session.data(for:) (DNS failure, cancellation,
                // dropped connection) leaked the permit. After 5 such failures
                // the gateway would soft-deadlock because no permits remained.
                //
                // `requestSnapshot` is a `let` copy of the `var request` so
                // the `@Sendable` withPermit closure captures an immutable
                // value. Swift 6 strict concurrency rejects `var` capture by
                // a concurrently-executing closure — URLRequest is a value
                // type, so the copy is essentially free.
                let requestSnapshot = request
                let (data, response) = try await withPermit {
                    try await session.data(for: requestSnapshot)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JamfFrameworkError.authenticationFailed
                }

                // Verbose per-response trace. Captures the status code, body
                // size, and elapsed time so slow endpoints are visible without
                // needing URLSessionTaskMetrics wiring.
                let elapsedMs = Int(Date().timeIntervalSince(requestStart) * 1000)
                await diagnosticsReporter.report(
                    source: "framework.api-gateway",
                    category: "request-finish",
                    severity: httpResponse.statusCode >= 400 ? .warning : .info,
                    message: "Jamf API response received.",
                    metadata: [
                        "method": method.rawValue,
                        "path": path,
                        "status_code": String(httpResponse.statusCode),
                        "response_byte_count": String(data.count),
                        "elapsed_ms": String(elapsedMs),
                        "retry_count": String(retryCount)
                    ]
                )

                // Handle 401 — invalidate stale token and retry once with a fresh token
                if httpResponse.statusCode == 401 {
                    await diagnosticsReporter.report(
                        source: "framework.api-gateway",
                        category: "authentication",
                        severity: .warning,
                        message: "Received 401 from Jamf API. Refreshing token.",
                        metadata: ["method": method.rawValue, "path": path]
                    )

                    await authenticationService.invalidateToken()
                    let refreshedToken = try await authenticationService.accessToken(for: credentials)
                    request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")

                    // Same withPermit wrapping as the primary request so the
                    // retry path also returns its permit on error/cancellation.
                    // Snapshot the mutated `request` as a `let` before handing
                    // it to the concurrently-executing closure (see primary
                    // request above for the full rationale).
                    let retryRequestSnapshot = request
                    let (retryData, retryResponse) = try await withPermit {
                        try await session.data(for: retryRequestSnapshot)
                    }
                    guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                        throw JamfFrameworkError.authenticationFailed
                    }

                    // Double-401 means the credentials themselves are invalid
                    if retryHTTPResponse.statusCode == 401 {
                        await diagnosticsReporter.reportError(
                            source: "framework.api-gateway",
                            category: "authentication",
                            message: "Double 401 — credentials appear to be invalid.",
                            metadata: ["method": method.rawValue, "path": path]
                        )
                        throw JamfFrameworkError.credentialsRejected
                    }

                    let retryHeaders = retryHTTPResponse.allHeaderFields
                    return try unwrapResponse(data: retryData, statusCode: retryHTTPResponse.statusCode, headers: retryHeaders)
                }

                // Handle 429 — exponential backoff with Retry-After
                if httpResponse.statusCode == 429 && retryCount < maxRetries {
                    let retryAfter: Int
                    if let retryHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                       let seconds = Int(retryHeader) {
                        retryAfter = seconds
                    } else {
                        // Exponential backoff: 2, 4, 8 seconds
                        retryAfter = Int(pow(2.0, Double(retryCount + 1)))
                    }

                    await diagnosticsReporter.report(
                        source: "framework.api-gateway",
                        category: "throttle",
                        severity: .warning,
                        message: "Rate limited (429). Retrying after \(retryAfter)s.",
                        metadata: [
                            "method": method.rawValue,
                            "path": path,
                            "retry_count": String(retryCount + 1)
                        ]
                    )

                    try await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
                    retryCount += 1
                    continue
                }

                let headers = httpResponse.allHeaderFields
                return try unwrapResponse(data: data, statusCode: httpResponse.statusCode, headers: headers)
            } catch {
                await diagnosticsReporter.reportError(
                    source: "framework.api-gateway",
                    category: "request",
                    message: "Jamf API request failed.",
                    errorDescription: describe(error),
                    metadata: ["method": method.rawValue, "path": path]
                )
                throw error
            }
        }
    }

    /// Uploads one or more parts as `multipart/form-data` through the authenticated gateway.
    ///
    /// Callers supply already-rendered bytes. The gateway builds the multipart
    /// envelope, applies bearer-token authentication, uses the standard retry
    /// path, and records diagnostics through `request(...)`.
    func uploadMultipart(
        path: String,
        method: HTTPMethod = .post,
        queryItems: [URLQueryItem] = [],
        parts: [JamfMultipartFormPart],
        boundary: String = "Boundary-\(UUID().uuidString)",
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        var headers = additionalHeaders
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"

        let body = try Self.makeMultipartBody(parts: parts, boundary: boundary)
        return try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            additionalHeaders: headers
        )
    }

    /// Fetches every page from a Jamf endpoint until the shared stop policy reaches end-of-results.
    ///
    /// The response decoder is caller-supplied because Jamf endpoint envelopes
    /// vary by resource. The page loop, query item construction, retries, and
    /// diagnostics belong in the framework so modules do not duplicate it.
    func pagedRequest<Element: Sendable>(
        path: String,
        pageSize: Int = JamfPaginationPolicy.defaultPageSize,
        startingPage: Int = 0,
        maxPages: Int = JamfPaginationPolicy.safetyPageLimit,
        queryItems: [URLQueryItem] = [],
        pageQueryName: String = "page",
        pageSizeQueryName: String = "page-size",
        decodePage: @Sendable (Data) throws -> JamfPage<Element>
    ) async throws -> JamfPagedFetchResult<Element> {
        guard pageSize > 0 else {
            throw JamfFrameworkError.invalidRequest(message: "Page size must be greater than zero.")
        }
        guard maxPages > 0 else {
            throw JamfFrameworkError.invalidRequest(message: "Max pages must be greater than zero.")
        }

        var page = startingPage
        var pagesFetched = 0
        var accumulatedItems: [Element] = []
        var latestTotalCount: Int?

        while pagesFetched < maxPages {
            let pageQueryItems = queryItems + [
                URLQueryItem(name: pageQueryName, value: String(page)),
                URLQueryItem(name: pageSizeQueryName, value: String(pageSize))
            ]
            let data = try await request(path: path, method: .get, queryItems: pageQueryItems)
            let decodedPage = try decodePage(data)

            accumulatedItems.append(contentsOf: decodedPage.items)
            latestTotalCount = decodedPage.totalCount ?? latestTotalCount
            pagesFetched += 1

            let shouldStop = JamfPaginationPolicy.shouldStop(
                pageRecordCount: decodedPage.items.count,
                page: page,
                pageSize: pageSize,
                totalCount: latestTotalCount,
                accumulatedCount: accumulatedItems.count,
                safetyPageLimit: maxPages
            )

            if shouldStop {
                if decodedPage.items.count >= pageSize,
                   let latestTotalCount,
                   accumulatedItems.count < latestTotalCount,
                   pagesFetched >= maxPages {
                    await diagnosticsReporter.report(
                        source: "framework.api-gateway",
                        category: "pagination",
                        severity: .warning,
                        message: "Paged Jamf API request stopped at the safety page limit.",
                        metadata: [
                            "path": path,
                            "page_size": String(pageSize),
                            "pages_fetched": String(pagesFetched),
                            "accumulated_count": String(accumulatedItems.count),
                            "total_count": String(latestTotalCount)
                        ]
                    )
                }
                break
            }

            page += 1
        }

        return JamfPagedFetchResult(
            items: accumulatedItems,
            totalCount: latestTotalCount,
            pagesFetched: pagesFetched
        )
    }

    // MARK: - Token Introspection

    /// Forces a fresh bearer token and returns the privilege display names it carries.
    ///
    /// Calls `GET /api/v1/auth` — the only supported token-introspection endpoint in Jamf Pro —
    /// after explicitly invalidating any cached token so that a newly-minted token (reflecting
    /// any recent API Role changes) is tested rather than a stale one. The response's
    /// `account.privileges` / `authorizations` array is parsed into a sorted, deduplicated list
    /// of display names suitable for showing in the Diagnostics view.
    ///
    /// This is a debugging aid for the undocumented base-level privilege gate on
    /// `POST /api/v2/mdm/commands` — operators can compare the token's actual privileges
    /// against the privilege matrix required by the endpoint they are hitting.
    ///
    /// Returns the base URL of the currently-configured Jamf Pro server, or
    /// `nil` if no credentials are saved / the stored server URL can't be
    /// parsed. Used by callers that need to deep-link into Jamf Pro's web
    /// UI (e.g. the Remote Management action opens the device's management
    /// page where Jamf Remote Assist lives).
    func currentServerBaseURL() async -> URL? {
        do {
            let credentials = try await MainActor.run(body: {
                try credentialsStore.loadCredentials()
            })
            guard let credentials else { return nil }
            return credentials.normalizedServerURL
        } catch {
            return nil
        }
    }

    /// Forces the authentication service to drop its cached bearer token. The
    /// next request on this gateway will issue a fresh token with whatever
    /// privileges the API Role currently has on the server.
    ///
    /// Useful after a privilege is added to the API Role: Jamf Pro OAuth tokens
    /// carry a privilege snapshot taken at issuance, so a cached token keeps
    /// its original privilege set even after the admin changes the role.
    /// Calling this makes the next MDM command request issue a new token
    /// that picks up the added privilege.
    func invalidateCachedToken() async {
        await authenticationService.invalidateToken()
    }

    /// - Returns: A sorted, deduplicated list of privilege names the token carries.
    /// - Throws: Network or decoding errors from the introspection request.
    func fetchTokenAuthorizations() async throws -> [String] {
        // Force a fresh token — a cached token may still reflect the previous API Role set.
        await authenticationService.invalidateToken()

        let data = try await request(path: "api/v1/auth", method: .get)
        let privileges = Self.parseAuthorizations(from: data)

        // Record the full privilege list as a telemetry event so it survives app restarts
        // and is visible in diagnostics exports. Metadata carries the raw comma-joined list,
        // the count, and severity-elevated presence checks for the three base-level MDM
        // privileges we know can gate POST /api/v2/mdm/commands.
        let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
        let severity: DiagnosticSeverity = privileges.isEmpty ? .warning : .info
        await diagnosticsReporter.report(
            source: "framework.api-gateway",
            category: "token-introspection",
            severity: severity,
            message: privileges.isEmpty
                ? "Token privilege introspection returned no privileges."
                : "Token privilege introspection returned \(privileges.count) privileges.",
            // Presence flags for privileges the app cares about. These use the
            // verbatim Jamf Pro 11.26.1 names as they appear in GET /api/v1/auth;
            // earlier versions of these flags had wrong names (e.g. the actual
            // privilege is "Send Mobile Device Restart Device Command" with
            // "Device" twice — NOT "Send Mobile Device Restart Command"). A
            // flag that checks a non-existent name always reports `false`,
            // which is misleading. Only include privileges that actually exist
            // in Jamf 11.26.1's privilege catalog.
            // Presence flags for privileges the app cares about. `has_view_mdm_command_information`
            // is the critical gate for `POST /api/v2/mdm/commands` — per Jamf's
            // privileges-and-deprecations docs, BOTH `GET` and `POST` of that
            // endpoint require "View MDM command information in Jamf Pro API"
            // (yes, "View" on a POST — counterintuitive Jamf naming). The per-
            // command privileges ("Send Device Information Command" etc.)
            // layer on top of that gate. If the gate privilege is missing, all
            // v2/mdm/commands POSTs return 403 INVALID_PRIVILEGE regardless of
            // which per-command privileges are present.
            metadata: [
                "privilege_count": String(privileges.count),
                "privileges": privileges.joined(separator: ", "),
                "has_view_mdm_command_information": String(privileges.contains("View MDM command information in Jamf Pro API")),
                "has_send_mdm_command_information": String(privileges.contains("Send MDM command information in Jamf Pro API")),
                "has_send_device_information_command": String(privileges.contains("Send Device Information Command")),
                "has_send_computer_restart_command": String(privileges.contains("Send Computer Restart Command")),
                "has_send_mobile_device_restart_device_command": String(privileges.contains("Send Mobile Device Restart Device Command")),
                "has_send_mobile_device_remove_passcode_command": String(privileges.contains("Send Mobile Device Remove Passcode Command")),
                "has_send_mdm_check_in_command": String(privileges.contains("Send MDM Check In Command")),
                "has_flush_mdm_commands": String(privileges.contains("Flush MDM Commands")),
                "has_read_app_installers": String(privileges.contains("Read App Installers")),
                "raw_response_body": rawBody
            ]
        )
        return privileges
    }

    /// Extracts privilege display names from the `GET /api/v1/auth` response body.
    ///
    /// Jamf Pro's response shape varies across versions and deployments. As of 11.26.1
    /// Cloud the canonical location is `account.privilegesBySite` — a dictionary keyed
    /// by site ID (where `"-1"` means global scope) whose values are arrays of privilege
    /// name strings. Older/legacy shapes have been seen at `account.privileges`,
    /// top-level `authorizations`, and top-level `privileges`. This helper tries each
    /// location in turn, flattens nested dictionaries (some versions return
    /// `{ "name": "Privilege X" }` objects instead of raw strings), deduplicates, and sorts.
    ///
    /// - Parameter data: The raw response body from `GET /api/v1/auth`.
    /// - Returns: The sorted, deduplicated privilege names; empty if none could be parsed.
    static func parseAuthorizations(from data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let account = root["account"] as? [String: Any]

        // `privilegesBySite` is a dictionary {siteID: [privileges]}; flatten all values
        // into a single array before running it through the same parse path.
        var flattenedBySite: [Any] = []
        if let bySite = account?["privilegesBySite"] as? [String: Any] {
            for (_, value) in bySite {
                if let array = value as? [Any] {
                    flattenedBySite.append(contentsOf: array)
                }
            }
        }

        let candidates: [Any?] = [
            flattenedBySite.isEmpty ? nil : flattenedBySite,
            account?["privileges"],
            root["authorizations"],
            root["privileges"]
        ]

        for candidate in candidates {
            guard let array = candidate as? [Any], array.isEmpty == false else {
                continue
            }

            var names: Set<String> = []
            for item in array {
                if let name = item as? String {
                    names.insert(name)
                } else if let dict = item as? [String: Any], let name = dict["name"] as? String {
                    names.insert(name)
                }
            }

            if names.isEmpty == false {
                return names.sorted()
            }
        }

        return []
    }

    /// Builds a standards-compliant `multipart/form-data` body for upload endpoints.
    nonisolated static func makeMultipartBody(
        parts: [JamfMultipartFormPart],
        boundary: String
    ) throws -> Data {
        guard isSafeHeaderParameter(boundary), boundary.isEmpty == false else {
            throw JamfFrameworkError.invalidRequest(message: "Multipart boundary is empty or contains invalid header characters.")
        }
        guard parts.isEmpty == false else {
            throw JamfFrameworkError.invalidRequest(message: "Multipart upload requires at least one part.")
        }

        var body = Data()
        for part in parts {
            guard isSafeHeaderParameter(part.name), part.name.isEmpty == false else {
                throw JamfFrameworkError.invalidRequest(message: "Multipart part name is empty or contains invalid header characters.")
            }
            if let filename = part.filename, isSafeHeaderParameter(filename) == false {
                throw JamfFrameworkError.invalidRequest(message: "Multipart filename contains invalid header characters.")
            }
            if let contentType = part.contentType, isSafeHeaderValue(contentType) == false {
                throw JamfFrameworkError.invalidRequest(message: "Multipart content type contains invalid header characters.")
            }

            body.appendString("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.appendString("\(disposition)\r\n")
            if let contentType = part.contentType {
                body.appendString("Content-Type: \(contentType)\r\n")
            }
            body.appendString("\r\n")
            body.append(part.data)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    /// Decodes common Jamf page envelopes into a `JamfPage`.
    ///
    /// Supports top-level arrays and object envelopes with collection keys
    /// commonly used by Jamf Pro APIs, including `results`, `records`, `items`,
    /// `devices`, and `data`.
    nonisolated static func decodePagedCollection<Element: Decodable & Sendable>(
        _ elementType: Element.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder(),
        collectionKeys: [String] = ["results", "records", "items", "devices", "data"]
    ) throws -> JamfPage<Element> {
        if let array = try? decoder.decode([Element].self, from: data) {
            return JamfPage(items: array, totalCount: nil)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JamfFrameworkError.decodingFailure
        }

        let totalCount = int(from: root, paths: ["totalCount", "total", "page.totalElements"])
        for key in collectionKeys {
            guard let arrayObject = root[key] as? [Any] else {
                continue
            }
            let arrayData = try JSONSerialization.data(withJSONObject: arrayObject)
            let items = try decoder.decode([Element].self, from: arrayData)
            return JamfPage(items: items, totalCount: totalCount)
        }

        return JamfPage(items: [], totalCount: totalCount)
    }

    // MARK: - Private Helpers

    nonisolated private static func isSafeHeaderParameter(_ value: String) -> Bool {
        isSafeHeaderValue(value) && value.contains("\"") == false
    }

    nonisolated private static func isSafeHeaderValue(_ value: String) -> Bool {
        value.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n")) == nil
    }

    nonisolated private static func int(from object: [String: Any], paths: [String]) -> Int? {
        for path in paths {
            let components = path.split(separator: ".").map(String.init)
            var current: Any? = object
            for component in components {
                current = (current as? [String: Any])?[component]
            }

            if let int = current as? Int {
                return int
            }
            if let string = current as? String, let int = Int(string) {
                return int
            }
        }
        return nil
    }

    /// Loads saved credentials from the store on the main actor (required by the store's isolation).
    ///
    /// - Returns: The user's saved Jamf Pro credentials.
    /// - Throws: `JamfFrameworkError.missingCredentials` if no credentials are saved.
    private func currentCredentials() async throws -> JamfCredentials {
        guard let credentials = try await MainActor.run(body: {
            try credentialsStore.loadCredentials()
        }) else {
            throw JamfFrameworkError.missingCredentials
        }

        return credentials
    }

    /// Assembles a fully configured `URLRequest` from the provided components.
    ///
    /// Handles path normalization (strips leading slash), query parameter injection,
    /// bearer token header, Accept/Content-Type headers, and any caller-provided extra headers.
    ///
    /// - Parameters:
    ///   - baseURL: The Jamf Pro server base URL.
    ///   - path: The API endpoint path.
    ///   - method: The HTTP method.
    ///   - queryItems: URL query parameters.
    ///   - body: Optional request body.
    ///   - token: The bearer token for authorization.
    ///   - additionalHeaders: Extra headers to merge.
    /// - Returns: A fully configured `URLRequest`.
    /// - Throws: `JamfFrameworkError.invalidServerURL` if URL construction fails.
    private func buildRequest(
        baseURL: URL,
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        body: Data?,
        token: String,
        additionalHeaders: [String: String]
    ) throws -> URLRequest {
        // Strip leading slash to avoid double-slash in the resolved URL
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: normalizedPath)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if queryItems.isEmpty == false {
            components?.queryItems = queryItems
        }

        guard let resolvedURL = components?.url else {
            throw JamfFrameworkError.invalidServerURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Only set Content-Type to JSON if the caller has not provided a custom one
        if body != nil && additionalHeaders["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    /// Validates an HTTP status code and returns the response body, or throws a typed error.
    ///
    /// Maps specific HTTP status codes to dedicated `JamfFrameworkError` cases for
    /// proper downstream handling (e.g., 403 is permanent, 429 needs backoff, 500 is retryable).
    ///
    /// - Parameters:
    ///   - data: The raw response body.
    ///   - statusCode: The HTTP status code from the response.
    ///   - headers: The response headers (used for Retry-After parsing).
    /// - Returns: The response body data if the status is in the 200-299 range.
    /// - Throws: A typed `JamfFrameworkError` based on the status code.
    private func unwrapResponse(data: Data, statusCode: Int, headers: [AnyHashable: Any] = [:]) throws -> Data {
        guard (200 ... 299).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server response"

            switch statusCode {
            case 403:
                throw JamfFrameworkError.forbidden(message: message)
            case 404:
                throw JamfFrameworkError.notFound(message: message)
            case 409:
                throw JamfFrameworkError.conflict(message: message)
            case 429:
                // Parse Retry-After header if present
                let retryAfter: Int?
                if let retryValue = headers["Retry-After"] as? String {
                    retryAfter = Int(retryValue)
                } else if let retryValue = headers["retry-after"] as? String {
                    retryAfter = Int(retryValue)
                } else {
                    retryAfter = nil
                }
                throw JamfFrameworkError.rateLimited(retryAfter: retryAfter)
            case 500, 502, 503:
                throw JamfFrameworkError.serverError(statusCode: statusCode, message: message)
            default:
                throw JamfFrameworkError.networkFailure(statusCode: statusCode, message: message)
            }
        }

        return data
    }

    /// Extracts a human-readable error description, preferring `LocalizedError.errorDescription`.
    ///
    /// - Parameter error: The error to describe.
    /// - Returns: A string suitable for diagnostic metadata.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension Data {
    nonisolated mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

/// A simple actor-based semaphore for limiting concurrent async operations.
///
/// Used to enforce Jamf Pro's recommendation of ≤5 concurrent API connections.
/// Operations call `acquire()` before starting and `release()` when done.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a semaphore with the given maximum concurrency.
    init(maxConcurrency: Int) {
        self.permits = maxConcurrency
    }

    /// Waits until a permit is available, then decrements the count.
    func acquire() async {
        if permits > 0 {
            permits -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// Returns a permit, unblocking one waiter if any are queued.
    func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

//endofline
