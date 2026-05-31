import SwiftUI

/// Layout heights for action buttons inside frame footers. Mirrors the
/// `SupportTechnicianLayout.controlButtonHeight` used by the main view.
private enum FrameLayout {
    static let actionButtonHeight: CGFloat = 44
    static let gaugeHeight: CGFloat = 22
    static let storageGaugeRowHeight: CGFloat = 80
}

// MARK: - Frame entry point

/// Renders a single category frame for the redesigned detail view. Routes
/// to the per-category specialized body based on the `category` value.
///
/// Hides itself when the category has no content (with two exceptions:
/// `.general`, which always renders identity rows + gauges, and
/// `.applications`, which always shows the Application Manager entry).
struct SupportCategoryFrameView: View {
    let category: SupportDeviceCategory
    let detail: SupportDeviceDetail
    let availableActions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    // Applications-frame state delegated up to the parent — the
    // Application Manager sheet lives there.
    let installedAppsCount: Int
    let onManageApplications: () -> Void

    // Tenant-wide policies for the Policy frame.
    let allPolicies: [SupportPolicy]
    let isLoadingAllPolicies: Bool
    let allPoliciesError: String?
    let onLoadAllPolicies: () -> Void

    /// Per-row password reset target for the User Accounts frame. Tapping
    /// the Reset Password button on any user row routes through this
    /// callback so the parent view can present its typed-confirm sheet
    /// bound to the selected user. The `SupportManagementAction` enum
    /// can't carry per-user context without a refactor, so password
    /// reset lives outside the action dispatch.
    let onResetUserPassword: (SupportLocalUser) -> Void

    var body: some View {
        switch category {
        case .general:
            GeneralFrame(
                detail: detail,
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        case .hardware:
            HardwareFrame(
                detail: detail,
                sections: detail.categorized.sections(for: .hardware),
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        case .storage:
            StorageFrame(
                detail: detail,
                sections: detail.categorized.sections(for: .storage)
            )
        case .os:
            OSFrame(
                detail: detail,
                osInfo: detail.osInfo,
                sections: detail.categorized.sections(for: .os),
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        case .security:
            SecurityFrame(
                detail: detail,
                securityProfile: detail.securityProfile,
                sections: detail.categorized.sections(for: .security),
                diagnostics: detail.diagnostics,
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        case .network:
            NetworkFrame(
                detail: detail,
                networkInfo: detail.networkInfo,
                hardwareSpecs: detail.hardwareSpecs,
                sections: detail.categorized.sections(for: .network),
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        case .extensionAttributes:
            ExtensionAttributesFrame(
                attributes: detail.extensionAttributes,
                fallbackSections: detail.categorized.sections(for: .extensionAttributes)
            )
        case .profiles:
            ProfilesFrame(
                profiles: detail.configurationProfiles,
                fallbackSections: detail.categorized.sections(for: .profiles)
            )
        case .groups:
            GroupFrame(
                groups: detail.deviceGroups,
                fallbackSections: detail.categorized.sections(for: .groups)
            )
        case .policies:
            PolicyFrame(
                policies: allPolicies,
                isLoading: isLoadingAllPolicies,
                errorMessage: allPoliciesError,
                onLoad: onLoadAllPolicies
            )
        case .applications:
            ApplicationsFrame(
                installedAppsCount: installedAppsCount,
                onManageApplications: onManageApplications,
                assetType: detail.summary.assetType,
                installedAppNames: detail.applications
            )
        case .userAccounts:
            UserAccountsFrame(
                detail: detail,
                users: detail.localUsers,
                fallbackSections: detail.categorized.sections(for: .userAccounts),
                actions: footerActions,
                isPerformingAction: isPerformingAction,
                onAction: onAction,
                onResetUserPassword: onResetUserPassword
            )
        case .other:
            // Removed per redesign — `.other` no longer renders.
            EmptyView()
        }
    }

    /// Subset of available actions whose `primaryCategory` matches this frame
    /// (excluding the universal toolbar actions, which live in the toolbar).
    private var footerActions: [SupportManagementAction] {
        availableActions.filter { action in
            action.primaryCategory == category && action.isUniversalToolbarAction == false
        }
    }
}

// MARK: - General Frame (identity + gauges + spec cards)

/// Identifies which hardware-resource card is being shown in the detail
/// sheet so the same sheet view can render the right content.
private enum HardwareDetailKind: String, Identifiable {
    case cpu, gpu, ram, storage, battery, model
    var id: String { rawValue }
}

private struct GeneralFrame: View {
    let detail: SupportDeviceDetail
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    /// Drives the tap-to-expand sheet showing more hardware detail.
    @State private var hardwareDetailKind: HardwareDetailKind?

    var body: some View {
        CategoryFrame(
            category: .general,
            bodyMaxHeight: 560
        ) {
            VStack(alignment: .leading, spacing: 16) {
                identityRows
                resourceRow
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
        .sheet(item: $hardwareDetailKind) { kind in
            HardwareDetailSheet(kind: kind, detail: detail)
        }
    }

    private var identityRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            CategoryFieldRow(label: "Device Name", value: detail.summary.displayName)
            CategoryFieldRow(label: "Device Type", value: detail.summary.assetType.title)
            CategoryFieldRow(label: "Serial Number", value: detail.summary.serialNumber)
            CategoryFieldRow(label: "Inventory ID", value: detail.summary.inventoryID)

            if let username = detail.summary.username, username.isEmpty == false {
                CategoryFieldRow(label: "Assigned User", value: username)
            }
            if let email = detail.summary.email, email.isEmpty == false {
                CategoryFieldRow(label: "User Email", value: email)
            }
            if let model = detail.summary.model, model.isEmpty == false {
                CategoryFieldRow(label: "Model", value: model)
            }
            if let osVersion = detail.summary.osVersion, osVersion.isEmpty == false {
                CategoryFieldRow(label: "Operating System", value: osVersion)
            }
            if let ade = detail.summary.automatedDeviceEnrollment {
                CategoryFieldRow(label: "Automated Enrollment", value: ade ? "Yes" : "No")
            }
            if let prestage = detail.summary.prestageEnrollment, prestage.isEmpty == false {
                CategoryFieldRow(label: "PreStage Enrollment", value: prestage)
            }
            if let lastInventory = detail.summary.lastInventoryUpdate, lastInventory.isEmpty == false {
                CategoryFieldRow(label: "Last Inventory Update", value: lastInventory)
            }
            if let mgmtID = detail.summary.managementID, mgmtID.isEmpty == false {
                CategoryFieldRow(label: "Management ID", value: mgmtID)
            }
            if let clientID = detail.summary.clientManagementID, clientID.isEmpty == false {
                CategoryFieldRow(label: "Client Management ID", value: clientID)
            }
        }
    }

    /// Cards: Model / CPU / GPU / RAM tappable to reveal a sheet with
    /// full hardware detail. Storage and Battery get their own row below
    /// — Storage uses the Metal liquid gauge, Battery uses the SwiftUI
    /// circular ring.
    private var resourceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hardware")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                modelCard
                cpuCard
            }

            HStack(alignment: .top, spacing: 12) {
                gpuCard
                ramCard
            }

            HStack(alignment: .center, spacing: 12) {
                storageGaugePanel
                    .frame(maxWidth: 420)
                batteryCard
            }
        }
    }

    @ViewBuilder
    private var modelCard: some View {
        let primary = detail.hardwareSpecs?.modelName ?? detail.summary.model ?? "Unavailable"
        tappable(.model) {
            HardwareSpecCard(
                iconSystemName: "macbook.gen2",
                label: "Model",
                primaryValue: primary,
                secondaryValue: detail.hardwareSpecs?.modelIdentifier
            )
        }
    }

    @ViewBuilder
    private var cpuCard: some View {
        if let summary = detail.hardwareSpecs?.cpuSummary {
            tappable(.cpu) {
                HardwareSpecCard(
                    iconSystemName: "cpu",
                    label: "CPU",
                    primaryValue: summary,
                    secondaryValue: detail.hardwareSpecs?.chipName ?? detail.hardwareSpecs?.modelIdentifier
                )
            }
        } else {
            HardwareSpecCard.unavailable(iconSystemName: "cpu", label: "CPU")
        }
    }

    @ViewBuilder
    private var gpuCard: some View {
        if let summary = detail.hardwareSpecs?.gpuSummary {
            tappable(.gpu) {
                HardwareSpecCard(
                    iconSystemName: "rectangle.3.group",
                    label: "GPU",
                    primaryValue: summary,
                    secondaryValue: detail.hardwareSpecs?.chipName
                )
            }
        } else {
            HardwareSpecCard.unavailable(iconSystemName: "rectangle.3.group", label: "GPU")
        }
    }

    @ViewBuilder
    private var ramCard: some View {
        if let summary = detail.hardwareSpecs?.ramSummary {
            tappable(.ram) {
                HardwareSpecCard(
                    iconSystemName: "memorychip",
                    label: "RAM",
                    primaryValue: summary,
                    secondaryValue: detail.hardwareSpecs?.memoryDescription ?? "Static spec"
                )
            }
        } else {
            HardwareSpecCard.unavailable(iconSystemName: "memorychip", label: "RAM")
        }
    }

    @ViewBuilder
    private var batteryCard: some View {
        if let battery = detail.hardwareSpecs?.batteryLevel, battery >= 0 {
            Button {
                hardwareDetailKind = .battery
            } label: {
                HardwareBatteryRingView(percent: battery, diameter: 96)
                    .frame(width: 96, height: 96)
            }
            .buttonStyle(.plain)
        } else if let health = detail.hardwareSpecs?.batteryHealth, health.isEmpty == false {
            Button {
                hardwareDetailKind = .battery
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.title2)
                        .foregroundStyle(ForsettiColors.greenPrimary)
                    Text(health)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(width: 96, height: 96)
                .background(ForsettiTheme.groupedSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button))
            }
            .buttonStyle(.plain)
        }
    }

