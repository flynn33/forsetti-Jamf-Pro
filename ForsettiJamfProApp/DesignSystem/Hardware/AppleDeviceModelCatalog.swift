import Foundation


/// Resolved hardware information for an Apple device, derived from its
/// `modelIdentifier` (e.g. `iPad14,5`).
///
/// `AppleDeviceModelCatalog` returns one of these for every identifier it
/// recognizes. The marketing name and chip details come from Apple's published
/// specs; CPU/GPU/Neural-engine core counts are filled in for chips where
/// Apple has documented them. RAM is delivered through `ramGB(forCapacityMb:)`
/// because some models (notably the M4 iPad Pro family) ship two RAM tiers
/// keyed by storage capacity.
nonisolated struct AppleDeviceModelInfo: Sendable {
    /// Marketing name (e.g. "iPad Pro 11-inch (M4)").
    let marketingName: String

    /// Apple chip name (e.g. "Apple M4").
    let chipName: String

    /// CPU core count where Apple has published the value, otherwise nil.
    let cpuCoreCount: Int?

    /// GPU core count where Apple has published the value, otherwise nil.
    let gpuCoreCount: Int?

    /// Neural Engine core count where Apple has published the value, otherwise nil.
    let neuralCoreCount: Int?

    /// Resolves device RAM in gigabytes from the inventory-reported storage
    /// capacity in megabytes.
    ///
    /// For most models RAM is fixed and the closure ignores the capacity.
    /// M4 iPad Pro and similar split-tier devices use the capacity to choose
    /// between an 8 GB and 16 GB SKU (Apple ships 16 GB only on 1 TB / 2 TB).
    /// Returns nil when the capacity is missing on a split-tier device — the
    /// view layer should then show a "RAM tier ambiguous" hint rather than
    /// guessing.
    let ramGB: @Sendable (_ capacityMb: Int?) -> Int?
}

/// Local lookup table mapping `modelIdentifier` to marketing/spec metadata.
///
/// Coverage is iPhone 8 / iPhone X onwards and iPad mini 5 / Air 3 onwards.
/// Apple Watch and Apple TV are intentionally out of scope. Unknown identifiers
/// return nil so the hardware card falls back to displaying the raw value.
///
/// Refresh cadence: Apple typically introduces 3-4 new identifier families per
/// year. When new hardware ships, add an entry here. The catalog tests confirm
/// no duplicate keys and that the RAM-tier logic resolves both M4 iPad Pro
/// branches.
enum AppleDeviceModelCatalog {

    // MARK: - Static helpers

    /// Constant-RAM accessor shared by the majority of devices.
    /// `nonisolated` because the project sets `-default-isolation MainActor`,
    /// and we need this closure to satisfy the `@Sendable` requirement of
    /// `AppleDeviceModelInfo.ramGB` so the catalog dictionary itself can be
    /// referenced from any isolation domain.
    nonisolated private static func fixed(_ ramGB: Int) -> @Sendable (Int?) -> Int? {
        { _ in ramGB }
    }

    /// M4 iPad Pro RAM accessor — 8 GB on 256/512 GB SKUs, 16 GB on 1 TB / 2 TB.
    /// Threshold sits at 768 GB MB-equivalent so a 1 TB device (~1,000,000 MB)
    /// reads as the higher tier without depending on exact base-10 vs. base-2
    /// reporting conventions.
    nonisolated private static let m4iPadProRam: @Sendable (Int?) -> Int? = { capacity in
        guard let capacity else {
            return nil
        }
        return capacity >= 768_000 ? 16 : 8
    }

    // MARK: - Lookup table

