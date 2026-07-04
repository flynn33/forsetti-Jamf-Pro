import Foundation

/// Deterministically resolves the best native Screen Sharing connection target for a managed Mac.
///
/// One responsibility, pure, and independently testable. The priority (highest first) is:
/// manual override → inventory hostname → last reported IPv4 → current IP → last reported IP →
/// display name when already an FQDN/IP → `displayName.local` when Bonjour-safe → no usable target.
///
/// The serial number is **never** used as a connection target — it identifies the device but
/// cannot host a `vnc://` connection.
nonisolated struct SupportRemoteSupportTargetResolver {

    init() {}

    /// Resolves the connection target for `detail`, honoring a technician `manualOverride` first.
    func resolve(detail: SupportDeviceDetail, manualOverride: String? = nil) -> SupportRemoteSupportTargetResolution {
        let serial = detail.summary.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Manual override — the technician's explicit choice wins.
        if let override = cleaned(manualOverride) {
            if isSerial(override, serial: serial) {
                return .unresolved(reason: "A serial number is not a usable connection target. Enter a hostname or IP address.")
            }
            guard isLaunchableHost(override) else {
                return .unresolved(reason: "“\(override)” isn’t a valid hostname or IP address.")
            }
            return .resolved(SupportRemoteSupportTarget(host: override, source: .manualOverride))
        }

        let net = detail.networkInfo

        // 2. Inventory hostname.
        if let host = cleaned(net?.hostname), isSerial(host, serial: serial) == false, isLaunchableHost(host) {
            return .resolved(SupportRemoteSupportTarget(host: host, source: .inventoryHostname))
        }

        // 3. Last reported IPv4.
        if let ip = cleaned(net?.lastReportedIpV4), isValidIPv4(ip) {
            return .resolved(SupportRemoteSupportTarget(host: ip, source: .lastReportedIPv4))
        }

        // 4. Current inventory IP address.
        if let ip = cleaned(net?.ipAddress), isValidIPAddress(ip) {
            return .resolved(SupportRemoteSupportTarget(host: ip, source: .currentIPAddress))
        }

        // 5. Last reported IP address (v4 or v6).
        if let ip = cleaned(net?.lastReportedIp), isValidIPAddress(ip) {
            return .resolved(SupportRemoteSupportTarget(host: ip, source: .lastReportedIP))
        }

        // 6. Display name only if it is already a valid FQDN or IP (and not the serial).
        let name = detail.summary.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false, isSerial(name, serial: serial) == false {
            if isValidIPAddress(name) || isFQDN(name) {
                return .resolved(SupportRemoteSupportTarget(host: name, source: .displayNameHost))
            }
            // 7. Bonjour `displayName.local`, only when the name is Bonjour-safe.
            if isBonjourSafe(name) {
                return .resolved(SupportRemoteSupportTarget(host: "\(name).local", source: .bonjourLocal))
            }
        }

        // 8. No usable target.
        return .unresolved(reason: "No usable connection target was found in inventory. Edit the target to a hostname or IP address.")
    }

    // MARK: - Validation helpers

    /// Trims `value` and returns `nil` for empty/whitespace-only strings.
    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    /// Whether `candidate` is the device's serial number (case-insensitive).
    private func isSerial(_ candidate: String, serial: String) -> Bool {
        serial.isEmpty == false && candidate.caseInsensitiveCompare(serial) == .orderedSame
    }

    /// A host usable for `vnc://`: a valid IP, or a hostname/FQDN with no whitespace.
    private func isLaunchableHost(_ value: String) -> Bool {
        isValidIPAddress(value) || isHostnameLike(value)
    }

    /// A dotted-quad IPv4 with each octet in 0...255.
    private func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard part.isEmpty == false, part.allSatisfy(\.isNumber), let n = Int(part) else { return false }
            return (0...255).contains(n)
        }
    }

    /// A valid IPv4, or a plausible IPv6 (hex digits and colons, at least one colon).
    private func isValidIPAddress(_ value: String) -> Bool {
        if isValidIPv4(value) { return true }
        guard value.contains(":") else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Host-like: non-empty labels of `[A-Za-z0-9-]` joined by dots, no whitespace.
    private func isHostnameLike(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.isEmpty == false else { return false }
        let labelChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return labels.allSatisfy { label in
            label.isEmpty == false && label.unicodeScalars.allSatisfy { labelChars.contains($0) }
        }
    }

    /// A multi-label hostname (contains a dot) that is host-like and not a bare IPv4.
    private func isFQDN(_ value: String) -> Bool {
        value.contains(".") && isHostnameLike(value) && isValidIPv4(value) == false
    }

    /// Bonjour-safe single label (host-like, no dots) so `\(name).local` is valid.
    private func isBonjourSafe(_ value: String) -> Bool {
        value.contains(".") == false && isHostnameLike(value)
    }
}

//endofline
