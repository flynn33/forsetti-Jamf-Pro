import Foundation

nonisolated struct ReportDeviceIdentityResolver: Sendable {
    nonisolated func resolve(
        domain: ReportInventoryDomain,
        model: String?,
        modelIdentifier: String?,
        modelNumber: String?,
        capacityMb: Int?,
        platformHint: String?
    ) -> ReportDeviceIdentity {
        let deviceType = Self.classify(
            domain: domain,
            model: model,
            modelIdentifier: modelIdentifier,
            platformHint: platformHint
        )

        if let modelIdentifier,
           let catalogInfo = AppleDeviceModelCatalog.info(for: modelIdentifier)
        {
            return ReportDeviceIdentity(
                deviceType: deviceType,
                marketingName: catalogInfo.marketingName,
                generation: generation(from: catalogInfo.marketingName),
                chipName: catalogInfo.chipName,
                ramGB: catalogInfo.ramGB(capacityMb),
                confidence: .catalogResolved,
                sourceDescription: "Resolved from Apple model identifier."
            )
        }

        if let model = Self.clean(model) {
            return ReportDeviceIdentity(
                deviceType: deviceType,
                marketingName: model,
                generation: generation(from: model),
                chipName: nil,
                ramGB: nil,
                confidence: .jamfAuthoritative,
                sourceDescription: "Provided by Jamf inventory."
            )
        }

        if let modelNumber = Self.clean(modelNumber) {
            return ReportDeviceIdentity(
                deviceType: deviceType,
                marketingName: modelNumber,
                generation: nil,
                chipName: nil,
                ramGB: nil,
                confidence: .inferredMedium,
                sourceDescription: "Inferred from model number."
            )
        }

        return ReportDeviceIdentity(
            deviceType: deviceType,
            marketingName: nil,
            generation: nil,
            chipName: nil,
            ramGB: nil,
            confidence: deviceType == .unknown ? .unknown : .inferredHigh,
            sourceDescription: domain == .computer ? "Inferred from computer inventory endpoint." : "Insufficient device identity fields."
        )
    }

    nonisolated static func classify(
        domain: ReportInventoryDomain,
        model: String?,
        modelIdentifier: String?,
        platformHint: String?
    ) -> ReportDeviceType {
        let identifier = clean(modelIdentifier)?.lowercased() ?? ""
        let modelValue = clean(model)?.lowercased() ?? ""
        let platform = clean(platformHint)?.lowercased() ?? ""

        switch domain {
        case .computer:
            if platform.contains("ipad") || modelValue.contains("ipad") || identifier.hasPrefix("ipad") {
                return .ipad
            }
            if platform.contains("iphone") || modelValue.contains("iphone") || identifier.hasPrefix("iphone") {
                return .iphone
            }
            if platform.contains("windows") || platform.contains("linux") {
                return .other
            }
            return .mac
        case .mobile:
            if identifier.hasPrefix("ipad") || modelValue.contains("ipad") {
                return .ipad
            }
            if identifier.hasPrefix("iphone") || modelValue.contains("iphone") {
                return .iphone
            }
            if modelValue.contains("apple tv") || modelValue.contains("appletv") || identifier.hasPrefix("appletv") {
                return .other
            }
            if identifier.isEmpty == false || modelValue.isEmpty == false {
                return .other
            }
            return .unknown
        }
    }

    nonisolated private func generation(from value: String) -> String? {
        guard let open = value.lastIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close
        else {
            return nil
        }

        let inside = value[value.index(after: open) ..< close]
        return inside.isEmpty ? nil : String(inside)
    }

    nonisolated private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.localizedCaseInsensitiveCompare("unknown") == .orderedSame ? nil : trimmed
    }
}
