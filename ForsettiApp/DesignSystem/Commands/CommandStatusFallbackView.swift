import SwiftUI

/// SwiftUI command-path renderer used by `CommandStatusIndicatorView`.
/// It keeps the command animation stable without the previous live Metal
/// surface, while still giving the technician a clear visual of the command
/// travelling from the app to Jamf Pro and then to the device.
struct CommandStatusFallbackView: View {
    let phase: CommandLifecyclePhase

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                let size = geometry.size
                let t = timeline.date.timeIntervalSinceReferenceDate
                let nodes = nodePositions(in: size)

                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.20),
                                    ForsettiTheme.groupedSurface.opacity(0.92),
                                    accentColor.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    commandTrack(from: nodes.app, via: nodes.jamf, to: nodes.device, time: t)

                    if phase.isInProgress {
                        signalPacket(from: nodes.app, to: nodes.jamf, time: t, delay: 0.0)
                        signalPacket(from: nodes.jamf, to: nodes.device, time: t, delay: 0.32)
                        signalPacket(from: nodes.app, to: nodes.jamf, time: t, delay: 0.64)
                    }

                    if phase.isTerminal {
                        terminalHalo(at: nodes.device, time: t)
                    }

                    commandNode(
                        title: "Technician",
                        icon: "wrench.and.screwdriver.fill",
                        point: nodes.app,
                        isActive: progress > 0.05,
                        time: t
                    )
                    commandNode(
                        title: "Jamf Pro",
                        icon: "server.rack",
                        point: nodes.jamf,
                        isActive: progress >= 0.42,
                        time: t + 0.35
                    )
                    commandNode(
                        title: "Device",
                        icon: phaseDeviceIcon,
                        point: nodes.device,
                        isActive: progress >= 0.72,
                        time: t + 0.7
                    )
                }
            }
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var progress: CGFloat {
        CGFloat(phase.progress)
    }

    private func nodePositions(in size: CGSize) -> (app: CGPoint, jamf: CGPoint, device: CGPoint) {
        let usableWidth = max(220, size.width)
        // Centre the node row on the available height. The prior
        // `max(48, …)` floor was sized for a 104pt frame; with the v3.22.10
        // 56pt frame the centred row + compact nodes (28pt circles + a
        // single-line label) fits comfortably without clipping.
        let y = size.height * 0.50
        return (
            CGPoint(x: usableWidth * 0.15, y: y),
            CGPoint(x: usableWidth * 0.50, y: y),
            CGPoint(x: usableWidth * 0.85, y: y)
        )
    }

    private func commandTrack(from app: CGPoint, via jamf: CGPoint, to device: CGPoint, time: TimeInterval) -> some View {
        ZStack {
            trackSegment(from: app, to: jamf, progress: min(progress / 0.50, 1.0), time: time)
            trackSegment(from: jamf, to: device, progress: max(0, min((progress - 0.45) / 0.55, 1.0)), time: time + 0.2)
        }
    }

    private func trackSegment(from start: CGPoint, to end: CGPoint, progress: CGFloat, time: TimeInterval) -> some View {
        let width = max(0, end.x - start.x)
        let shimmer = CGFloat((sin(time * 3.2) + 1.0) / 2.0)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(width: width, height: 5)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.35),
                            accentColor,
                            Color.white.opacity(0.86),
                            accentColor.opacity(0.72)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(8, width * progress), height: 5)
                .shadow(color: accentColor.opacity(0.42 + shimmer * 0.25), radius: 4)
        }
        .position(x: start.x + width / 2, y: start.y)
    }

    private func signalPacket(from start: CGPoint, to end: CGPoint, time: TimeInterval, delay: Double) -> some View {
        let cycle = 1.6
        let raw = ((time / cycle) + delay).truncatingRemainder(dividingBy: 1.0)
        let fraction = CGFloat(raw < 0 ? raw + 1.0 : raw)
        let x = start.x + (end.x - start.x) * fraction
        let y = start.y + sin(fraction * .pi) * -4

        return ZStack {
            Circle()
                .fill(accentColor.opacity(0.25))
                .frame(width: 16, height: 16)
                .blur(radius: 3)
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle().stroke(accentColor, lineWidth: 1.5)
                )
        }
        .position(x: x, y: y)
        .opacity(phase.isInProgress ? 1 : 0)
    }

    private func terminalHalo(at point: CGPoint, time: TimeInterval) -> some View {
        let pulse = CGFloat((sin(time * 3.4) + 1.0) / 2.0)
        return Circle()
            .stroke(accentColor.opacity(0.35), lineWidth: 2)
            .frame(width: 30 + pulse * 10, height: 30 + pulse * 10)
            .shadow(color: accentColor.opacity(0.45), radius: 8)
            .position(point)
    }

    private func commandNode(
        title: String,
        icon: String,
        point: CGPoint,
        isActive: Bool,
        time: TimeInterval
    ) -> some View {
        let pulse = CGFloat((sin(time * 2.6) + 1.0) / 2.0)
        let nodeColor = isActive ? accentColor : Color.gray.opacity(0.52)

        return ZStack {
            Circle()
                .fill(nodeColor.opacity(isActive ? 0.24 : 0.12))
                .frame(
                    width: 32 + (isActive && phase.isInProgress ? pulse * 5 : 0),
                    height: 32 + (isActive && phase.isInProgress ? pulse * 5 : 0)
                )
                .blur(radius: isActive ? 1 : 0)
            Circle()
                .fill(ForsettiTheme.surface)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(nodeColor, lineWidth: 1.5))
                .shadow(color: nodeColor.opacity(isActive ? 0.36 : 0.12), radius: isActive ? 6 : 2)
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(nodeColor)
                .accessibilityLabel(Text(title))
        }
        .position(x: point.x, y: point.y)
    }

    private var phaseDeviceIcon: String {
        switch phase {
        case .succeeded:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.octagon.fill"
        case .timedOut:
            return "hourglass"
        default:
            return "laptopcomputer.and.iphone"
        }
    }

    private var accentColor: Color {
        switch phase {
        case .idle:
            return Color.gray
        case .sending, .queued:
            return ForsettiColors.bluePrimary
        case .verifying:
            return .orange
        case .succeeded:
            return ForsettiColors.greenPrimary
        case .failed:
            return .red
        case .timedOut:
            return .orange
        }
    }

    private var accessibilityText: Text {
        Text(CommandStatusIndicatorView.defaultCaption(for: phase) ?? "Command status idle")
    }
}

//endofline
