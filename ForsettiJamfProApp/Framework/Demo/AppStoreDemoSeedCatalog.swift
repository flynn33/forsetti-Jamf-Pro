import Foundation

/// Built-in sample inventory and catalog data for App Store Review demo mode.
///
/// Records are fictional retail/IT devices with no real customer PII. Serial
/// numbers and names are clearly demo-oriented so reviewers never confuse them
/// with a live tenant.
///
/// Support Technician relies on `general.managementId`, multi-section detail
/// payloads, MDM command history, and application inventory — those fields are
/// intentionally richer than the search-only fixtures used by Computer Search.
nonisolated enum AppStoreDemoSeedCatalog: Sendable {

    // MARK: - Computers

    nonisolated static let computers: [[String: Any]] = [
        computer(
            id: "1001",
            managementID: "11111111-1111-4111-8111-111111111101",
            name: "Reviewer MacBook Pro",
            serial: "C02DEMO0001",
            udid: "DEMO-UDID-MAC-0001",
            model: "MacBook Pro (14-inch, 2023)",
            modelIdentifier: "Mac14,9",
            osVersion: "15.1",
            osBuild: "24B83",
            username: "app.reviewer",
            email: "reviewer@example.com",
            assetTag: "AST-DEMO-1001",
            ip: "10.20.0.11",
            applications: [
                ("Safari", "18.1", "/Applications/Safari.app", "com.apple.Safari"),
                ("Google Chrome", "131.0.6778.85", "/Applications/Google Chrome.app", "com.google.Chrome"),
                ("Slack", "4.41.105", "/Applications/Slack.app", "com.tinyspeck.slackmacgap"),
                ("Microsoft Word", "16.90.1", "/Applications/Microsoft Word.app", "com.microsoft.Word")
            ]
        ),
        computer(
            id: "1002",
            managementID: "11111111-1111-4111-8111-111111111102",
            name: "Floor iMac — Demo Store 12",
            serial: "C02DEMO0002",
            udid: "DEMO-UDID-MAC-0002",
            model: "iMac (24-inch, M3, 2023)",
            modelIdentifier: "Mac15,4",
            osVersion: "14.7",
            osBuild: "23H124",
            username: "store.floor",
            email: "floor@example.com",
            assetTag: "AST-DEMO-1002",
            ip: "10.20.0.22",
            applications: [
                ("Safari", "17.6", "/Applications/Safari.app", "com.apple.Safari"),
                ("POS Companion", "3.2.1", "/Applications/POS Companion.app", "com.example.pos")
            ]
        ),
        computer(
            id: "1003",
            managementID: "11111111-1111-4111-8111-111111111103",
            name: "Warehouse Mac mini",
            serial: "C02DEMO0003",
            udid: "DEMO-UDID-MAC-0003",
            model: "Mac mini (M2, 2023)",
            modelIdentifier: "Mac14,3",
            osVersion: "15.0.1",
            osBuild: "24A348",
            username: "warehouse.ops",
            email: "warehouse@example.com",
            assetTag: "AST-DEMO-1003",
            ip: "10.20.0.33",
            applications: [
                ("Safari", "18.0", "/Applications/Safari.app", "com.apple.Safari"),
                ("Inventory Scanner", "2.0.0", "/Applications/Inventory Scanner.app", "com.example.scanner")
            ]
        )
    ]

    nonisolated static func computer(id: String) -> [String: Any]? {
        computers.first { String(describing: $0["id"] ?? "") == id }
    }

    nonisolated static func filteredComputers(filter: String?) -> [[String: Any]] {
        computers.filter { matches(searchableBlob(forComputer: $0), filter: filter) }
    }

    // MARK: - Mobile devices

    nonisolated static let mobileDevices: [[String: Any]] = [
        mobileDevice(
            id: "2001",
            managementID: "22222222-2222-4222-8222-222222222201",
            name: "Reviewer iPad Pro",
            serial: "F9FDEMO0001",
            udid: "DEMO-UDID-IPAD-0001",
            model: "iPad Pro 11-inch (M4)",
            modelIdentifier: "iPad16,3",
            osVersion: "18.1",
            username: "app.reviewer",
            email: "reviewer@example.com",
            assetTag: "AST-DEMO-2001",
            supervised: true
        ),
        mobileDevice(
            id: "2002",
            managementID: "22222222-2222-4222-8222-222222222202",
            name: "POS iPhone — Demo Lane 3",
            serial: "F9FDEMO0002",
            udid: "DEMO-UDID-IPHONE-0002",
            model: "iPhone 15",
            modelIdentifier: "iPhone15,4",
            osVersion: "18.0.1",
            username: "pos.lane3",
            email: "pos@example.com",
            assetTag: "AST-DEMO-2002",
            supervised: true
        ),
        mobileDevice(
            id: "2003",
            managementID: "22222222-2222-4222-8222-222222222203",
            name: "Training iPad Air",
            serial: "F9FDEMO0003",
            udid: "DEMO-UDID-IPAD-0003",
            model: "iPad Air 11-inch (M2)",
            modelIdentifier: "iPad14,8",
            osVersion: "17.6.1",
            username: "training.lead",
            email: "training@example.com",
            assetTag: "AST-DEMO-2003",
            supervised: true
        )
    ]

    nonisolated static func mobileDevice(id: String) -> [String: Any]? {
        mobileDevices.first { String(describing: $0["id"] ?? "") == id }
    }

    nonisolated static func filteredMobileDevices(filter: String?) -> [[String: Any]] {
        mobileDevices.filter { matches(searchableBlob(forMobile: $0), filter: filter) }
    }

    // MARK: - Support Technician extras

    /// Sample MDM command history for modern `GET /api/v2/mdm/commands`.
    nonisolated static func mdmCommandHistoryJSON(managementID: String?) -> Data {
        let clientID = managementID ?? "11111111-1111-4111-8111-111111111101"
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        func stamp(_ hoursAgo: Double) -> String {
            formatter.string(from: now.addingTimeInterval(-hoursAgo * 3_600))
        }

        let results: [[String: Any]] = [
            [
                "uuid": "demo-cmd-001",
                "clientManagementId": clientID,
                "commandType": "DEVICE_INFORMATION",
                "status": "Acknowledged",
                "dateSent": stamp(2),
                "dateCompleted": stamp(1.9)
            ],
            [
                "uuid": "demo-cmd-002",
                "clientManagementId": clientID,
                "commandType": "BlankPush",
                "status": "Acknowledged",
                "dateSent": stamp(6),
                "dateCompleted": stamp(5.9)
            ],
            [
                "uuid": "demo-cmd-003",
                "clientManagementId": clientID,
                "commandType": "UpdateInventory",
                "status": "Pending",
                "dateSent": stamp(0.25),
                "dateCompleted": NSNull()
            ],
            [
                "uuid": "demo-cmd-004",
                "clientManagementId": clientID,
                "commandType": "RESTART_DEVICE",
                "status": "Failed",
                "dateSent": stamp(26),
                "dateCompleted": stamp(25.5),
                "errorReasons": ["Device offline during restart window (demo sample)"]
            ]
        ]

        return json([
            "totalCount": results.count,
            "results": results
        ])
    }

    nonisolated static func classicPoliciesJSON() -> Data {
        json([
            "policies": [
                ["id": 501, "name": "Demo — Install Chrome"],
                ["id": 502, "name": "Demo — Wi‑Fi Profile (Retail)"],
                ["id": 503, "name": "Demo — Weekly Inventory"],
                ["id": 504, "name": "Demo — Security Baseline"]
            ]
        ])
    }

    nonisolated static func classicComputerHistoryJSON(inventoryID: String) -> Data {
        json([
            "computer_history": [
                "id": Int(inventoryID) ?? 1001,
                "commands": [
                    "completed": [
                        ["name": "Update Inventory", "date_time_completed": "2026-07-29T18:00:00Z", "username": "app-store-review-demo"]
                    ],
                    "pending": [
                        ["name": "Blank Push", "date_time_issued": "2026-07-30T10:00:00Z"]
                    ],
                    "failed": []
                ]
            ]
        ])
    }

    nonisolated static func lapsAccountsJSON() -> Data {
        json([
            "results": [
                [
                    "username": "localadmin",
                    "guid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "userSource": "JAMF"
                ]
            ]
        ])
    }

    nonisolated static func lapsPasswordJSON() -> Data {
        json([
            "password": "Demo-Only-Passw0rd!",
            "expirationTime": "2099-01-01T00:00:00Z"
        ])
    }

    // MARK: - Auth / locations / prestages

    nonisolated static func authPrivilegesJSON() -> Data {
        let privileges = [
            "Read Computers",
            "Read Mobile Devices",
            "Read Computer PreStage Enrollments",
            "Read Mobile Device PreStage Enrollments",
            "View MDM command information in Jamf Pro API",
            "Send MDM command information in Jamf Pro API",
            "Send Device Information Command",
            "Send Computer Restart Command",
            "Send Mobile Device Restart Device Command",
            "Send Mobile Device Remove Passcode Command",
            "Send MDM Check In Command",
            "Flush MDM Commands",
            "Send Computer Remote Desktop Command",
            "Create Computer PreStage Enrollments",
            "Update Computer PreStage Enrollments",
            "Read Policies",
            "Create Policies",
            "Update Policies",
            "Delete Policies",
            "Read Scripts",
            "Create Scripts",
            "Update Scripts",
            "Delete Scripts",
            "Read Local Admin Password",
            "Update Local Admin Password Settings",
            "Read Buildings",
            "Read Departments",
            "Read Users"
        ]
        return json([
            "account": [
                "username": "app-store-review-demo",
                "privilegesBySite": [
                    "-1": privileges
                ]
            ]
        ])
    }

    nonisolated static func buildingsJSON() -> Data {
        json([
            "totalCount": 2,
            "results": [
                ["id": "10", "name": "Demo HQ"],
                ["id": "11", "name": "Demo Warehouse"]
            ]
        ])
    }

    nonisolated static func departmentsJSON() -> Data {
        json([
            "totalCount": 2,
            "results": [
                ["id": "20", "name": "Retail Floor"],
                ["id": "21", "name": "IT Operations"]
            ]
        ])
    }

    nonisolated static func computerPrestagesListJSON() -> Data {
        json([
            "totalCount": 1,
            "results": [
                [
                    "id": "demo-c-prestage-1",
                    "displayName": "Demo Mac PreStage",
                    "mandatory": true,
                    "mdmRemovable": false
                ]
            ]
        ])
    }

    nonisolated static func computerPrestageDetailJSON(id: String) -> Data {
        json([
            "id": id,
            "displayName": "Demo Mac PreStage",
            "mandatory": true,
            "mdmRemovable": false
        ])
    }

    nonisolated static func computerPrestageScopeJSON(prestageID: String) -> Data {
        _ = prestageID
        return json([
            "assignments": [
                [
                    "serialNumber": "C02DEMO0001",
                    "prestageId": "demo-c-prestage-1"
                ],
                [
                    "serialNumber": "C02DEMO0002",
                    "prestageId": "demo-c-prestage-1"
                ]
            ],
            "totalCount": 2
        ])
    }

    nonisolated static func mobilePrestagesListJSON() -> Data {
        json([
            "totalCount": 1,
            "results": [
                [
                    "id": "demo-m-prestage-1",
                    "displayName": "Demo iPad PreStage",
                    "mandatory": true,
                    "mdmRemovable": false
                ]
            ]
        ])
    }

    nonisolated static func mobilePrestageDetailJSON(id: String) -> Data {
        json([
            "id": id,
            "displayName": "Demo iPad PreStage",
            "mandatory": true,
            "mdmRemovable": false
        ])
    }

    nonisolated static func mobilePrestageScopeJSON(prestageID: String) -> Data {
        _ = prestageID
        return json([
            "assignments": [
                [
                    "serialNumber": "F9FDEMO0001",
                    "prestageId": "demo-m-prestage-1"
                ],
                [
                    "serialNumber": "F9FDEMO0003",
                    "prestageId": "demo-m-prestage-1"
                ]
            ],
            "totalCount": 2
        ])
    }

    // MARK: - RSQL filter matching (Support Technician + Search modules)

    /// Extracts human search terms from Jamf RSQL filters such as
    /// `(general.name=="*MacBook*",hardware.serialNumber=="*MacBook*")` or
    /// `(serialNumber=='*ipad*',username=='*ipad*')`.
    nonisolated static func termsFromRSQLFilter(_ filter: String?) -> [String] {
        guard let filter, filter.isEmpty == false else { return [] }

        var terms: [String] = []
        var remaining = Substring(filter)

        while let eq = remaining.range(of: "==") {
            remaining = remaining[eq.upperBound...]
            guard let first = remaining.first else { break }

            let quote: Character?
            if first == "\"" || first == "'" {
                quote = first
                remaining = remaining.dropFirst()
            } else {
                quote = nil
            }

            if let quote {
                guard let end = remaining.firstIndex(of: quote) else { break }
                let raw = String(remaining[..<end])
                remaining = remaining[remaining.index(after: end)...]
                let cleaned = raw
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if cleaned.isEmpty == false {
                    terms.append(cleaned)
                }
            } else {
                break
            }
        }

        return Array(Set(terms))
    }

    nonisolated static func matches(_ searchableBlob: String, filter: String?) -> Bool {
        let terms = termsFromRSQLFilter(filter)
        if terms.isEmpty {
            guard let filter, filter.isEmpty == false else { return true }
            // Unquoted / simple filters (Computer Search free text path).
            let needle = filter.lowercased()
            if needle.contains("==") {
                // Unparsed RSQL — do not hide the fleet.
                return true
            }
            return searchableBlob.contains(needle)
        }
        // OR semantics across RSQL alternatives: any term matches.
        return terms.contains { searchableBlob.contains($0) }
    }

    // MARK: - Builders

    nonisolated private static func computer(
        id: String,
        managementID: String,
        name: String,
        serial: String,
        udid: String,
        model: String,
        modelIdentifier: String,
        osVersion: String,
        osBuild: String,
        username: String,
        email: String,
        assetTag: String,
        ip: String,
        applications: [(String, String, String, String)]
    ) -> [String: Any] {
        let appRecords: [[String: Any]] = applications.map { name, version, path, bundle in
            [
                "name": name,
                "version": version,
                "path": path,
                "bundleId": bundle,
                "bundleIdentifier": bundle
            ]
        }

        return [
            "id": id,
            "udid": udid,
            "general": [
                "name": name,
                "lastIpAddress": ip,
                "assetTag": assetTag,
                "managementStatus": "Managed",
                "enrollmentStatus": "Enrolled",
                "managed": true,
                "managementId": managementID,
                "clientManagementId": managementID,
                "reportDate": "2026-07-30T12:00:00Z",
                "lastContactTime": "2026-07-30T11:55:00Z",
                "lastEnrolledDate": "2025-11-02T09:00:00Z",
                "platform": "Mac",
                "prestageEnrollmentProfileName": "Demo Mac PreStage",
                "prestageEnrollmentProfileId": "demo-c-prestage-1",
                "remoteManagement": [
                    "managed": true,
                    "managementUsername": "jamfmanagement"
                ]
            ],
            "hardware": [
                "serialNumber": serial,
                "model": model,
                "modelIdentifier": modelIdentifier,
                "macAddress": "AA:BB:CC:DD:EE:0\(id.suffix(1))",
                "altMacAddress": "AA:BB:CC:DD:EF:0\(id.suffix(1))",
                "totalRamMegabytes": 16_384,
                "processorType": "Apple M-series",
                "coreCount": 10,
                "appleSilicon": true,
                "batteryCapacityPercent": 88
            ],
            "operatingSystem": [
                "version": osVersion,
                "build": osBuild,
                "name": "macOS",
                "activeDirectoryStatus": "Not Bound",
                "fileVault2Status": "All Partitions Encrypted"
            ],
            "userAndLocation": [
                "username": username,
                "email": email,
                "realName": username.replacingOccurrences(of: ".", with: " ").capitalized,
                "departmentId": "21",
                "buildingId": "10",
                "phone": "555-0100",
                "position": "Demo Operator"
            ],
            "storage": [
                "bootDriveAvailableSpaceMegabytes": 180_000,
                "disks": [
                    [
                        "device": "disk0",
                        "model": "APPLE SSD",
                        "sizeMegabytes": 512_000,
                        "partitions": [
                            [
                                "name": "Macintosh HD",
                                "sizeMegabytes": 512_000,
                                "availableMegabytes": 180_000,
                                "fileVault2State": "ENCRYPTED",
                                "partitionType": "BOOT"
                            ]
                        ]
                    ]
                ]
            ],
            "security": [
                "sipStatus": "Enabled",
                "firewallEnabled": true,
                "activationLockEnabled": false,
                "secureBootLevel": "full",
                "externalBootLevel": "allowed",
                "authenticatedRootEnabled": true,
                "autoLoginDisabled": true
            ],
            "diskEncryption": [
                "fileVault2Enabled": true,
                "bootPartitionEncryptionDetails": [
                    "partitionName": "Macintosh HD",
                    "partitionFileVault2State": "ENCRYPTED",
                    "partitionFileVault2Percent": 100
                ]
            ],
            "applications": appRecords,
            "localUserAccounts": [
                [
                    "username": "localadmin",
                    "fullName": "Local Administrator",
                    "admin": true,
                    "homeDirectory": "/Users/localadmin",
                    "userAccountType": "LOCAL",
                    "passwordMinLength": 12,
                    "computerAzureActiveDirectoryId": ""
                ],
                [
                    "username": username,
                    "fullName": username.replacingOccurrences(of: ".", with: " ").capitalized,
                    "admin": false,
                    "homeDirectory": "/Users/\(username.replacingOccurrences(of: ".", with: ""))",
                    "userAccountType": "LOCAL"
                ]
            ],
            "configurationProfiles": [
                [
                    "id": "cp-wifi",
                    "displayName": "Demo Wi‑Fi (Retail)",
                    "uuid": "DEMO-PROFILE-WIFI-0001",
                    "username": username,
                    "removable": false
                ],
                [
                    "id": "cp-sec",
                    "displayName": "Demo Security Baseline",
                    "uuid": "DEMO-PROFILE-SEC-0001",
                    "username": username,
                    "removable": false
                ]
            ],
            "groupMemberships": [
                ["groupName": "Demo — All Managed Macs", "groupId": "g-mac-1", "smartGroup": true],
                ["groupName": "Demo — App Review Devices", "groupId": "g-mac-2", "smartGroup": false]
            ],
            "extensionAttributes": [
                [
                    "id": "ea-1",
                    "name": "Demo Asset Owner",
                    "type": "STRING",
                    "values": ["App Store Review"]
                ]
            ],
            "certificates": [
                [
                    "commonName": "Demo Device Identity",
                    "identity": true,
                    "expirationDate": "2027-07-01T00:00:00Z"
                ]
            ]
        ]
    }

    nonisolated private static func mobileDevice(
        id: String,
        managementID: String,
        name: String,
        serial: String,
        udid: String,
        model: String,
        modelIdentifier: String,
        osVersion: String,
        username: String,
        email: String,
        assetTag: String,
        supervised: Bool
    ) -> [String: Any] {
        [
            "id": id,
            "udid": udid,
            "serialNumber": serial,
            "managementId": managementID,
            "general": [
                "displayName": name,
                "name": name,
                "deviceName": name,
                "assetTag": assetTag,
                "serialNumber": serial,
                "udid": udid,
                "osVersion": osVersion,
                "osBuild": "22B83",
                "model": model,
                "modelIdentifier": modelIdentifier,
                "supervised": supervised,
                "managed": true,
                "managementId": managementID,
                "clientManagementId": managementID,
                "lastInventoryUpdateDate": "2026-07-30T11:40:00Z",
                "lastInventoryUpdate": "2026-07-30T11:40:00Z",
                "ipAddress": "10.30.0.\(id.suffix(1))",
                "enrollmentMethodPrestage": [
                    "id": "demo-m-prestage-1",
                    "name": "Demo iPad PreStage"
                ]
            ],
            "hardware": [
                "model": model,
                "modelIdentifier": modelIdentifier,
                "serialNumber": serial,
                "capacityMb": 256_000,
                "availableSpaceMb": 120_000,
                "batteryLevel": 87
            ],
            "userAndLocation": [
                "username": username,
                "emailAddress": email,
                "realName": username.replacingOccurrences(of: ".", with: " ").capitalized
            ],
            "network": [
                "ipAddress": "10.30.0.\(id.suffix(1))",
                "wifiMacAddress": "11:22:33:44:55:0\(id.suffix(1))",
                "cellularTechnology": "LTE"
            ],
            "security": [
                "dataProtected": true,
                "blockLevelEncryptionCapable": true,
                "fileLevelEncryptionCapable": true,
                "passcodePresent": true,
                "passcodeCompliant": true,
                "hardwareEncryption": 3,
                "activationLockEnabled": false,
                "jailbreakDetected": false
            ],
            "applications": [
                [
                    "identifier": "com.apple.mobilesafari",
                    "name": "Safari",
                    "version": "18.1",
                    "shortVersion": "18.1"
                ],
                [
                    "identifier": "com.example.demoapp",
                    "name": "Demo Retail App",
                    "version": "5.4.0",
                    "shortVersion": "5.4"
                ]
            ],
            "configurationProfiles": [
                [
                    "displayName": "Demo Mobile Restrictions",
                    "identifier": "com.example.demo.restrictions",
                    "uuid": "DEMO-MOBILE-PROFILE-1"
                ]
            ],
            "certificates": [
                [
                    "commonName": "Demo Mobile Identity",
                    "identity": true
                ]
            ],
            "extensionAttributes": [
                [
                    "id": "mea-1",
                    "name": "Demo Lane",
                    "type": "STRING",
                    "value": "App Review"
                ]
            ]
        ]
    }

    nonisolated private static func searchableBlob(forComputer record: [String: Any]) -> String {
        let general = record["general"] as? [String: Any] ?? [:]
        let hardware = record["hardware"] as? [String: Any] ?? [:]
        let user = record["userAndLocation"] as? [String: Any] ?? [:]
        let parts: [String] = [
            String(describing: record["id"] ?? ""),
            String(describing: general["name"] ?? ""),
            String(describing: hardware["serialNumber"] ?? ""),
            String(describing: hardware["model"] ?? ""),
            String(describing: user["username"] ?? ""),
            String(describing: user["email"] ?? "")
        ]
        return parts.joined(separator: " ").lowercased()
    }

    nonisolated private static func searchableBlob(forMobile record: [String: Any]) -> String {
        let general = record["general"] as? [String: Any] ?? [:]
        let hardware = record["hardware"] as? [String: Any] ?? [:]
        let user = record["userAndLocation"] as? [String: Any] ?? [:]
        let parts: [String] = [
            String(describing: record["id"] ?? ""),
            String(describing: general["displayName"] ?? general["name"] ?? ""),
            String(describing: record["serialNumber"] ?? general["serialNumber"] ?? hardware["serialNumber"] ?? ""),
            String(describing: general["model"] ?? hardware["model"] ?? ""),
            String(describing: user["username"] ?? ""),
            String(describing: user["emailAddress"] ?? "")
        ]
        return parts.joined(separator: " ").lowercased()
    }

    nonisolated private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