    nonisolated static let entries: [String: AppleDeviceModelInfo] = [

        // MARK: iPhone

        // iPhone 8 / 8 Plus / X / XS / XR / XS Max / 11 family / SE 2nd gen
        "iPhone10,1": .init(
            marketingName: "iPhone 8", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPhone10,4": .init(
            marketingName: "iPhone 8", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPhone10,2": .init(
            marketingName: "iPhone 8 Plus", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPhone10,5": .init(
            marketingName: "iPhone 8 Plus", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPhone10,3": .init(
            marketingName: "iPhone X", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPhone10,6": .init(
            marketingName: "iPhone X", chipName: "Apple A11 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 3, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPhone11,2": .init(
            marketingName: "iPhone XS", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone11,4": .init(
            marketingName: "iPhone XS Max", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone11,6": .init(
            marketingName: "iPhone XS Max", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone11,8": .init(
            marketingName: "iPhone XR", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPhone12,1": .init(
            marketingName: "iPhone 11", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone12,3": .init(
            marketingName: "iPhone 11 Pro", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone12,5": .init(
            marketingName: "iPhone 11 Pro Max", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPhone12,8": .init(
            marketingName: "iPhone SE (2nd generation)", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),

        // iPhone 12 family
        "iPhone13,1": .init(
            marketingName: "iPhone 12 mini", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPhone13,2": .init(
            marketingName: "iPhone 12", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPhone13,3": .init(
            marketingName: "iPhone 12 Pro", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone13,4": .init(
            marketingName: "iPhone 12 Pro Max", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),

        // iPhone 13 family / SE 3
        "iPhone14,4": .init(
            marketingName: "iPhone 13 mini", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPhone14,5": .init(
            marketingName: "iPhone 13", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPhone14,2": .init(
            marketingName: "iPhone 13 Pro", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone14,3": .init(
            marketingName: "iPhone 13 Pro Max", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone14,6": .init(
            marketingName: "iPhone SE (3rd generation)", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),

        // iPhone 14 family
        "iPhone14,7": .init(
            marketingName: "iPhone 14", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone14,8": .init(
            marketingName: "iPhone 14 Plus", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone15,2": .init(
            marketingName: "iPhone 14 Pro", chipName: "Apple A16 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone15,3": .init(
            marketingName: "iPhone 14 Pro Max", chipName: "Apple A16 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),

        // iPhone 15 family
        "iPhone15,4": .init(
            marketingName: "iPhone 15", chipName: "Apple A16 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone15,5": .init(
            marketingName: "iPhone 15 Plus", chipName: "Apple A16 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPhone16,1": .init(
            marketingName: "iPhone 15 Pro", chipName: "Apple A17 Pro",
            cpuCoreCount: 6, gpuCoreCount: 6, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPhone16,2": .init(
            marketingName: "iPhone 15 Pro Max", chipName: "Apple A17 Pro",
            cpuCoreCount: 6, gpuCoreCount: 6, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),

        // iPhone 16 family
        "iPhone17,3": .init(
            marketingName: "iPhone 16", chipName: "Apple A18",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPhone17,4": .init(
            marketingName: "iPhone 16 Plus", chipName: "Apple A18",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPhone17,1": .init(
            marketingName: "iPhone 16 Pro", chipName: "Apple A18 Pro",
            cpuCoreCount: 6, gpuCoreCount: 6, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPhone17,2": .init(
            marketingName: "iPhone 16 Pro Max", chipName: "Apple A18 Pro",
            cpuCoreCount: 6, gpuCoreCount: 6, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPhone17,5": .init(
            marketingName: "iPhone 16e", chipName: "Apple A18",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),

        // MARK: iPad

        // MARK: iPad — pre-A12 generations
        //
        // Added in 3.22.10 because tenants commonly still have iPads in
        // service from these generations and the prior catalog (which
        // started at iPad mini 5 / Air 3) had no entry for them. Without
        // a catalog hit the General-frame CPU/GPU/RAM cards rendered as
        // "Unavailable" even though the model identifier was correctly
        // extracted from the inventory payload.
        "iPad5,1": .init(
            marketingName: "iPad mini 4", chipName: "Apple A8",
            cpuCoreCount: 2, gpuCoreCount: 4, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad5,2": .init(
            marketingName: "iPad mini 4", chipName: "Apple A8",
            cpuCoreCount: 2, gpuCoreCount: 4, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad5,3": .init(
            marketingName: "iPad Air 2", chipName: "Apple A8X",
            cpuCoreCount: 3, gpuCoreCount: 8, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad5,4": .init(
            marketingName: "iPad Air 2", chipName: "Apple A8X",
            cpuCoreCount: 3, gpuCoreCount: 8, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad6,3": .init(
            marketingName: "iPad Pro 9.7-inch", chipName: "Apple A9X",
            cpuCoreCount: 2, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad6,4": .init(
            marketingName: "iPad Pro 9.7-inch", chipName: "Apple A9X",
            cpuCoreCount: 2, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad6,7": .init(
            marketingName: "iPad Pro 12.9-inch (1st generation)", chipName: "Apple A9X",
            cpuCoreCount: 2, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad6,8": .init(
            marketingName: "iPad Pro 12.9-inch (1st generation)", chipName: "Apple A9X",
            cpuCoreCount: 2, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad6,11": .init(
            marketingName: "iPad (5th generation)", chipName: "Apple A9",
            cpuCoreCount: 2, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad6,12": .init(
            marketingName: "iPad (5th generation)", chipName: "Apple A9",
            cpuCoreCount: 2, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad7,1": .init(
            marketingName: "iPad Pro 12.9-inch (2nd generation)", chipName: "Apple A10X Fusion",
            cpuCoreCount: 6, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad7,2": .init(
            marketingName: "iPad Pro 12.9-inch (2nd generation)", chipName: "Apple A10X Fusion",
            cpuCoreCount: 6, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad7,3": .init(
            marketingName: "iPad Pro 10.5-inch", chipName: "Apple A10X Fusion",
            cpuCoreCount: 6, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad7,4": .init(
            marketingName: "iPad Pro 10.5-inch", chipName: "Apple A10X Fusion",
            cpuCoreCount: 6, gpuCoreCount: 12, neuralCoreCount: nil,
            ramGB: fixed(4)
        ),
        "iPad7,5": .init(
            marketingName: "iPad (6th generation)", chipName: "Apple A10 Fusion",
            cpuCoreCount: 4, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        "iPad7,6": .init(
            marketingName: "iPad (6th generation)", chipName: "Apple A10 Fusion",
            cpuCoreCount: 4, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(2)
        ),
        // iPad mini 5 / Air 3 (A12)
        "iPad11,1": .init(
            marketingName: "iPad mini (5th generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad11,2": .init(
            marketingName: "iPad mini (5th generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad11,3": .init(
            marketingName: "iPad Air (3rd generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad11,4": .init(
            marketingName: "iPad Air (3rd generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),

        // iPad 7th-9th gen
        "iPad7,11": .init(
            marketingName: "iPad (7th generation)", chipName: "Apple A10 Fusion",
            cpuCoreCount: 4, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPad7,12": .init(
            marketingName: "iPad (7th generation)", chipName: "Apple A10 Fusion",
            cpuCoreCount: 4, gpuCoreCount: 6, neuralCoreCount: nil,
            ramGB: fixed(3)
        ),
        "iPad11,6": .init(
            marketingName: "iPad (8th generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad11,7": .init(
            marketingName: "iPad (8th generation)", chipName: "Apple A12 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad12,1": .init(
            marketingName: "iPad (9th generation)", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),
        "iPad12,2": .init(
            marketingName: "iPad (9th generation)", chipName: "Apple A13 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 8,
            ramGB: fixed(3)
        ),

        // iPad 10th gen
        "iPad13,18": .init(
            marketingName: "iPad (10th generation)", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPad13,19": .init(
            marketingName: "iPad (10th generation)", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),

        // iPad (A16) — 11th-gen branding
        "iPad15,7": .init(
            marketingName: "iPad (A16)", chipName: "Apple A16 Bionic",
            cpuCoreCount: 5, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),
        "iPad15,8": .init(
            marketingName: "iPad (A16)", chipName: "Apple A16 Bionic",
            cpuCoreCount: 5, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(6)
        ),

        // iPad mini 6 (A15) / iPad mini 7 (A17 Pro)
        "iPad14,1": .init(
            marketingName: "iPad mini (6th generation)", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPad14,2": .init(
            marketingName: "iPad mini (6th generation)", chipName: "Apple A15 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPad16,1": .init(
            marketingName: "iPad mini (A17 Pro)", chipName: "Apple A17 Pro",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad16,2": .init(
            marketingName: "iPad mini (A17 Pro)", chipName: "Apple A17 Pro",
            cpuCoreCount: 6, gpuCoreCount: 5, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),

        // iPad Air 4 (A14) / Air 5 (M1) / Air 11" M2 / Air 13" M2 / Air M3
        "iPad13,1": .init(
            marketingName: "iPad Air (4th generation)", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPad13,2": .init(
            marketingName: "iPad Air (4th generation)", chipName: "Apple A14 Bionic",
            cpuCoreCount: 6, gpuCoreCount: 4, neuralCoreCount: 16,
            ramGB: fixed(4)
        ),
        "iPad13,16": .init(
            marketingName: "iPad Air (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad13,17": .init(
            marketingName: "iPad Air (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad14,8": .init(
            marketingName: "iPad Air 11-inch (M2)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 9, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad14,9": .init(
            marketingName: "iPad Air 11-inch (M2)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 9, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad14,10": .init(
            marketingName: "iPad Air 13-inch (M2)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad14,11": .init(
            marketingName: "iPad Air 13-inch (M2)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad15,3": .init(
            marketingName: "iPad Air 11-inch (M3)", chipName: "Apple M3",
            cpuCoreCount: 8, gpuCoreCount: 9, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad15,4": .init(
            marketingName: "iPad Air 11-inch (M3)", chipName: "Apple M3",
            cpuCoreCount: 8, gpuCoreCount: 9, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad15,5": .init(
            marketingName: "iPad Air 13-inch (M3)", chipName: "Apple M3",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),
        "iPad15,6": .init(
            marketingName: "iPad Air 13-inch (M3)", chipName: "Apple M3",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: fixed(8)
        ),

        // iPad Pro 11" 1st gen / 2nd gen / 3rd gen / 4th gen / M4
        "iPad8,1": .init(
            marketingName: "iPad Pro 11-inch (1st generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPad8,2": .init(
            marketingName: "iPad Pro 11-inch (1st generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,3": .init(
            marketingName: "iPad Pro 11-inch (1st generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPad8,4": .init(
            marketingName: "iPad Pro 11-inch (1st generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,9": .init(
            marketingName: "iPad Pro 11-inch (2nd generation)", chipName: "Apple A12Z Bionic",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,10": .init(
            marketingName: "iPad Pro 11-inch (2nd generation)", chipName: "Apple A12Z Bionic",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad13,4": .init(
            marketingName: "iPad Pro 11-inch (3rd generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,5": .init(
            marketingName: "iPad Pro 11-inch (3rd generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,6": .init(
            marketingName: "iPad Pro 11-inch (3rd generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,7": .init(
            marketingName: "iPad Pro 11-inch (3rd generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad14,3": .init(
            marketingName: "iPad Pro 11-inch (4th generation)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad14,4": .init(
            marketingName: "iPad Pro 11-inch (4th generation)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad16,3": .init(
            marketingName: "iPad Pro 11-inch (M4)", chipName: "Apple M4",
            cpuCoreCount: 9, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad16,4": .init(
            marketingName: "iPad Pro 11-inch (M4)", chipName: "Apple M4",
            cpuCoreCount: 9, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),

        // iPad Pro 12.9" / 13" lineage
        "iPad8,5": .init(
            marketingName: "iPad Pro 12.9-inch (3rd generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPad8,6": .init(
            marketingName: "iPad Pro 12.9-inch (3rd generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,7": .init(
            marketingName: "iPad Pro 12.9-inch (3rd generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(4)
        ),
        "iPad8,8": .init(
            marketingName: "iPad Pro 12.9-inch (3rd generation)", chipName: "Apple A12X Bionic",
            cpuCoreCount: 8, gpuCoreCount: 7, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,11": .init(
            marketingName: "iPad Pro 12.9-inch (4th generation)", chipName: "Apple A12Z Bionic",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad8,12": .init(
            marketingName: "iPad Pro 12.9-inch (4th generation)", chipName: "Apple A12Z Bionic",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 8,
            ramGB: fixed(6)
        ),
        "iPad13,8": .init(
            marketingName: "iPad Pro 12.9-inch (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,9": .init(
            marketingName: "iPad Pro 12.9-inch (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,10": .init(
            marketingName: "iPad Pro 12.9-inch (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad13,11": .init(
            marketingName: "iPad Pro 12.9-inch (5th generation)", chipName: "Apple M1",
            cpuCoreCount: 8, gpuCoreCount: 8, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad14,5": .init(
            marketingName: "iPad Pro 12.9-inch (6th generation)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad14,6": .init(
            marketingName: "iPad Pro 12.9-inch (6th generation)", chipName: "Apple M2",
            cpuCoreCount: 8, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad16,5": .init(
            marketingName: "iPad Pro 13-inch (M4)", chipName: "Apple M4",
            cpuCoreCount: 9, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        ),
        "iPad16,6": .init(
            marketingName: "iPad Pro 13-inch (M4)", chipName: "Apple M4",
            cpuCoreCount: 9, gpuCoreCount: 10, neuralCoreCount: 16,
            ramGB: m4iPadProRam
        )
    ]

    /// Returns hardware metadata for `modelIdentifier` if known, else nil.
    /// Trims whitespace before lookup so a stray API response with a trailing
    /// newline still resolves.
    nonisolated static func info(for modelIdentifier: String) -> AppleDeviceModelInfo? {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        return entries[trimmed]
    }
}

//endofline
