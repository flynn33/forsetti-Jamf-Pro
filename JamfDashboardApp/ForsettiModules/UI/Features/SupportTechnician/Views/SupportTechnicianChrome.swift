import Foundation
import SwiftUI

struct SupportTechnicianSidebarHeader: View {
    let status: ForsettiSemanticStatus
    let resultCount: Int
    let scopeTitle: String
    let selectedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.42), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Support Technician")
                        .font(DashboardTheme.Typography.sectionTitle)
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(1)
                    Text("Search, inspect, and queue Jamf device actions")
                        .font(.caption)
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                ForsettiStatusPill(status: status)
            }

            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForsettiFilterChip(title: "Scope", value: scopeTitle, systemImage: "scope")
                ForsettiFilterChip(title: "Results", value: "\(resultCount)", systemImage: "list.bullet.rectangle")
            }

            if let selectedName, selectedName.isEmpty == false {
                Text(selectedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Selected device: \(selectedName)")
            }
        }
        .forsettiGlassPanel(padding: .standard, isActive: status != .ready, statusTint: status.color)
    }
}

struct SupportTechnicianInlineBanner: View {
    let text: String
    let status: ForsettiSemanticStatus
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(status.color)
                .frame(width: 22)

            Text(text)
                .font(.footnote)
                .foregroundStyle(DashboardColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .forsettiGlassPanel(padding: .dense, statusTint: status.color)
    }
}

struct SupportTechnicianDeviceHero: View {
    let detail: SupportDeviceDetail
    let availableActionCount: Int
    let commandLifecycle: CommandLifecyclePhase
    let commandHistoryCount: Int
    let isLoadingDetail: Bool
    let isPerformingAction: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 176), spacing: DashboardTheme.Spacing.md, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
                Image(systemName: detail.summary.assetType.iconSystemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.42), lineWidth: 1))

                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
                    Text(detail.summary.displayName)
                        .font(DashboardTheme.Typography.screenTitle)
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text("Serial \(detail.summary.serialNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: DashboardTheme.Spacing.sm) {
                    ForsettiStatusPill(status: commandLifecycle.heroStatus)
                    ForsettiFilterChip(title: detail.summary.assetType.title, systemImage: detail.summary.assetType.iconSystemName)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                SupportHeroMetric(
                    title: "Model",
                    value: displayValue(detail.summary.model),
                    subtitle: displayValue(detail.summary.osVersion, fallback: "OS not reported"),
                    systemImage: "cpu",
                    status: .configured
                )

                SupportHeroMetric(
                    title: "Inventory",
                    value: detail.summary.inventoryID,
                    subtitle: "Jamf record ID",
                    systemImage: "number.square",
                    status: .trusted
                )

                SupportHeroMetric(
                    title: "Actions",
                    value: "\(availableActionCount)",
                    subtitle: isPerformingAction ? "Command running" : "Available now",
                    systemImage: "bolt.shield",
                    status: isPerformingAction ? .sending : .ready
                )

                SupportHeroMetric(
                    title: "History",
                    value: "\(commandHistoryCount)",
                    subtitle: isLoadingDetail ? "Refreshing detail" : "Recent commands",
                    systemImage: "clock.arrow.circlepath",
                    status: isLoadingDetail ? .validating : .healthy
                )
            }

            ForsettiCommandStreamBar(
                state: commandLifecycle.commandStreamState,
                message: commandLifecycle.heroMessage,
                progress: commandLifecycle.progress,
                trailingText: commandLifecycle.heroTrailingText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayValue(_ value: String?, fallback: String = "Not reported") -> String {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return fallback
        }
        return value
    }
}

private struct SupportHeroMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let status: ForsettiSemanticStatus

    var body: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.small, style: .continuous).fill(status.color.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(DashboardTheme.Typography.caption)
                    .foregroundStyle(DashboardColors.textTertiary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(DashboardColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(DashboardTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous).fill(DashboardColors.backgroundPanelGlass.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous).stroke(status.color.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private extension CommandLifecyclePhase {
    var commandStreamState: ForsettiCommandStreamState {
        switch self {
        case .idle:
            return .idle
        case .sending:
            return .sending
        case .queued:
            return .waiting
        case .verifying:
            return .validating
        case .succeeded:
            return .completed
        case .failed:
            return .failed
        case .timedOut:
            return .blocked
        }
    }

    var heroStatus: ForsettiSemanticStatus {
        commandStreamState.status
    }

    var heroMessage: String {
        switch self {
        case .idle:
            return "Ready for management actions"
        case let .sending(action, _):
            return "Sending \(action.title)"
        case let .queued(action, _):
            return "\(action.title) queued"
        case let .verifying(action, _, _):
            return "Verifying \(action.title)"
        case let .succeeded(action, _):
            return "\(action.title) completed"
        case let .failed(action, _):
            return "\(action.title) failed"
        case let .timedOut(action):
            return "\(action.title) timed out"
        }
    }

    var heroTrailingText: String? {
        switch self {
        case let .verifying(_, _, attempt):
            return "Attempt \(attempt)"
        case .idle:
            return nil
        default:
            return action?.title
        }
    }
}
