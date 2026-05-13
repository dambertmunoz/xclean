import Foundation

/// Tunable safety/aggressiveness for a single run.
struct Profile {
    let name: String
    /// Items not modified in this many days are eligible under `.age`.
    let ageThresholdDays: Int
    /// How many recent iOS/watchOS/tvOS DeviceSupport bundles to preserve.
    let keepDeviceSupports: Int
    /// How many simulator runtimes per platform to preserve.
    let keepSimulatorRuntimes: Int
    /// Whether to touch Xcode .xcarchive bundles at all.
    let touchesArchives: Bool
    /// Stricter age threshold applied to Archives when allowed.
    let archivesAgeDays: Int
    /// Whether the CocoaPods global cache is in scope.
    let touchesCocoaPodsCache: Bool
    /// Categories considered active for this profile.
    let categories: Set<CleanCategory>

    static let conservative = Profile(
        name: "conservative",
        ageThresholdDays: 60,
        keepDeviceSupports: 5,
        keepSimulatorRuntimes: 3,
        touchesArchives: false,
        archivesAgeDays: 365,
        touchesCocoaPodsCache: true,
        categories: [.orphan, .corruption, .generic]
    )

    static let balanced = Profile(
        name: "balanced",
        ageThresholdDays: 30,
        keepDeviceSupports: 3,
        keepSimulatorRuntimes: 2,
        touchesArchives: false,
        archivesAgeDays: 180,
        touchesCocoaPodsCache: true,
        categories: [.age, .orphan, .corruption, .duplicate, .generic]
    )

    static let aggressive = Profile(
        name: "aggressive",
        ageThresholdDays: 14,
        keepDeviceSupports: 2,
        keepSimulatorRuntimes: 1,
        touchesArchives: true,
        archivesAgeDays: 180,
        touchesCocoaPodsCache: true,
        categories: [.age, .orphan, .corruption, .duplicate, .generic]
    )

    static func named(_ name: String) -> Profile? {
        switch name.lowercased() {
        case "conservative": return .conservative
        case "balanced":     return .balanced
        case "aggressive":   return .aggressive
        default: return nil
        }
    }
}
