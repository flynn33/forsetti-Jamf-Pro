import SwiftUI

// "End of Line"

/// Compact security & management indicator grid for `ComputerDetailView`.
///
/// Surfaces the protective-posture fields Jamf reports for a Mac (FileVault, SIP,
/// Gatekeeper, firewall, Activation Lock, supervision, remote management, …) as a
/// two-column grid of small badges. Every badge carries a human-readable label
/// (booleans → Yes/No, statuses → title-cased), so status is never communicated by
/// color alone — the tint is a supplementary cue layered on top of the text, and is
/// always derived from the raw value so it can't disagree with the label. The whole
/// view self-hides when none of the fields are present on the record, so it costs
/// nothing for tenants that don't report them.
struct ComputerSecurityIndicatorGrid: View {
    let record: ComputerRecord

    /// When embedded in a `CategoryFrame`, render only the badge grid — the frame
    /// supplies the title and surface, so the internal headline and
    /// `dashboardCardSurface()` are dropped to avoid a duplicate title and a
    /// card-within-a-card.
    var embedded: Bool = false

    /// Supplementary color cue. The badge always carries the literal value too,
    /// satisfying the "no color-only status" accessibility rule.
    private enum Tone {
        case positive, caution, neutral
    }

    /// One configured indicator: which field to read, how to label it, its icon,
    /// and whether an "on" value is the secure posture (so we can tint it).
    private struct Indicator: Identifiable {
        let key: String
        let title: String
        let systemImage: String
        let isProtective: Bool
        var id: String { key }
    }

    /// Ordered most-important-first. Only the entries with a non-empty value on
    /// this record are rendered.
    private static let indicators: [Indicator] = [
        .init(key: "diskEncryption.fileVault2Enabled", title: "FileVault 2", systemImage: "checkmark.shield.fill", isProtective: true),
        .init(key: "security.firewallEnabled", title: "Firewall", systemImage: "shield.lefthalf.filled", isProtective: true),
        .init(key: "security.sipStatus", title: "System Integrity Protection", systemImage: "checkmark.shield", isProtective: true),
        .init(key: "security.gatekeeperStatus", title: "Gatekeeper", systemImage: "hand.raised.fill", isProtective: true),
        .init(key: "security.activationLockEnabled", title: "Activation Lock", systemImage: "person.crop.circle.badge.checkmark", isProtective: true),
        .init(key: "general.supervised", title: "Supervision", systemImage: "checkmark.seal", isProtective: true),
        .init(key: "general.remoteManagement.managed", title: "Remote Management", systemImage: "antenna.radiowaves.left.and.right", isProtective: true),
        .init(key: "security.bootstrapTokenAllowed", title: "Bootstrap Token", systemImage: "key", isProtective: true),
        .init(key: "security.autoLoginDisabled", title: "Auto-login Disabled", systemImage: "key.fill", isProtective: true),
        .init(key: "security.secureBootLevel", title: "Secure Boot", systemImage: "bolt.shield", isProtective: false),
        .init(key: "security.externalBootLevel", title: "External Boot", systemImage: "externaldrive", isProtective: false),
        .init(key: "security.xprotectVersion", title: "XProtect", systemImage: "checkmark.shield", isProtective: false),
        .init(key: "security.remoteDesktopEnabled", title: "Remote Desktop", systemImage: "display", isProtective: false)
    ]

    /// The field keys this grid renders. Exposed so `ComputerDetailView`'s inventory
    /// table can exclude them and avoid surfacing the same field twice.
    static let configuredKeys: Set<String> = Set(indicators.map(\.key))

    /// Whether any configured indicator has a value on this record. Lets
    /// `ComputerDetailView` skip wrapping the grid in an empty Security frame.
    static func hasIndicators(for record: ComputerRecord) -> Bool {
        indicators.contains { record.value(for: $0.key)?.isEmpty == false }
    }

    /// The subset of indicators that actually have a value on this record.
    private var present: [(indicator: Indicator, value: String)] {
        Self.indicators.compactMap { indicator in
            guard let value = record.value(for: indicator.key), value.isEmpty == false else {
                return nil
            }
            return (indicator, value)
        }
    }

    var body: some View {
        if present.isEmpty {
            EmptyView()
        } else if embedded {
            grid
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Security & Management")
                    .font(.headline)

                grid
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardCardSurface()
        }
    }

    /// The two-column badge grid shared by the standalone and embedded layouts.
    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(present, id: \.indicator.id) { entry in
                badge(entry.indicator, value: entry.value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func badge(_ indicator: Indicator, value: String) -> some View {
        let tone = self.tone(for: indicator, value: value)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: indicator.systemImage)
                .font(.body)
                .foregroundStyle(color(for: tone))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(indicator.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.displayValue(value))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color(for: tone).opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(indicator.title): \(Self.displayValue(value))")
    }

    /// Maps a value to a supplementary tone. Only flags a protective field
    /// clearly on (positive) or clearly off (caution); everything else stays
    /// neutral so we never over-claim a posture from an ambiguous string.
    private func tone(for indicator: Indicator, value: String) -> Tone {
        guard indicator.isProtective, let isOn = Self.booleanState(of: value) else {
            return .neutral
        }
        return isOn ? .positive : .caution
    }

    private func color(for tone: Tone) -> Color {
        switch tone {
        case .positive: return Color(red: 0.18, green: 0.72, blue: 0.40)
        case .caution: return Color(red: 0.95, green: 0.78, blue: 0.20)
        case .neutral: return .secondary
        }
    }

    /// Human-readable rendering of a raw status value. Pure booleans collapse to
    /// Yes/No (matching `CategoryFieldRow`); everything else is title-cased by the
    /// shared formatter. Tone is still derived from the raw value elsewhere, so the
    /// color cue and the text can never disagree.
    private static func displayValue(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return "Yes"
        case "false": return "No"
        default: return ComputerFieldValueFormatter.displayString(rawValue)
        }
    }

    /// Best-effort interpretation of Jamf's boolean-ish status strings. Returns
    /// nil when the value isn't clearly on or off (e.g. a version or level string).
    private static func booleanState(of value: String) -> Bool? {
        let lowered = value.lowercased()
        if lowered.contains("not ") || lowered.contains("disabled")
            || lowered.contains("false") || lowered == "off" || lowered == "no"
        {
            return false
        }
        if lowered.contains("enabled") || lowered.contains("true")
            || lowered == "on" || lowered == "yes"
            || lowered.contains("managed") || lowered.contains("supervised")
            || lowered.contains("allowed") || lowered.contains("verified")
            || lowered.contains("active")
        {
            return true
        }
        return nil
    }
}

//endofline
