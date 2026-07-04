import XCTest
@testable import ForsettiJamfProApp

/// A mutable clock so tests can advance time between service calls.
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ start: Date) { self.now = start }
    var provider: @Sendable () -> Date { { [self] in self.now } }
}

final class TemporaryAdminElevationServiceTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeService(
        scope: MockRequestScopeService,
        reloader: MockInventoryReloader,
        diagnostics: RecordingDiagnostics,
        clock: TestClock,
        requireTicket: Bool = true
    ) -> TemporaryAdminElevationService {
        TemporaryAdminElevationService(
            configuration: TemporaryAdminTestSupport.enabledConfiguration(requireTicket: requireTicket),
            requestScopeService: scope,
            diagnostics: diagnostics,
            inventoryReloader: reloader,
            dateProvider: clock.provider
        )
    }

    // MARK: - Request

    func test_requestAddsComputerToConfiguredDurationScope() async throws {
        let scope = MockRequestScopeService()
        let reloader = MockInventoryReloader(details: [])
        let diags = RecordingDiagnostics()
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: diags, clock: clock)

        let request = try await service.requestElevation(
            for: TemporaryAdminTestSupport.makeDetail(),
            duration: .fifteen,
            reason: "needs admin",
            ticketReference: "TICKET-1"
        )

        XCTAssertEqual(request.duration, .fifteen)
        let adds = await scope.addCalls()
        XCTAssertEqual(adds.count, 1)
        XCTAssertEqual(adds.first?.scopeId, "515", "Should add to the 15m scope.")
        XCTAssertEqual(adds.first?.computerId, "1234")
        let hasRequest = await diags.hasCategory(TemporaryAdminDiagnostics.Category.request)
        XCTAssertTrue(hasRequest)
    }

    func test_requestPermissionFailureThrowsAndReportsPermissionDiagnostic() async throws {
        let scope = MockRequestScopeService(addError: JamfFrameworkError.forbidden(message: "denied"))
        let reloader = MockInventoryReloader(details: [])
        let diags = RecordingDiagnostics()
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: diags, clock: clock)

        do {
            _ = try await service.requestElevation(
                for: TemporaryAdminTestSupport.makeDetail(),
                duration: .five,
                reason: "needs admin",
                ticketReference: "TICKET-1"
            )
            XCTFail("Expected the request to throw.")
        } catch {
            XCTAssertTrue(error.isJamfInvalidPrivilege)
        }
        let hasPermission = await diags.hasCategory(TemporaryAdminDiagnostics.Category.permission)
        XCTAssertTrue(hasPermission)
    }

    func test_duplicateActiveRequestIsBlocked() async throws {
        let scope = MockRequestScopeService()
        let reloader = MockInventoryReloader(details: [])
        let diags = RecordingDiagnostics()
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: diags, clock: clock)
        let detail = TemporaryAdminTestSupport.makeDetail()

        _ = try await service.requestElevation(for: detail, duration: .five, reason: "r", ticketReference: "T")

        do {
            _ = try await service.requestElevation(for: detail, duration: .five, reason: "r", ticketReference: "T")
            XCTFail("Expected a duplicate request to be blocked.")
        } catch let error as TemporaryAdminElevationError {
            XCTAssertEqual(error, .duplicateActiveRequest)
        }
    }

    func test_validationFailureThrowsForMobileDevice() async throws {
        let scope = MockRequestScopeService()
        let service = makeService(scope: scope, reloader: MockInventoryReloader(details: []), diagnostics: RecordingDiagnostics(), clock: TestClock(t0))
        do {
            _ = try await service.requestElevation(
                for: TemporaryAdminTestSupport.makeDetail(assetType: .mobileDevice),
                duration: .five, reason: "r", ticketReference: "T"
            )
            XCTFail("Expected validation to reject a mobile device.")
        } catch let error as TemporaryAdminElevationError {
            guard case .validationFailed = error else { return XCTFail("Expected validationFailed.") }
        }
        let adds = await scope.addCalls()
        XCTAssertTrue(adds.isEmpty, "No scope write should happen for an invalid request.")
    }

    // MARK: - Poll

    func test_pollElevatedConfirmsAndCleansUpScope() async throws {
        let scope = MockRequestScopeService()
        let elevatedDetail = TemporaryAdminTestSupport.makeDetail(
            extensionAttributes: TemporaryAdminTestSupport.statusEAs(
                status: "elevated",
                user: "consoleuser",
                expiresISO: TemporaryAdminTestSupport.iso(t0.addingTimeInterval(900)),
                lastChangeISO: TemporaryAdminTestSupport.iso(t0)
            )
        )
        let reloader = MockInventoryReloader(details: [elevatedDetail])
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: RecordingDiagnostics(), clock: clock)

        let request = try await service.requestElevation(for: TemporaryAdminTestSupport.makeDetail(), duration: .fifteen, reason: "r", ticketReference: "T")
        let result = try await service.pollElevation(for: TemporaryAdminTestSupport.makeDetail(), request: request)

        XCTAssertTrue(result.isComplete)
        XCTAssertFalse(result.cleanupFailed)
        if case .elevated = result.snapshot.state {} else { XCTFail("Expected elevated, got \(result.snapshot.state)") }
        let removes = await scope.removeCalls()
        XCTAssertEqual(removes.first?.scopeId, "515", "Cleanup should remove the Mac from the 15m scope.")
    }

    func test_pollDemotedConfirms() async throws {
        let scope = MockRequestScopeService()
        let demotedDetail = TemporaryAdminTestSupport.makeDetail(
            extensionAttributes: TemporaryAdminTestSupport.statusEAs(
                status: "demoted",
                user: "consoleuser",
                lastChangeISO: TemporaryAdminTestSupport.iso(t0)
            )
        )
        let reloader = MockInventoryReloader(details: [demotedDetail])
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: RecordingDiagnostics(), clock: clock)

        let request = try await service.requestElevation(for: TemporaryAdminTestSupport.makeDetail(), duration: .five, reason: "r", ticketReference: "T")
        let result = try await service.pollElevation(for: TemporaryAdminTestSupport.makeDetail(), request: request)

        XCTAssertTrue(result.isComplete)
        if case .demoted = result.snapshot.state {} else { XCTFail("Expected demoted.") }
    }

    func test_timeoutCleansUpAndReportsTimedOut() async throws {
        let scope = MockRequestScopeService()
        // The Mac never reports elevated (status not_requested).
        let pendingDetail = TemporaryAdminTestSupport.makeDetail(
            extensionAttributes: TemporaryAdminTestSupport.statusEAs(status: "not_requested", user: nil)
        )
        let reloader = MockInventoryReloader(details: [pendingDetail])
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: RecordingDiagnostics(), clock: clock)

        let request = try await service.requestElevation(for: TemporaryAdminTestSupport.makeDetail(), duration: .five, reason: "r", ticketReference: "T")
        clock.now = t0.addingTimeInterval(26 * 60) // past the 25-minute timeout

        let result = try await service.pollElevation(for: TemporaryAdminTestSupport.makeDetail(), request: request)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.didTimeout)
        if case .timedOut = result.snapshot.state {} else { XCTFail("Expected timedOut, got \(result.snapshot.state)") }
        let removes = await scope.removeCalls()
        XCTAssertEqual(removes.first?.scopeId, "501")
    }

    func test_cleanupFailureProducesCleanupWarning() async throws {
        let scope = MockRequestScopeService(removeError: JamfFrameworkError.serverError(statusCode: 500, message: "boom"))
        let elevatedDetail = TemporaryAdminTestSupport.makeDetail(
            extensionAttributes: TemporaryAdminTestSupport.statusEAs(
                status: "elevated",
                user: "consoleuser",
                lastChangeISO: TemporaryAdminTestSupport.iso(t0)
            )
        )
        let reloader = MockInventoryReloader(details: [elevatedDetail])
        let clock = TestClock(t0)
        let service = makeService(scope: scope, reloader: reloader, diagnostics: RecordingDiagnostics(), clock: clock)

        let request = try await service.requestElevation(for: TemporaryAdminTestSupport.makeDetail(), duration: .fifteen, reason: "r", ticketReference: "T")
        let result = try await service.pollElevation(for: TemporaryAdminTestSupport.makeDetail(), request: request)

        XCTAssertTrue(result.cleanupFailed)
        if case .cleanupWarning = result.snapshot.state {} else { XCTFail("Expected cleanupWarning, got \(result.snapshot.state)") }
    }

    // MARK: - Demote-now

    func test_demoteNowRemovesDurationScopesThenAddsDemoteScope() async throws {
        let scope = MockRequestScopeService()
        let service = makeService(scope: scope, reloader: MockInventoryReloader(details: []), diagnostics: RecordingDiagnostics(), clock: TestClock(t0))

        _ = try await service.requestDemotionNow(for: TemporaryAdminTestSupport.makeDetail(), reason: "end now", ticketReference: nil)

        let calls = await scope.recordedCalls()
        // The demote-now add must come after best-effort removals from the four
        // duration scopes.
        let addCalls = calls.filter { $0.action == "add" }
        XCTAssertEqual(addCalls.count, 1)
        XCTAssertEqual(addCalls.first?.scopeId, "590")
        let removeScopeIds = Set(calls.filter { $0.action == "remove" }.map(\.scopeId))
        XCTAssertTrue(removeScopeIds.isSuperset(of: ["501", "515", "530", "560"]))
        // The add happens last.
        XCTAssertEqual(calls.last?.action, "add")
    }

    // MARK: - Configuration gating

    func test_disabledConfigurationLoadsNotConfiguredSnapshot() async throws {
        let service = TemporaryAdminElevationService(
            configuration: .disabledDefault,
            requestScopeService: MockRequestScopeService(),
            diagnostics: RecordingDiagnostics(),
            inventoryReloader: MockInventoryReloader(details: []),
            dateProvider: { Date() }
        )
        let snap = try await service.loadSnapshot(for: TemporaryAdminTestSupport.makeDetail())
        if case .notConfigured = snap.state {} else { XCTFail("Expected notConfigured, got \(snap.state)") }
    }

    // MARK: - Request-scope adapter (read-modify-write)

    func test_requestScopeAddAppendsWithoutOverwriting() async throws {
        let getResponse = Data(#"{"name":"G","assignments":{"computerIds":["7","8"]}}"#.utf8)
        let performer = MockRequestPerformer(getResponse: getResponse)
        let adapter = JamfComputerRequestScopeService(performer: performer)
        let scope = JamfComputerRequestScope(id: "42", name: "G", kind: "staticComputerGroup")

        try await adapter.addComputer("9", toScope: scope)

        let bodies = await performer.recordedPutBodies()
        XCTAssertEqual(bodies.count, 1, "Exactly one PUT for the merged membership.")
        let written = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any]
        let ids = ((written?["assignments"] as? [String: Any])?["computerIds"] as? [String]) ?? []
        XCTAssertEqual(Set(ids), ["7", "8", "9"], "Existing members preserved, new member added.")
    }

    func test_requestScopeAddIsIdempotentWhenAlreadyMember() async throws {
        let getResponse = Data(#"{"name":"G","assignments":{"computerIds":["9"]}}"#.utf8)
        let performer = MockRequestPerformer(getResponse: getResponse)
        let adapter = JamfComputerRequestScopeService(performer: performer)

        try await adapter.addComputer("9", toScope: JamfComputerRequestScope(id: "42", name: "G", kind: "staticComputerGroup"))

        let bodies = await performer.recordedPutBodies()
        XCTAssertTrue(bodies.isEmpty, "No write needed when the computer is already a member.")
    }

    func test_requestScopeRemoveDropsMember() async throws {
        let getResponse = Data(#"{"name":"G","assignments":{"computerIds":["7","9"]}}"#.utf8)
        let performer = MockRequestPerformer(getResponse: getResponse)
        let adapter = JamfComputerRequestScopeService(performer: performer)

        try await adapter.removeComputer("7", fromScope: JamfComputerRequestScope(id: "42", name: "G", kind: "staticComputerGroup"))

        let bodies = await performer.recordedPutBodies()
        let written = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any]
        let ids = ((written?["assignments"] as? [String: Any])?["computerIds"] as? [String]) ?? []
        XCTAssertEqual(ids, ["9"])
    }

    func test_parseMembershipToleratesNumberIdsAndMissingAssignments() {
        let numberIds = Data(#"{"name":"G","assignments":{"computerIds":[7,8]}}"#.utf8)
        let parsed = JamfComputerRequestScopeService.parseMembership(from: numberIds)
        XCTAssertEqual(parsed.members, ["7", "8"])
        XCTAssertEqual(parsed.name, "G")

        let empty = JamfComputerRequestScopeService.parseMembership(from: Data("{}".utf8))
        XCTAssertTrue(empty.members.isEmpty)
    }
}
