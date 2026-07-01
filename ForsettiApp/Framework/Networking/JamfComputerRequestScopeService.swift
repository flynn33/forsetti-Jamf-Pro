import Foundation

/// Abstraction over the single `JamfAPIGateway` request primitive this service
/// needs. Declared so the request-scope adapter can be unit-tested with a mock
/// performer instead of a live gateway; `JamfAPIGateway` (an actor) conforms
/// directly with its existing method.
protocol JamfRequestPerforming: Sendable {
    func request(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> Data
}

extension JamfAPIGateway: JamfRequestPerforming {}

/// Changes a managed computer's membership in a dedicated Jamf request scope.
///
/// This is the only Jamf write the Temporary Admin Elevation feature performs:
/// it adds or removes a single computer from a pre-created static computer group
/// so a pre-created policy runs (or stops running) at the Mac's next check-in.
/// It never creates groups, policies, or scripts.
protocol JamfComputerRequestScopeServicing: Sendable {
    func addComputer(_ computerId: String, toScope scope: JamfComputerRequestScope) async throws
    func removeComputer(_ computerId: String, fromScope scope: JamfComputerRequestScope) async throws
}

/// Gateway-backed implementation of `JamfComputerRequestScopeServicing`.
///
/// The exact endpoint for updating static computer group membership is kept
/// behind this adapter so that endpoint deprecations never leak into the
/// Support Technician view logic. The currently documented compatibility
/// endpoint is `PUT /api/v2/computer-groups/static-groups/{id}`, which replaces
/// a static group's `assignments`. Because a blind replace could wipe existing
/// members, every mutation is **read-modify-write**: the current membership is
/// loaded first, the single computer is added or removed, and only the computed
/// set is written back. A failed read throws before any write, so membership is
/// never overwritten from an unknown baseline, and an empty set is only ever
/// written as the explicit result of removing the last member.
///
/// Note for tenant operators: verify this endpoint in your tenant's API
/// explorer. If your tenant exposes a different request-scope endpoint, this is
/// the single place to adapt it — the feature code above depends only on the
/// `JamfComputerRequestScopeServicing` protocol.
struct JamfComputerRequestScopeService: JamfComputerRequestScopeServicing {
    private let performer: JamfRequestPerforming

    init(performer: JamfRequestPerforming) {
        self.performer = performer
    }

    func addComputer(_ computerId: String, toScope scope: JamfComputerRequestScope) async throws {
        let trimmedComputerId = computerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedComputerId.isEmpty == false else {
            throw JamfFrameworkError.invalidRequest(message: "A computer inventory ID is required to update a request scope.")
        }
        try requireConfigured(scope)

        let current = try await currentMembership(of: scope)
        guard current.members.contains(trimmedComputerId) == false else {
            return // Already in scope — idempotent, no write needed.
        }

        var updated = current.members
        updated.insert(trimmedComputerId)
        // `add` always yields a non-empty set, so this can never accidentally
        // clear the group.
        try await writeMembership(updated, name: current.name ?? scope.name, scope: scope)
    }

    func removeComputer(_ computerId: String, fromScope scope: JamfComputerRequestScope) async throws {
        let trimmedComputerId = computerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedComputerId.isEmpty == false else {
            throw JamfFrameworkError.invalidRequest(message: "A computer inventory ID is required to update a request scope.")
        }
        try requireConfigured(scope)

        let current = try await currentMembership(of: scope)
        guard current.members.contains(trimmedComputerId) else {
            return // Not in scope — nothing to remove.
        }

        var updated = current.members
        updated.remove(trimmedComputerId)
        // Writing an empty set here is the explicit, correct result of removing
        // the last member of a dedicated request group — and it is derived from
        // a successful read, never from an unknown baseline.
        try await writeMembership(updated, name: current.name ?? scope.name, scope: scope)
    }

    // MARK: - Endpoint

    private func path(for scope: JamfComputerRequestScope) -> String {
        "api/v2/computer-groups/static-groups/\(scope.id)"
    }

    private func requireConfigured(_ scope: JamfComputerRequestScope) throws {
        guard scope.isConfigured else {
            throw JamfFrameworkError.invalidRequest(
                message: "Request scope \"\(scope.name)\" has no configured Jamf object ID."
            )
        }
    }

    struct Membership: Equatable {
        let name: String?
        let members: Set<String>
    }

    private func currentMembership(of scope: JamfComputerRequestScope) async throws -> Membership {
        let data = try await performer.request(
            path: path(for: scope),
            method: .get,
            queryItems: [],
            body: nil,
            additionalHeaders: [:]
        )
        return Self.parseMembership(from: data)
    }

    private func writeMembership(_ members: Set<String>, name: String, scope: JamfComputerRequestScope) async throws {
        let body = StaticGroupAssignmentsBody(
            name: name,
            assignments: .init(computerIds: members.sorted())
        )
        let data = try JSONEncoder().encode(body)
        _ = try await performer.request(
            path: path(for: scope),
            method: .put,
            queryItems: [],
            body: data,
            additionalHeaders: ["Content-Type": "application/json"]
        )
    }

    // MARK: - Wire shapes

    private struct StaticGroupAssignmentsBody: Encodable {
        let name: String
        let assignments: Assignments

        struct Assignments: Encodable {
            let computerIds: [String]
        }
    }

    /// Tolerantly extracts the static group name and current computer-ID
    /// membership from a v2 static-group response. Handles the documented
    /// `{ assignments: { computerIds: [...] } }` shape plus a couple of
    /// defensive fallbacks, and accepts IDs as strings or numbers.
    static func parseMembership(from data: Data) -> Membership {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return Membership(name: nil, members: [])
        }

        let name = dictionary["name"] as? String

        var rawIds: [Any] = []
        if let assignments = dictionary["assignments"] as? [String: Any],
           let ids = assignments["computerIds"] as? [Any] {
            rawIds = ids
        } else if let assignments = dictionary["assignments"] as? [Any] {
            rawIds = assignments
        } else if let ids = dictionary["computerIds"] as? [Any] {
            rawIds = ids
        }

        var members: Set<String> = []
        for element in rawIds {
            if let string = element as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { members.insert(trimmed) }
            } else if let number = element as? NSNumber {
                members.insert(number.stringValue)
            } else if let dict = element as? [String: Any] {
                // Some shapes nest the id, e.g. `{ "id": "123" }`.
                if let idString = dict["id"] as? String {
                    members.insert(idString)
                } else if let idNumber = dict["id"] as? NSNumber {
                    members.insert(idNumber.stringValue)
                }
            }
        }

        return Membership(name: name, members: members)
    }
}