    /// Storage panel — the Metal `HardwareStorageGaugeView` is rendered
    /// OUTSIDE a SwiftUI `Button` label because an MTKView inside a
    /// Button label doesn't drive its render loop reliably (the button
    /// suppresses or steals layout passes). Tapping the surrounding
    /// container fires the detail-sheet via `.onTapGesture` instead.
    @ViewBuilder
    private var storageGaugePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ForsettiColors.bluePrimary)
                    .frame(width: 22)
                Text("Storage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let summary = detail.hardwareSpecs?.storageSummary {
                    Text(summary)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let used = detail.hardwareSpecs?.storageUsedFraction {
                HardwareStorageGaugeView(usedFraction: used, style: .inline)
                    .frame(height: 10)
                    .padding(.vertical, 4)
                storageMetricsRow(usedFraction: used)
            } else {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.20))
                    Text("Storage usage unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
                .frame(height: 18)
            }
        }
        .padding(10)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button))
        .contentShape(Rectangle())
        .onTapGesture {
            hardwareDetailKind = .storage
        }
    }

    @ViewBuilder
    private func storageMetricsRow(usedFraction: Double) -> some View {
        HStack(spacing: 12) {
            if let total = detail.hardwareSpecs?.storageTotalMB {
                storageMetric(value: humanReadable(megabytes: total), caption: "Total")
            }
            if let total = detail.hardwareSpecs?.storageTotalMB,
               let available = detail.hardwareSpecs?.storageAvailableMB
            {
                storageMetric(value: humanReadable(megabytes: max(0, total - available)), caption: "Used")
                storageMetric(value: humanReadable(megabytes: available), caption: "Free")
            }
            storageMetric(value: "\(Int((usedFraction * 100).rounded()))%", caption: "Used")
        }
    }

    private func storageMetric(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    private func humanReadable(megabytes: Int) -> String {
        if megabytes >= 1_048_576 {
            return String(format: "%.2f TB", Double(megabytes) / 1_048_576.0)
        }
        if megabytes >= 1024 {
            return String(format: "%.0f GB", Double(megabytes) / 1024.0)
        }
        return "\(megabytes) MB"
    }

    /// Wraps a card in a button that opens the detail sheet for the given
    /// hardware kind. Keeps the per-card body unchanged.
    @ViewBuilder
    private func tappable<Content: View>(
        _ kind: HardwareDetailKind,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        Button {
            hardwareDetailKind = kind
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }
}

/// Modal sheet shown when a hardware card in the General frame is tapped.
/// Renders all the hardware fields associated with that card kind.
private struct HardwareDetailSheet: View {
    let kind: HardwareDetailKind
    let detail: SupportDeviceDetail

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.0) { row in
                        CategoryFieldRow(label: row.0, value: row.1)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
#if os(macOS)
            .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 460)
#endif
        }
    }

    private var title: String {
        switch kind {
        case .cpu:     return "CPU Detail"
        case .gpu:     return "GPU / Neural Engine Detail"
        case .ram:     return "RAM Detail"
        case .storage: return "Storage Detail"
        case .battery: return "Battery Detail"
        case .model:   return "Model Detail"
        }
    }

    private var rows: [(String, String)] {
        guard let specs = detail.hardwareSpecs else {
            return [("Hardware", "Not reported by Jamf Pro for this device.")]
        }
        switch kind {
        case .cpu:
            return [
                ("Chip", specs.chipName ?? specs.cpuType ?? "Unavailable"),
                ("Cores", specs.coreCount.map { "\($0)" } ?? "Unavailable"),
                ("Clock Speed", specs.cpuSpeedMhz.map { mhz in
                    mhz >= 1000 ? String(format: "%.2f GHz", Double(mhz) / 1000.0) : "\(mhz) MHz"
                } ?? specs.cpuFrequencyDescription ?? "Not reported"),
                ("Model Identifier", specs.modelIdentifier ?? "Unavailable")
            ]
        case .gpu:
            return [
                ("GPU Cores", specs.gpuCoreCount.map { "\($0)" } ?? specs.gpuCoreDescription ?? "Unavailable"),
                ("Neural Engine Cores", specs.neuralCoreCount.map { "\($0)" } ?? "Unavailable"),
                ("Chip", specs.chipName ?? "Unavailable"),
                ("Model Identifier", specs.modelIdentifier ?? "Unavailable")
            ]
        case .ram:
            return [
                ("Total RAM", specs.ramSummary ?? "Unavailable"),
                ("Rated Memory", specs.memoryDescription ?? "Not reported"),
                ("Source", "Derived from Apple Device Model Catalog (iOS / iPadOS) or Jamf hardware report (Mac)."),
                ("Model Identifier", specs.modelIdentifier ?? "Unavailable")
            ]
        case .storage:
            return [
                ("Capacity", specs.storageTotalMB.map { humanReadable(megabytes: $0) } ?? "Unavailable"),
                ("Available", specs.storageAvailableMB.map { humanReadable(megabytes: $0) } ?? "Unavailable"),
                ("Used",
                    specs.storageTotalMB.flatMap { total in
                        specs.storageAvailableMB.map { avail in
                            humanReadable(megabytes: max(0, total - avail))
                        }
                    } ?? "Unavailable"
                ),
                ("Used Percentage", specs.usedSpacePercentage.map { "\($0)%" } ?? "Unavailable")
            ]
        case .battery:
            return [
                ("Level", specs.batteryLevel.map { "\($0)%" } ?? "Unavailable"),
                ("Health", specs.batteryHealth ?? "Unavailable")
            ]
        case .model:
            return [
                ("Model", specs.modelName ?? "Unavailable"),
                ("Model Identifier", specs.modelIdentifier ?? "Unavailable"),
                ("Model Number", specs.modelNumber ?? "Unavailable"),
                ("Chip", specs.chipName ?? specs.cpuType ?? "Unavailable")
            ]
        }
    }

    private func humanReadable(megabytes: Int) -> String {
        if megabytes >= 1_048_576 {
            return String(format: "%.2f TB", Double(megabytes) / 1_048_576.0)
        }
        if megabytes >= 1024 {
            return String(format: "%.0f GB", Double(megabytes) / 1024.0)
        }
        return "\(megabytes) MB"
    }
}

// MARK: - Hardware Frame

private struct HardwareFrame: View {
    let detail: SupportDeviceDetail
    let sections: [SupportDetailSection]
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    var body: some View {
        CategoryFrame(category: .hardware) {
            VStack(alignment: .leading, spacing: 12) {
                // Canonical hardware fields surfaced from the typed
                // extractor so they're always present when Jamf reports them,
                // independent of the generic section flattener.
                if let specs = detail.hardwareSpecs {
                    VStack(alignment: .leading, spacing: 6) {
                        if let model = specs.modelName {
                            CategoryFieldRow(label: "Model", value: model)
                        }
                        if let modelID = specs.modelIdentifier {
                            CategoryFieldRow(label: "Model Identifier", value: modelID)
                        }
                        if let modelNumber = specs.modelNumber {
                            CategoryFieldRow(label: "Model Number", value: modelNumber)
                        }
                        if let cpu = specs.cpuSummary {
                            CategoryFieldRow(label: "CPU / Chip", value: cpu)
                        }
                        if let gpu = specs.gpuSummary {
                            CategoryFieldRow(label: "GPU / Neural", value: gpu)
                        }
                        if let ram = specs.ramSummary {
                            CategoryFieldRow(label: "RAM", value: ram)
                        }
                        if let storage = specs.storageSummary {
                            CategoryFieldRow(label: "Storage", value: storage)
                        }
                        if let battery = specs.batterySummary {
                            CategoryFieldRow(label: "Battery", value: battery)
                        }
                        if let bluetoothMac = specs.bluetoothMacAddress {
                            CategoryFieldRow(label: "Bluetooth MAC", value: bluetoothMac)
                        }
                        if let wifiMac = specs.wifiMacAddress {
                            CategoryFieldRow(label: "Wi-Fi MAC", value: wifiMac)
                        }
                    }
                }

                sectionsBlock(sections)
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
    }
}

// MARK: - Storage Frame

private struct StorageFrame: View {
    let detail: SupportDeviceDetail
    let sections: [SupportDetailSection]

    var body: some View {
        CategoryFrame(category: .storage) {
            VStack(alignment: .leading, spacing: 12) {
                if let used = detail.hardwareSpecs?.storageUsedFraction {
                    VStack(alignment: .leading, spacing: 6) {
                        if let summary = detail.hardwareSpecs?.storageSummary {
                            Text(summary)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        HardwareStorageGaugeView(usedFraction: used, style: .detail)
                            .frame(height: 36)
                    }
                } else if let total = detail.hardwareSpecs?.storageSummary {
                    CategoryFieldRow(label: "Capacity", value: total)
                }

                sectionsBlock(sections)
            }
        }
    }
}

// MARK: - OS Frame

private struct OSFrame: View {
    let detail: SupportDeviceDetail
    let osInfo: SupportOSInfo?
    let sections: [SupportDetailSection]
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    var body: some View {
        CategoryFrame(category: .os) {
            VStack(alignment: .leading, spacing: 12) {
                if let osInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        if let osName = osInfo.osName {
                            CategoryFieldRow(label: "OS", value: osName)
                        }
                        if let version = osInfo.version {
                            CategoryFieldRow(label: "Version", value: version)
                        }
                        if let build = osInfo.build {
                            CategoryFieldRow(label: "Build", value: build)
                        }
                        if let supplemental = osInfo.supplementalBuildVersion {
                            CategoryFieldRow(label: "Supplemental Build", value: supplemental)
                        }
                        if let rsr = osInfo.rapidSecurityResponseVersion {
                            CategoryFieldRow(label: "Rapid Security Response", value: rsr)
                        }
                    }
                }
                sectionsBlock(sections)
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
    }
}

// MARK: - Security Frame

private struct SecurityFrame: View {
    let detail: SupportDeviceDetail
    let securityProfile: SupportSecurityProfile?
    let sections: [SupportDetailSection]
    let diagnostics: [SupportDiagnosticItem]
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    @State private var selectedSecuritySection: DetailDrillInSection?

    /// Keyword list used to decide which diagnostic items are
    /// security-relevant. Diagnostics are emitted as a flat list of
    /// `(title, value, severity)` records — anything matching one of
    /// these substrings (case-insensitive) belongs in the Security frame
    /// instead of (or in addition to) the top-level Diagnostics card.
    private static let securityKeywords: [String] = [
        "filevault",
        "encrypt",
        "supervis",
        "activation",
        "passcode",
        "recovery",
        "lost mode",
        "jailbroken",
        "gatekeeper",
        "sip",
        "xprotect",
        "firewall",
        "compliant"
    ]

    private var securityDiagnostics: [SupportDiagnosticItem] {
        diagnostics.filter { item in
            let title = item.title.lowercased()
            return Self.securityKeywords.contains { title.contains($0) }
        }
    }

    private func severityColor(_ severity: SupportDiagnosticSeverity) -> Color {
        switch severity {
        case .info: return ForsettiColors.greenPrimary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        CategoryFrame(category: .security, bodyMaxHeight: 520) {
            VStack(alignment: .leading, spacing: 14) {
                securitySectionHeader("Protection overview")
                statusCardsGrid

                securitySectionHeader("Security records")
                if securityDetailCards.isEmpty {
                    EmptyContent(message: "Jamf Pro didn't return additional security records for this device.")
                } else {
                    DetailDrillInCardGrid(
                        sections: securityDetailCards,
                        selectedSection: $selectedSecuritySection
                    )
                }
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
        .sheet(item: $selectedSecuritySection) { section in
            DetailDrillInSheet(section: section)
        }
    }

    private var securityDetailCards: [DetailDrillInSection] {
        var cards: [DetailDrillInSection] = []

        if let profile = securityProfile {
            var bootItems: [SupportDetailItem] = []
            appendItem(&bootItems, key: "FileVault", value: profile.fileVaultStatus.map(readableSecurityValue))
            appendItem(&bootItems, key: "Recovery Key", value: profile.recoveryKeyStatus.map(readableSecurityValue))
            appendItem(&bootItems, key: "Secure Boot", value: profile.secureBootLevel.map(readableSecurityValue))
            appendItem(&bootItems, key: "External Boot", value: profile.externalBootLevel.map(readableSecurityValue))
            appendIntItem(&bootItems, key: "Hardware Encryption", value: profile.hardwareEncryptionSupported)
            appendBoolItem(&bootItems, key: "Bootstrap Token Allowed", value: profile.bootstrapTokenAllowed)
            appendBoolItem(&bootItems, key: "Auto Login Disabled", value: profile.autoLoginDisabled)
            appendBoolItem(&bootItems, key: "Remote Desktop Enabled", value: profile.remoteDesktopEnabled)
            appendDrillInCard(
                to: &cards,
                id: "security-boot-recovery",
                title: "Boot & Recovery",
                description: "Startup security, recovery lock, encryption, and escrow status.",
                iconSystemName: "lock.laptopcomputer",
                items: bootItems
            )

            var protectionItems: [SupportDetailItem] = []
            appendItem(&protectionItems, key: "Gatekeeper", value: profile.gatekeeperStatus.map(readableSecurityValue))
            appendItem(&protectionItems, key: "SIP", value: profile.sipStatus.map(readableSecurityValue))
            appendItem(&protectionItems, key: "XProtect Version", value: profile.xprotectVersion)
            appendBoolItem(&protectionItems, key: "Firewall Enabled", value: profile.firewallEnabled)
            appendBoolItem(&protectionItems, key: "Passcode Present", value: profile.passcodePresent)
            appendBoolItem(&protectionItems, key: "Passcode Compliant", value: profile.passcodeCompliant)
            appendBoolItem(&protectionItems, key: "Passcode Profile Compliant", value: profile.passcodeCompliantWithProfile)
            appendDrillInCard(
                to: &cards,
                id: "security-protection",
                title: "Protection Controls",
                description: "OS protection posture and passcode compliance values.",
                iconSystemName: "shield.lefthalf.filled",
                items: protectionItems
            )

            var attestationItems: [SupportDetailItem] = []
            appendItem(&attestationItems, key: "Attestation", value: profile.attestationStatus.map(readableSecurityValue))
            appendItem(&attestationItems, key: "Last Attestation", value: profile.lastSuccessfulAttestation)
            appendItem(&attestationItems, key: "Bootstrap Token Escrow", value: profile.bootstrapTokenEscrowedStatus.map(readableSecurityValue))
            appendDrillInCard(
                to: &cards,
                id: "security-attestation",
                title: "Attestation",
                description: "Device attestation and bootstrap token escrow details.",
                iconSystemName: "checkmark.seal.fill",
                items: attestationItems
            )
        }

        if securityDiagnostics.isEmpty == false {
            cards.append(
                DetailDrillInSection(
                    id: "security-posture-diagnostics",
                    title: "Posture Diagnostics",
                    description: "\(securityDiagnostics.count) diagnostic signal\(securityDiagnostics.count == 1 ? "" : "s") from inventory parsing.",
                    iconSystemName: "waveform.path.ecg",
                    sections: [
                        SupportDetailSection(
                            title: "Posture Diagnostics",
                            items: securityDiagnostics.map { item in
                                SupportDetailItem(key: item.title, value: item.value)
                            }
                        )
                    ]
                )
            )
        }

        let certificateSections = sections.filter { section in
            containsSecurityTerm(section, terms: ["certificate", "cert"])
        }
        if certificateSections.isEmpty == false {
            cards.append(
                DetailDrillInSection(
                    id: "security-certificates",
                    title: "Certificates",
                    description: "\(certificateSections.reduce(0) { $0 + $1.items.count }) certificate field\(certificateSections.reduce(0) { $0 + $1.items.count } == 1 ? "" : "s") reported by Jamf.",
                    iconSystemName: "checkmark.seal",
                    sections: certificateSections
                )
            )
        }

        let remainingSections = sections.filter { section in
            containsSecurityTerm(section, terms: ["certificate", "cert"]) == false
        }
        cards.append(contentsOf: rawPayloadCards(from: remainingSections, idPrefix: "security-raw"))
        return cards
    }

    /// Two-column grid of `SecurityStatusCard` instances. Each maps a
    /// binary or known-string security property to a coloured dot:
    /// green = enabled / compliant, red = disabled / non-compliant,
    /// yellow = not configured / unknown-but-non-binary, orange =
    /// unknown. Cards with no underlying value are omitted entirely.
    private var statusCardsGrid: some View {
        let entries = makeStatusEntries()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(entries, id: \.title) { entry in
                SecurityStatusCard(entry: entry)
            }
        }
    }

    private func makeStatusEntries() -> [SecurityStatusEntry] {
        guard let profile = securityProfile else { return [] }
        var entries: [SecurityStatusEntry] = []

        func appendBinary(_ title: String, icon: String, value: Bool?, enabledLabel: String = "Enabled", disabledLabel: String = "Disabled") {
            guard let value else { return }
            entries.append(
                SecurityStatusEntry(
                    title: title,
                    icon: icon,
                    state: value ? .enabled : .disabled,
                    valueLabel: value ? enabledLabel : disabledLabel
                )
            )
        }

        func appendEvaluated(_ title: String, icon: String, value: String?, goodValues: [String], badValues: [String] = []) {
            guard let value, value.isEmpty == false else { return }
            let normalized = value.lowercased()
            let state: SecurityStatusState
            if badValues.contains(where: { normalized.contains($0) }) {
                state = .disabled
            } else if goodValues.contains(where: { normalized.contains($0) }) {
                state = .enabled
            } else {
                state = .unknown
            }
            entries.append(
                SecurityStatusEntry(
                    title: title,
                    icon: icon,
                    state: state,
                    valueLabel: readableSecurityValue(value)
                )
            )
        }

        appendBinary("Encrypted", icon: "lock.fill", value: profile.isEncrypted, enabledLabel: "Yes", disabledLabel: "No")
        appendBinary("Data Protected", icon: "lock.doc.fill", value: profile.dataProtected, enabledLabel: "Yes", disabledLabel: "No")
        appendBinary("Firewall", icon: "flame.fill", value: profile.firewallEnabled)
        appendBinary("Supervised", icon: "person.crop.circle.badge.checkmark", value: profile.supervised, enabledLabel: "Yes", disabledLabel: "No")
        appendBinary("Activation Lock", icon: "lock.shield.fill", value: profile.activationLockEnabled)
        appendBinary("Lost Mode", icon: "mappin.and.ellipse", value: profile.lostModeEnabled)
        appendBinary("Passcode Set", icon: "key.fill", value: profile.passcodePresent, enabledLabel: "Yes", disabledLabel: "No")
        appendBinary("Passcode Compliant", icon: "checkmark.shield", value: profile.passcodeCompliant, enabledLabel: "Yes", disabledLabel: "No")
        appendBinary("Passcode Profile", icon: "checkmark.shield.fill", value: profile.passcodeCompliantWithProfile, enabledLabel: "Compliant", disabledLabel: "Not compliant")
        appendBinary("Recovery Lock", icon: "lock.rectangle", value: profile.recoveryLockEnabled)
        appendBinary("Auto Login", icon: "person.crop.circle.badge.xmark", value: profile.autoLoginDisabled, enabledLabel: "Disabled", disabledLabel: "Enabled")
        appendBinary("Block Encryption", icon: "rectangle.compress.vertical", value: profile.blockEncryptionCapable, enabledLabel: "Capable", disabledLabel: "Not capable")
        appendBinary("File Encryption", icon: "doc.fill", value: profile.fileEncryptionCapable, enabledLabel: "Capable", disabledLabel: "Not capable")

        appendEvaluated("Gatekeeper", icon: "gate.left.and.gate.right", value: profile.gatekeeperStatus, goodValues: ["app_store", "identified", "enabled"], badValues: ["disabled"])
        appendEvaluated("SIP", icon: "shield.lefthalf.filled", value: profile.sipStatus, goodValues: ["enabled"], badValues: ["disabled"])
        appendEvaluated("Recovery Key", icon: "key.horizontal.fill", value: profile.recoveryKeyStatus, goodValues: ["valid"], badValues: ["invalid"])
        appendEvaluated("Secure Boot", icon: "lock.laptopcomputer", value: profile.secureBootLevel, goodValues: ["full"], badValues: ["none", "reduced"])
        appendEvaluated("Attestation", icon: "checkmark.seal.fill", value: profile.attestationStatus, goodValues: ["success"], badValues: ["failed", "failure"])
        appendEvaluated("Bootstrap Token", icon: "key.radiowaves.forward.fill", value: profile.bootstrapTokenEscrowedStatus, goodValues: ["escrowed"], badValues: ["not_escrowed", "not escrowed"])

        if let remoteDesktop = profile.remoteDesktopEnabled {
            entries.append(
                SecurityStatusEntry(
                    title: "Remote Desktop",
                    icon: "display.and.arrow.down",
                    state: remoteDesktop ? .notConfigured : .enabled,
                    valueLabel: remoteDesktop ? "Enabled" : "Disabled"
                )
            )
        }

        // Jailbroken: invert the colour so jailbroken=true reads red.
        if let jailbroken = profile.jailbroken {
            entries.append(
                SecurityStatusEntry(
                    title: "Jailbroken",
                    icon: "exclamationmark.shield",
                    state: jailbroken ? .disabled : .enabled,
                    valueLabel: jailbroken ? "Detected" : "Not detected"
                )
            )
        }

        return entries
    }

    private func securitySectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func readableSecurityValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { word in
                let text = String(word)
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }
}

/// Visual state for a SecurityStatusCard. Maps to the user-requested
/// colour scheme: green = enabled, red = disabled, yellow = not
/// configured, orange = unknown.
///
/// Note: NOT marked `nonisolated` because `tint` references
/// `ForsettiColors.greenPrimary`, which the project's `-default-isolation MainActor`
/// flag pins to the main actor. The enum stays MainActor-isolated and
/// the card view is constructed from MainActor view-render paths only.
enum SecurityStatusState: Sendable {
    case enabled, disabled, notConfigured, unknown

    var tint: Color {
        switch self {
        case .enabled:       return ForsettiColors.greenPrimary
        case .disabled:      return .red
        case .notConfigured: return .yellow
        case .unknown:       return .orange
        }
    }
}

struct SecurityStatusEntry: Hashable, Sendable {
    let title: String
    let icon: String
    let state: SecurityStatusState
    let valueLabel: String
}

private struct SecurityStatusCard: View {
    let entry: SecurityStatusEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(entry.state.tint)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle().stroke(entry.state.tint.opacity(0.3), lineWidth: 4)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: entry.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(entry.valueLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button))
        .overlay(
            RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button)
                .stroke(entry.state.tint.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Network Frame

private struct NetworkFrame: View {
    let detail: SupportDeviceDetail
    let networkInfo: SupportNetworkInfo?
    let hardwareSpecs: SupportHardwareSpecs?
    let sections: [SupportDetailSection]
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    var body: some View {
        CategoryFrame(category: .network) {
            VStack(alignment: .leading, spacing: 12) {
                if let net = networkInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        networkSectionHeader("Status")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            if let connection = net.connectionActive {
                                NetworkCapabilityRow(title: "Connection", systemImage: "network", isEnabled: connection, enabledText: "Connected", disabledText: "No IP reported")
                            }
                            if let wifi = net.wifiEnabled {
                                NetworkCapabilityRow(title: "Wi-Fi", systemImage: "wifi", isEnabled: wifi, enabledText: "On", disabledText: "Off")
                            }
                            NetworkCapabilityRow(
                                title: "Wi-Fi Network",
                                systemImage: "wifi",
                                isEnabled: net.ssid?.isEmpty == false,
                                enabledText: net.ssid ?? "",
                                disabledText: "Not reported"
                            )
                            if let bluetooth = net.bluetoothEnabled {
                                NetworkCapabilityRow(title: "Bluetooth", systemImage: "dot.radiowaves.left.and.right", isEnabled: bluetooth, enabledText: "On", disabledText: "Off")
                            }
                        }

                        networkSectionHeader("Addresses")
                        if let ip = net.ipAddress {
                            CategoryFieldRow(label: "IP Address", value: ip)
                        }
                        if let lastIp = net.lastReportedIp, lastIp != net.ipAddress {
                            CategoryFieldRow(label: "Last Reported IP", value: lastIp)
                        }
                        if let ipv4 = net.lastReportedIpV4 {
                            CategoryFieldRow(label: "Last IPv4", value: ipv4)
                        }
                        if let ipv6 = net.lastReportedIpV6 {
                            CategoryFieldRow(label: "Last IPv6", value: ipv6)
                        }
                        if let host = net.hostname {
                            CategoryFieldRow(label: "Hostname", value: host)
                        }

                        networkSectionHeader("Network hardware")
                        if let wifi = net.wifiMacAddress ?? hardwareSpecs?.wifiMacAddress {
                            CategoryFieldRow(label: "Wi-Fi MAC", value: wifi)
                        }
                        if let adapter = net.networkAdapterType {
                            CategoryFieldRow(label: "Primary Adapter", value: readableNetworkValue(adapter))
                        }
                        if let alternateMac = net.alternateMacAddress {
                            CategoryFieldRow(label: "Secondary MAC", value: alternateMac)
                        }
                        if let alternateAdapter = net.alternateNetworkAdapterType {
                            CategoryFieldRow(label: "Secondary Adapter", value: readableNetworkValue(alternateAdapter))
                        }
                        if let speed = net.nicSpeed {
                            CategoryFieldRow(label: "NIC Speed", value: speed)
                        }
                        if let bt = net.bluetoothMacAddress ?? hardwareSpecs?.bluetoothMacAddress {
                            CategoryFieldRow(label: "Bluetooth MAC", value: bt)
                        }
                        if let ble = net.bleCapable {
                            NetworkCapabilityRow(title: "Bluetooth LE", systemImage: "dot.radiowaves.left.and.right", isEnabled: ble, enabledText: "Capable", disabledText: "Not capable")
                        }

                        networkSectionHeader("Cellular")
                        if let carrier = net.cellularCarrier {
                            CategoryFieldRow(label: "Carrier", value: carrier)
                        }
                        if let technology = net.cellularTechnology {
                            CategoryFieldRow(label: "Cellular Technology", value: readableNetworkValue(technology))
                        }
                        if let phone = net.phoneNumber {
                            CategoryFieldRow(label: "Phone Number", value: phone)
                        }
                        if let imei = net.imei {
                            CategoryFieldRow(label: "IMEI", value: imei)
                        }
                        if let imei2 = net.imei2 {
                            CategoryFieldRow(label: "IMEI 2", value: imei2)
                        }
                        if let meid = net.meid {
                            CategoryFieldRow(label: "MEID", value: meid)
                        }
                        if let iccid = net.iccid {
                            CategoryFieldRow(label: "ICCID", value: iccid)
                        }
                        if let eid = net.eid {
                            CategoryFieldRow(label: "EID", value: eid)
                        }
                        if net.dataRoamingEnabled != nil || net.voiceRoamingEnabled != nil || net.roaming != nil || net.personalHotspotEnabled != nil {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                if let dataRoaming = net.dataRoamingEnabled {
                                    NetworkCapabilityRow(title: "Data Roaming", systemImage: "antenna.radiowaves.left.and.right", isEnabled: dataRoaming, enabledText: "Enabled", disabledText: "Disabled")
                                }
                                if let voiceRoaming = net.voiceRoamingEnabled {
                                    NetworkCapabilityRow(title: "Voice Roaming", systemImage: "phone.connection", isEnabled: voiceRoaming, enabledText: "Enabled", disabledText: "Disabled")
                                }
                                if let roaming = net.roaming {
                                    NetworkCapabilityRow(title: "Currently Roaming", systemImage: "network", isEnabled: roaming, enabledText: "Yes", disabledText: "No")
                                }
                                if let hotspot = net.personalHotspotEnabled {
                                    NetworkCapabilityRow(title: "Personal Hotspot", systemImage: "personalhotspot", isEnabled: hotspot, enabledText: "Enabled", disabledText: "Disabled")
                                }
                            }
                        }
                    }
                }
                sectionsBlock(sections)
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
    }

    private func networkSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func readableNetworkValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { word in
                let text = String(word)
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct NetworkCapabilityRow: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let enabledText: String
    let disabledText: String

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(isEnabled ? ForsettiColors.greenPrimary : Color.gray.opacity(0.65))
                .frame(width: 10, height: 10)
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(isEnabled ? enabledText : disabledText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Profiles Frame and Other Frame share the generic layout

private struct GenericSectionsFrame: View {
    let category: SupportDeviceCategory
    let sections: [SupportDetailSection]

    var body: some View {
        CategoryFrame(
            category: category,
            subtitle: sections.isEmpty ? "No data reported by Jamf Pro." : nil
        ) {
            if sections.isEmpty {
                EmptyView()
            } else {
                sectionsBlock(sections)
            }
        }
    }
}

// MARK: - Extension Attributes Frame

private struct ExtensionAttributesFrame: View {
    let attributes: [SupportExtensionAttribute]
    let fallbackSections: [SupportDetailSection]
    @State private var sortByName = true

    var body: some View {
        CategoryFrame(
            category: .extensionAttributes,
            subtitle: subtitleText,
            bodyMaxHeight: 420
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if curatedAttributes.isEmpty == false {
                    typedAttributesBlock
                } else {
                    EmptyContent(message: "Jamf inventory didn't return any extension attributes for this device.")
                }
            }
        }
    }

    private var subtitleText: String? {
        "10 technician fields"
    }

    @ViewBuilder
    private var typedAttributesBlock: some View {
        Group {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(curatedAttributes) { attribute in
                        CuratedExtensionAttributeRow(attribute: attribute)
                    }
                }
        }
    }

    private var curatedAttributes: [CuratedExtensionAttribute] {
        Self.curatedDefinitions.map { definition in
            let match = attributes.first { attribute in
                definition.aliases.contains(normalize(attribute.name))
            }
            return CuratedExtensionAttribute(
                name: definition.name,
                value: match?.value ?? "",
                isBinary: definition.isBinary,
                isReported: match != nil
            )
        }
    }

    private nonisolated static let curatedDefinitions: [(name: String, aliases: Set<String>, isBinary: Bool)] = [
        ("Automated GL Code", ["automatedglcode"], false),
        ("Billing GL & Store No", ["billingglstoreno", "billingglstorenumber"], false),
        ("Device Testing Group", ["devicetestinggroup", "testinggroup"], false),
        ("Entra Account Active", ["entraaccountactive"], true),
        ("Jamf Setup Role", ["jamfsetuprole"], false),
        ("Legal Hold", ["legalhold"], true),
        ("Lost or Stolen Comment or Ticket Ref", ["lostorstolencommentorticketref"], false),
        ("Reported Stolen", ["reportedstolen"], true),
        ("Shared Device No", ["shareddeviceno", "shareddevicenumber"], false),
        ("Store No", ["storeno", "storenumber", "store_no"], false)
    ]

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

private struct CuratedExtensionAttribute: Identifiable, Hashable {
    let name: String
    let value: String
    let isBinary: Bool
    let isReported: Bool

    var id: String { name }
}

private struct CuratedExtensionAttributeRow: View {
    let attribute: CuratedExtensionAttribute

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if attribute.isBinary {
                Circle()
                    .fill(binaryColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
            } else {
                Image(systemName: attribute.isReported ? "tag.fill" : "tag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(attribute.isReported ? ForsettiColors.bluePrimary : .secondary)
                    .frame(width: 16)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(attribute.name)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(displayValue)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(attribute.isReported ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var displayValue: String {
        let trimmed = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return attribute.isReported ? "—" : "Not reported"
        }
        if attribute.isBinary, let value = binaryValue {
            return value ? "Yes" : "No"
        }
        return trimmed
    }

    private var binaryValue: Bool? {
        let normalized = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "1", "active", "enabled"].contains(normalized) { return true }
        if ["false", "no", "0", "inactive", "disabled"].contains(normalized) { return false }
        return nil
    }

    private var binaryColor: Color {
        guard attribute.isReported else { return .secondary }
        guard let binaryValue else { return .orange }
        return binaryValue ? ForsettiColors.greenPrimary : Color.gray.opacity(0.65)
    }
}

// MARK: - Applications Frame

private struct ApplicationsFrame: View {
    let installedAppsCount: Int
    let onManageApplications: () -> Void
    let assetType: SupportAssetType
    let installedAppNames: [String]

    @State private var showMobileUnsupportedAlert = false

    var body: some View {
        CategoryFrame(
            category: .applications,
            subtitle: subtitleText,
            bodyMaxHeight: 460
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Manage Applications button is shown for BOTH device types.
                // On iOS / iPadOS the button shows a "not yet supported"
                // alert instead of opening the Application Manager sheet —
                // the user explicitly asked for this behaviour.
                Button {
                    if assetType == .mobileDevice {
                        showMobileUnsupportedAlert = true
                    } else {
                        onManageApplications()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Label("Manage Applications", systemImage: "app.badge")
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("\(visibleAppCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ForsettiTheme.groupedSurface)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.forsettiSecondary)
                .frame(maxWidth: .infinity, minHeight: FrameLayout.actionButtonHeight)

                // Installed apps list — populated for any device with
                // application inventory data. Mobile devices report apps
                // via `ios.applications` (extracted into
                // `detail.applications`). Macs surface the same list
                // through the Application Manager sheet, but the list
                // itself is useful as a read-only preview here too.
                if installedAppNames.isEmpty == false {
                    Divider().opacity(0.3)
                    Text("Installed (\(installedAppNames.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(installedAppNames.prefix(60), id: \.self) { name in
                            Text(name)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        if installedAppNames.count > 60 {
                            Text("Showing first 60 of \(installedAppNames.count).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if assetType == .computer {
                    Text("Opens the Application Manager to view installed apps, request installs by exact app name, or queue uninstalls. Group-assigned policies reinstall removed apps on the next check-in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Application Manager not yet supported", isPresented: $showMobileUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install / Uninstall against iOS or iPadOS devices is not yet supported in this release. Use the Jamf Pro web console for now. The installed-apps list above is read-only.")
        }
    }

    private var subtitleText: String? {
        if installedAppNames.isEmpty == false {
            return "\(installedAppNames.count) installed"
        }
        return nil
    }

    private var visibleAppCount: Int {
        installedAppNames.isEmpty ? installedAppsCount : installedAppNames.count
    }
}

// MARK: - User Accounts Frame

private struct UserAccountsFrame: View {
    let detail: SupportDeviceDetail
    let users: [SupportLocalUser]
    let fallbackSections: [SupportDetailSection]
    let actions: [SupportManagementAction]
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void
    let onResetUserPassword: (SupportLocalUser) -> Void

    @State private var isOtherAccountsPresented = false

    /// Whether the per-row View Password button on the jssmanage row
    /// should render — the action is gated by whether
    /// `.viewJamfManagementAccountPassword` is in the available action
    /// list for the selected device. Macs return it; mobile devices
    /// don't.
    private var canViewJamfManagementPassword: Bool {
        actions.contains(.viewJamfManagementAccountPassword)
    }

    /// Sign-in admin accounts (UID >= 500 typically, non-system).
    private var adminAccounts: [SupportLocalUser] {
        users.filter { $0.isAdmin == true && isSystemAccount($0) == false && isJSSManage($0) == false }
    }

    /// Standard sign-in user accounts.
    private var standardAccounts: [SupportLocalUser] {
        users.filter { $0.isAdmin != true && isSystemAccount($0) == false && isJSSManage($0) == false }
    }

    /// Jamf's management account, surfaced separately so it's obvious.
    private var jssManageAccount: SupportLocalUser? {
        users.first(where: isJSSManage)
    }

    /// Hidden / system accounts (everything else) — collapsed under a
    /// disclosure so the main list isn't polluted with `_root`, `daemon`,
    /// `_atsserver`, etc.
    private var otherAccounts: [SupportLocalUser] {
        users.filter { user in
            isSystemAccount(user)
                && isJSSManage(user) == false
        }
    }

    private func isJSSManage(_ user: SupportLocalUser) -> Bool {
        let name = user.username.lowercased()
        return name == "jssmanage" || name == "jamfmanage" || name == "jamfadmin"
    }

    /// Heuristic: usernames starting with `_` or with UID < 500 are
    /// system accounts. Falls back to `userAccountType` containing
    /// "system" / "service".
    private func isSystemAccount(_ user: SupportLocalUser) -> Bool {
        if user.username.hasPrefix("_") { return true }
        if let uidString = user.uid, let uid = Int(uidString), uid < 500, uid >= 0 {
            return true
        }
        if let home = user.homeDirectory?.lowercased(), home.isEmpty == false {
            let isInteractiveHome = home.hasPrefix("/users/")
            if isInteractiveHome == false {
                return true
            }
        }
        if let type = user.userAccountType?.lowercased(),
           type.contains("system") || type.contains("service") || type.contains("hidden") || type.contains("daemon")
        {
            return true
        }
        return false
    }

    var body: some View {
        CategoryFrame(
            category: .userAccounts,
            subtitle: subtitleText,
            bodyMaxHeight: 520
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let jss = jssManageAccount {
                    sectionHeader("Jamf Management")
                    userRow(jss, isJSSManage: true)
                }

                if adminAccounts.isEmpty == false {
                    sectionHeader("Admin Accounts")
                    ForEach(adminAccounts) { user in
                        userRow(user, isJSSManage: false)
                    }
                }

                if standardAccounts.isEmpty == false {
                    sectionHeader("User Accounts")
                    ForEach(standardAccounts) { user in
                        userRow(user, isJSSManage: false)
                    }
                }

                if otherAccounts.isEmpty == false {
                    Button {
                        isOtherAccountsPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.sequence.fill")
                            Text("Other accounts (\(otherAccounts.count))")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(ForsettiTheme.groupedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                if users.isEmpty {
                    if fallbackSections.isEmpty {
                        EmptyContent(
                            message: "No local user accounts reported. Macs need the LOCAL_USER_ACCOUNTS inventory section; mobile devices don't have this concept."
                        )
                    } else {
                        sectionsBlock(fallbackSections)
                    }
                }
            }
        } footer: {
            FrameActionFooter(
                actions: actions,
                detail: detail,
                isPerformingAction: isPerformingAction,
                onAction: onAction
            )
        }
        .sheet(isPresented: $isOtherAccountsPresented) {
            OtherAccountsSheet(groups: groupedOtherAccounts())
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func userRow(_ user: SupportLocalUser, isJSSManage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isJSSManage
                    ? "gearshape.circle.fill"
                    : (user.isAdmin == true ? "star.circle.fill" : "person.circle"))
                    .foregroundStyle(isJSSManage
                        ? ForsettiColors.bluePrimary
                        : (user.isAdmin == true ? ForsettiColors.bluePrimary : .secondary))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.fullName ?? user.username)
                        .font(.subheadline.weight(.semibold))
                    Text(user.username)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isJSSManage {
                    chip("jssmanage", color: ForsettiColors.bluePrimary)
                } else if user.isAdmin == true {
                    chip("Admin", color: ForsettiColors.bluePrimary)
                }
                if let fileVault = user.fileVault2Enabled {
                    chip(
                        fileVault ? "FileVault On" : "FileVault Off",
                        color: fileVault ? ForsettiColors.greenPrimary : Color.gray.opacity(0.75)
                    )
                }
            }
            HStack(spacing: 12) {
                if let uid = user.uid {
                    Text("UID \(uid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let type = user.userAccountType, type.isEmpty == false {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let home = user.homeDirectory, home.isEmpty == false {
                    Text(home)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Per-row password actions.
            //
            // jssmanage row gets two buttons — View Password (existing
            // `.viewJamfManagementAccountPassword` action, which already
            // targets the jssmanage account specifically) and Reset
            // Password (per-row rotate via the new view-model flow).
            //
            // Admin and standard user rows get just Reset Password.
            // The reset path goes through Jamf's LAPS per-account
            // rotate endpoint, so it only succeeds for accounts that
            // are registered with Jamf's LAPS feature; non-LAPS
            // accounts surface the failure popup with the 404
            // remediation suggestion.
            HStack(spacing: 8) {
                if isJSSManage, canViewJamfManagementPassword {
                    Button {
                        onAction(.viewJamfManagementAccountPassword)
                    } label: {
                        Label("View Password", systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPerformingAction)
                    .help("Retrieve the current LAPS-stored password for the jssmanage account. The password is shown once.")
                }

                Button {
                    onResetUserPassword(user)
                } label: {
                    Label("Reset Password", systemImage: "key.fill")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPerformingAction)
                .help("Rotate the \(user.username) account password via Jamf LAPS. The new password is shown once after rotation. Only works for accounts registered with Jamf's LAPS feature.")

                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            Divider().opacity(0.3)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
            .foregroundStyle(color)
    }

    /// Group other accounts by inferred type for the disclosure body.
    private func groupedOtherAccounts() -> [(String, [SupportLocalUser])] {
        let buckets = Dictionary(grouping: otherAccounts) { user -> String in
            if let type = user.userAccountType, type.isEmpty == false {
                return type
            }
            if user.username.hasPrefix("_") {
                return "Service accounts"
            }
            return "Hidden accounts"
        }
        return buckets
            .map { ($0.key, $0.value.sorted { $0.username < $1.username }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private var subtitleText: String? {
        if users.isEmpty == false {
            let admins = adminAccounts.count
            let standards = standardAccounts.count
            let parts = [
                "\(users.count) account\(users.count == 1 ? "" : "s")",
                admins > 0 ? "\(admins) admin" : nil,
                standards > 0 ? "\(standards) user" : nil,
                jssManageAccount != nil ? "jssmanage" : nil
            ].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}

private struct OtherAccountsSheet: View {
    let groups: [(String, [SupportLocalUser])]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.0) { group in
                        Text(group.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(group.1) { user in
                            otherUserRow(user)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Other Accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 560)
#endif
    }

    private func otherUserRow(_ user: SupportLocalUser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.fullName ?? user.username)
                        .font(.subheadline.weight(.semibold))
                    Text(user.username)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let fileVault = user.fileVault2Enabled {
                    statusChip(fileVault ? "FileVault On" : "FileVault Off", isOn: fileVault)
                }
            }
            HStack(spacing: 12) {
                if let uid = user.uid {
                    Text("UID \(uid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let type = user.userAccountType, type.isEmpty == false {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let home = user.homeDirectory, home.isEmpty == false {
                    Text(home)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Divider().opacity(0.3)
        }
    }

    private func statusChip(_ text: String, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isOn ? ForsettiColors.greenPrimary : Color.gray.opacity(0.75)).opacity(0.16))
        .foregroundStyle(isOn ? ForsettiColors.greenPrimary : Color.gray.opacity(0.75))
        .clipShape(Capsule())
    }
}

// MARK: - Profiles Frame (typed)

private struct ProfilesFrame: View {
    let profiles: [SupportDeviceProfile]
    let fallbackSections: [SupportDetailSection]

    @State private var selectedProfileSection: DetailDrillInSection?

    var body: some View {
        CategoryFrame(
            category: .profiles,
            subtitle: subtitleText,
            bodyMaxHeight: 460
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let cards = profileCards
                if cards.isEmpty {
                    EmptyContent(
                        message: "Jamf Pro didn't return CONFIGURATION_PROFILES or USER_PROFILES sections for this device. The API role may lack profile-read privileges."
                    )
                } else {
                    DetailDrillInCardGrid(
                        sections: cards,
                        selectedSection: $selectedProfileSection
                    )
                }
            }
        }
        .sheet(item: $selectedProfileSection) { section in
            DetailDrillInSheet(section: section)
        }
    }

    private var subtitleText: String? {
        if profiles.isEmpty == false {
            return "\(profiles.count) profile\(profiles.count == 1 ? "" : "s")"
        }
        if fallbackSections.isEmpty == false {
            return "Raw payload available"
        }
        return nil
    }

    private var profileCards: [DetailDrillInSection] {
        var cards: [DetailDrillInSection] = []
        let grouped = Dictionary(grouping: profiles, by: profileCategory)

        for title in grouped.keys.sorted() {
            let categoryProfiles = grouped[title, default: []].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let detailSections = categoryProfiles.map { profile in
                SupportDetailSection(
                    title: profile.name,
                    items: profileDetailItems(profile)
                )
            }
            cards.append(
                DetailDrillInSection(
                    id: "profiles-\(stableID(title))",
                    title: title,
                    description: "\(categoryProfiles.count) profile\(categoryProfiles.count == 1 ? "" : "s") grouped by profile scope or identifier.",
                    iconSystemName: profileIcon(for: title),
                    sections: detailSections
                )
            )
        }

        cards.append(contentsOf: rawPayloadCards(from: fallbackSections, idPrefix: "profiles-raw"))
        return cards
    }

    private func profileCategory(_ profile: SupportDeviceProfile) -> String {
        let scope = profile.scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identifier = profile.identifier?.lowercased() ?? ""
        if scope.lowercased().contains("user") {
            return "User Profiles"
        }
        if scope.isEmpty == false {
            return "\(scope) Profiles"
        }
        if identifier.hasPrefix("com.apple") {
            return "Apple Profiles"
        }
        return "Configuration Profiles"
    }

    private func profileIcon(for title: String) -> String {
        let normalized = title.lowercased()
        if normalized.contains("user") { return "person.crop.circle.badge.checkmark" }
        if normalized.contains("apple") { return "apple.logo" }
        return "rectangle.stack.badge.person.crop"
    }

    private func profileDetailItems(_ profile: SupportDeviceProfile) -> [SupportDetailItem] {
        var items: [SupportDetailItem] = []
        appendItem(&items, key: "Profile ID", value: profile.profileID.isEmpty ? nil : profile.profileID)
        appendItem(&items, key: "Identifier", value: profile.identifier)
        appendItem(&items, key: "Scope", value: profile.scope)
        return items.isEmpty ? [SupportDetailItem(key: "Profile", value: profile.name)] : items
    }
}

// MARK: - Group Frame

private struct GroupFrame: View {
    let groups: [SupportDeviceGroup]
    let fallbackSections: [SupportDetailSection]

    @State private var selectedGroupSection: DetailDrillInSection?

    var body: some View {
        CategoryFrame(
            category: .groups,
            subtitle: subtitleText,
            bodyMaxHeight: 460
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let cards = groupCards
                if cards.isEmpty {
                    EmptyContent(
                        message: "Jamf Pro didn't return GROUP_MEMBERSHIPS / MOBILE_DEVICE_GROUPS for this device. The API role may lack the read privilege."
                    )
                } else {
                    DetailDrillInCardGrid(
                        sections: cards,
                        selectedSection: $selectedGroupSection
                    )
                }
            }
        }
        .sheet(item: $selectedGroupSection) { section in
            DetailDrillInSheet(section: section)
        }
    }

    private var subtitleText: String? {
        if groups.isEmpty == false {
            return "\(groups.count) group\(groups.count == 1 ? "" : "s")"
        }
        if fallbackSections.isEmpty == false {
            return "Raw payload available"
        }
        return nil
    }

    private var groupCards: [DetailDrillInSection] {
        var cards: [DetailDrillInSection] = []

        let smartGroups = groups.filter { $0.isSmart == true }
        let staticGroups = groups.filter { $0.isSmart == false }
        let unclassifiedGroups = groups.filter { $0.isSmart == nil }

        appendGroupCard(
            to: &cards,
            id: "groups-smart",
            title: "Smart Groups",
            description: "Dynamic group memberships calculated by Jamf.",
            iconSystemName: "bolt.fill",
            groups: smartGroups
        )
        appendGroupCard(
            to: &cards,
            id: "groups-static",
            title: "Static Groups",
            description: "Manual group memberships assigned in Jamf.",
            iconSystemName: "circle.dotted",
            groups: staticGroups
        )
        appendGroupCard(
            to: &cards,
            id: "groups-unclassified",
            title: "Unclassified Groups",
            description: "Groups where Jamf did not report smart/static type.",
            iconSystemName: "questionmark.folder",
            groups: unclassifiedGroups
        )

        cards.append(contentsOf: rawPayloadCards(from: fallbackSections, idPrefix: "groups-raw"))
        return cards
    }

    private func appendGroupCard(
        to cards: inout [DetailDrillInSection],
        id: String,
        title: String,
        description: String,
        iconSystemName: String,
        groups: [SupportDeviceGroup]
    ) {
        guard groups.isEmpty == false else { return }
        cards.append(
            DetailDrillInSection(
                id: id,
                title: title,
                description: "\(groups.count) group\(groups.count == 1 ? "" : "s"). \(description)",
                iconSystemName: iconSystemName,
                sections: groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { group in
                    SupportDetailSection(
                        title: group.name,
                        items: groupDetailItems(group)
                    )
                }
            )
        )
    }

    private func groupDetailItems(_ group: SupportDeviceGroup) -> [SupportDetailItem] {
        var items: [SupportDetailItem] = []
        appendItem(&items, key: "Group ID", value: group.groupID.isEmpty ? nil : group.groupID)
        if let isSmart = group.isSmart {
            appendBoolItem(&items, key: "Smart Group", value: isSmart)
        } else {
            appendItem(&items, key: "Smart Group", value: "Unknown")
        }
        return items
    }
}

// MARK: - Policy Frame (tenant-wide)

private struct PolicyFrame: View {
    let policies: [SupportPolicy]
    let isLoading: Bool
    let errorMessage: String?
    let onLoad: () -> Void

    @State private var hasAutoLoaded = false
    @State private var filterText = ""
    @State private var selectedPolicySection: DetailDrillInSection?

    var body: some View {
        CategoryFrame(
            category: .policies,
            subtitle: policies.isEmpty ? "Loaded lazily on first view." : "\(policies.count) policies in tenant",
            bodyMaxHeight: 420
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage, errorMessage.isEmpty == false {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter policies", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        onLoad()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh policy list")
                    .disabled(isLoading)
                }

                if isLoading && policies.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading all tenant policies…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if policies.isEmpty {
                    EmptyContent(
                        message: "No policies loaded yet. Tap the refresh icon to fetch /JSSResource/policies."
                    )
                } else if matchingPolicies.isEmpty {
                    EmptyContent(message: "No policies match the current filter.")
                } else {
                    DetailDrillInCardGrid(
                        sections: policyCards,
                        selectedSection: $selectedPolicySection
                    )
                }
            }
        }
        .onAppear {
            if hasAutoLoaded == false {
                hasAutoLoaded = true
                onLoad()
            }
        }
        .sheet(item: $selectedPolicySection) { section in
            DetailDrillInSheet(section: section)
        }
    }

    private var matchingPolicies: [SupportPolicy] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return policies }
        return policies.filter { policy in
            policy.name.lowercased().contains(trimmed)
                || policy.policyID.lowercased().contains(trimmed)
                || (policy.category?.lowercased().contains(trimmed) ?? false)
                || (policy.frequency?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var policyCards: [DetailDrillInSection] {
        let grouped = Dictionary(grouping: matchingPolicies) { policy in
            let category = policy.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return category.isEmpty ? "Uncategorized" : category
        }
        return grouped.keys.sorted().map { category in
            let policies = grouped[category, default: []].sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let enabledCount = policies.filter { $0.enabled == true }.count
            let disabledCount = policies.filter { $0.enabled == false }.count
            return DetailDrillInSection(
                id: "policies-\(stableID(category))",
                title: category,
                description: "\(policies.count) polic\(policies.count == 1 ? "y" : "ies"), \(enabledCount) enabled, \(disabledCount) disabled.",
                iconSystemName: "checklist",
                sections: policies.map { policy in
                    SupportDetailSection(
                        title: policy.name,
                        items: policyDetailItems(policy)
                    )
                }
            )
        }
    }

    private func policyDetailItems(_ policy: SupportPolicy) -> [SupportDetailItem] {
        var items: [SupportDetailItem] = []
        appendItem(&items, key: "Policy ID", value: policy.policyID)
        appendItem(&items, key: "Category", value: policy.category)
        if let enabled = policy.enabled {
            appendBoolItem(&items, key: "Enabled", value: enabled)
        } else {
            appendItem(&items, key: "Enabled", value: "Unknown")
        }
        appendItem(&items, key: "Frequency", value: policy.frequency)
        return items
    }
}

// MARK: - Diagnostics Frame (not category-based; helper used by main view)

struct DiagnosticsFrame: View {
    let diagnostics: [SupportDiagnosticItem]

    var body: some View {
        CategoryFrame(
            category: .general,
            titleOverride: "Diagnostics",
            subtitle: diagnostics.isEmpty ? "No diagnostics emitted." : nil,
            bodyMaxHeight: 220
        ) {
            if diagnostics.isEmpty {
                EmptyContent(message: "No diagnostic checks emitted for this device.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnostics) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.severity.iconSystemName)
                                .foregroundStyle(color(for: item.severity))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.body.weight(.semibold))
                                Text(item.value).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func color(for severity: SupportDiagnosticSeverity) -> Color {
        switch severity {
        case .info: return ForsettiColors.greenPrimary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Command History Frame

/// Shows the device's recent MDM command history: pending, completed,
/// failed, NotNow buckets at the top; the chronological list below.
///
/// Sourced from `GET /api/v2/mdm/commands?filter=clientManagementId==<uuid>`
/// with a Classic-history fallback for tenants whose API role can't read
/// the modern endpoint.
struct CommandHistoryFrame: View {
    let history: SupportMDMCommandHistory
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        CategoryFrame(
            category: .other,
            titleOverride: "Command History",
            subtitle: subtitleText,
            bodyMaxHeight: 380
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage, errorMessage.isEmpty == false {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                bucketRow

                if history.records.isEmpty {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading command history…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        EmptyContent(
                            message: "Jamf Pro hasn't reported any MDM commands for this device, or the API role lacks \"View MDM command information in Jamf Pro API\"."
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(history.records.prefix(40)) { record in
                            commandRow(record: record)
                            Divider().opacity(0.3)
                        }
                        if history.records.count > 40 {
                            Text("Showing the most recent 40 of \(history.records.count) records.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.forsettiSecondary)
                    .disabled(isLoading)
                }
            }
        }
    }

    private var subtitleText: String? {
        guard history.records.isEmpty == false else {
            return nil
        }
        let elapsed = Int(Date().timeIntervalSince(history.fetchedAt))
        let stamp = elapsed < 60
            ? "\(elapsed)s ago"
            : "\(elapsed / 60)m ago"
        return "\(history.records.count) record\(history.records.count == 1 ? "" : "s") · refreshed \(stamp) · \(history.source == .modern ? "v2 endpoint" : "Classic API")"
    }

    private var bucketRow: some View {
        HStack(spacing: 10) {
            bucketChip(label: "Pending", count: history.count(in: .pending), color: ForsettiColors.bluePrimary)
            bucketChip(label: "Completed", count: history.count(in: .completed), color: ForsettiColors.greenPrimary)
            bucketChip(label: "Failed", count: history.count(in: .failed), color: .red)
            bucketChip(label: "NotNow", count: history.count(in: .notNow), color: .orange)
            Spacer(minLength: 0)
        }
    }

    private func bucketChip(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func commandRow(record: SupportMDMCommandRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: record.bucket))
                .foregroundStyle(color(for: record.bucket))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.commandType)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    Text(record.status)
                        .font(.caption2)
                        .foregroundStyle(color(for: record.bucket))
                    if let sent = record.dateSent {
                        Text(sent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let completed = record.dateCompleted, completed != record.dateSent {
                        Text("→ \(completed)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if record.errorReasons.isEmpty == false {
                    Text(record.errorReasons.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func iconName(for bucket: SupportMDMCommandRecord.Bucket) -> String {
        switch bucket {
        case .pending: return "clock"
        case .completed: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .notNow: return "pause.circle"
        case .other: return "questionmark.diamond"
        }
    }

    private func color(for bucket: SupportMDMCommandRecord.Bucket) -> Color {
        switch bucket {
        case .pending: return ForsettiColors.bluePrimary
        case .completed: return ForsettiColors.greenPrimary
        case .failed: return .red
        case .notNow: return .orange
        case .other: return .secondary
        }
    }
}

// MARK: - Raw Payload Frame

struct RawPayloadFrame: View {
    let rawJSON: String
    @State private var isExpanded = false

    var body: some View {
        CategoryFrame(
            category: .other,
            titleOverride: "Raw Payload",
            subtitle: "Full Jamf response — for troubleshooting only.",
            bodyMaxHeight: 360
        ) {
            DisclosureGroup("Show JSON", isExpanded: $isExpanded) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(rawJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

// MARK: - Shared helpers

private struct DetailDrillInSection: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let iconSystemName: String
    let sections: [SupportDetailSection]

    var itemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }
}

private struct DetailDrillInCardGrid: View {
    let sections: [DetailDrillInSection]
    @Binding var selectedSection: DetailDrillInSection?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                DetailDrillInCard(section: section) {
                    selectedSection = section
                }
            }
        }
    }
}

private struct DetailDrillInCard: View {
    let section: DetailDrillInSection
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.iconSystemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ForsettiColors.bluePrimary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(section.itemCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ForsettiColors.bluePrimary.opacity(0.14))
                            .foregroundStyle(ForsettiColors.bluePrimary)
                            .clipShape(Capsule())
                    }

                    Text(section.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(ForsettiTheme.groupedSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button))
            .overlay(
                RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button)
                    .stroke(ForsettiTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DetailDrillInSheet: View {
    let section: DetailDrillInSection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.title3.weight(.semibold))
                    Text(section.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(section.sections.enumerated()), id: \.offset) { _, detailSection in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(detailSection.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(detailSection.items) { item in
                                CategoryFieldRow(label: formatLabel(item.key), value: item.value)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ForsettiTheme.groupedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button))
                        .overlay(
                            RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button)
                                .stroke(ForsettiTheme.border, lineWidth: 1)
                        )
                    }

                    if section.sections.isEmpty {
                        EmptyContent(message: "No records were reported for this category.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
    }
}

private func appendItem(_ items: inout [SupportDetailItem], key: String, value: String?) {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
        return
    }
    items.append(SupportDetailItem(key: key, value: value))
}

private func appendBoolItem(_ items: inout [SupportDetailItem], key: String, value: Bool?) {
    guard let value else { return }
    items.append(SupportDetailItem(key: key, value: value ? "Yes" : "No"))
}

private func appendIntItem(_ items: inout [SupportDetailItem], key: String, value: Int?) {
    guard let value else { return }
    items.append(SupportDetailItem(key: key, value: "\(value)"))
}

private func appendDrillInCard(
    to cards: inout [DetailDrillInSection],
    id: String,
    title: String,
    description: String,
    iconSystemName: String,
    items: [SupportDetailItem]
) {
    guard items.isEmpty == false else { return }
    cards.append(
        DetailDrillInSection(
            id: id,
            title: title,
            description: description,
            iconSystemName: iconSystemName,
            sections: [SupportDetailSection(title: title, items: items)]
        )
    )
}

private func rawPayloadCards(from sections: [SupportDetailSection], idPrefix: String) -> [DetailDrillInSection] {
    sections.enumerated().map { index, section in
        DetailDrillInSection(
            id: "\(idPrefix)-\(index)-\(stableID(section.title))",
            title: section.title,
            description: "\(section.items.count) raw Jamf field\(section.items.count == 1 ? "" : "s") kept for tenant-specific data.",
            iconSystemName: detailIcon(for: section.title),
            sections: [section]
        )
    }
}

private func containsSecurityTerm(_ section: SupportDetailSection, terms: [String]) -> Bool {
    let haystack = ([section.title] + section.items.flatMap { [$0.key, $0.value] })
        .joined(separator: " ")
        .lowercased()
    return terms.contains { haystack.contains($0) }
}

private func detailIcon(for title: String) -> String {
    let normalized = title.lowercased()
    if normalized.contains("certificate") || normalized.contains("cert") {
        return "checkmark.seal"
    }
    if normalized.contains("profile") {
        return "rectangle.stack.badge.person.crop"
    }
    if normalized.contains("group") {
        return "person.3.fill"
    }
    if normalized.contains("policy") {
        return "checklist"
    }
    if normalized.contains("security") {
        return "shield"
    }
    return "doc.text"
}

private func stableID(_ value: String) -> String {
    let normalized = value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return normalized.isEmpty ? "section" : normalized
}

@ViewBuilder
private func sectionsBlock(_ sections: [SupportDetailSection]) -> some View {
    // No empty-state message when sections is empty — frames with typed
    // extractors already render their typed content above this call, and
    // the "Jamf inventory didn't report..." placeholder was just noise
    // when those typed fields were populated.
    if sections.isEmpty == false {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(section.items) { item in
                    CategoryFieldRow(label: formatLabel(item.key), value: item.value)
                }
                Divider().opacity(0.3)
            }
        }
    }
}

private func formatLabel(_ key: String) -> String {
    let acronyms: Set<String> = ["api", "cpu", "id", "imei", "ip", "laps", "mac", "mdm", "os", "pin", "ram", "udid", "url", "uuid"]
    let camelSplit = key.replacingOccurrences(
        of: "([a-z0-9])([A-Z])",
        with: "$1 $2",
        options: .regularExpression
    )
    let normalized = camelSplit
        .replacingOccurrences(of: "[_\\-.]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let words = normalized.split(whereSeparator: { $0.isWhitespace })
    guard words.isEmpty == false else { return key }
    return words.map { token in
        let lower = String(token).lowercased()
        if acronyms.contains(lower) {
            return lower.uppercased()
        }
        if lower.allSatisfy(\.isNumber) {
            return lower
        }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }.joined(separator: " ")
}

private struct EmptyContent: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FrameActionFooter: View {
    let actions: [SupportManagementAction]
    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let onAction: (SupportManagementAction) -> Void

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                Divider()
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        actionButton(for: action)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ForsettiTheme.groupedSurface)
        }
    }

    @ViewBuilder
    private func actionButton(for action: SupportManagementAction) -> some View {
        let availability = action.availability(for: detail)
        let label = HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(action.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(isPerformingAction ? "Running" : availability.helpText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(availability.isAvailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if action == .eraseDevice {
            Button { onAction(action) } label: { label }
                .buttonStyle(.forsettiDanger)
                .frame(maxWidth: .infinity, minHeight: FrameLayout.actionButtonHeight)
                .disabled(isPerformingAction || availability.isAvailable == false)
                .help("\(action.subtitle)\n\(availability.helpText)")
        } else {
            Button { onAction(action) } label: { label }
                .buttonStyle(.forsettiSecondary)
                .frame(maxWidth: .infinity, minHeight: FrameLayout.actionButtonHeight)
                .disabled(isPerformingAction || availability.isAvailable == false)
                .help("\(action.subtitle)\n\(availability.helpText)")
        }
    }
}

//endofline
