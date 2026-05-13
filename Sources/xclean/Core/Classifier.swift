import Foundation

enum Verdict: String {
    case safe   // deletable without prompting
    case risky  // deletable only with --include-risky or explicit confirm
    case keep   // do not touch under current profile
}

/// Centralized verdict logic. The only place that knows the rules for
/// "safe to drop under this profile".
struct Classifier {
    let profile: Profile

    func verdict(for c: Candidate) -> Verdict {
        // If the profile does not consider this category at all, keep it.
        guard profile.categories.contains(c.category) else { return .keep }

        switch c.category {
        case .generic:
            return .safe

        case .age:
            guard let date = c.lastUsed else { return .risky }
            let days = Self.daysSince(date)
            return days >= profile.ageThresholdDays ? .safe : .keep

        case .orphan:
            return .safe

        case .corruption:
            return .safe

        case .duplicate:
            // Plugins only emit duplicates that exceed the keep-N quota.
            // Profile category filter already gates whether we look at them.
            return .safe
        }
    }

    static func daysSince(_ date: Date) -> Int {
        let seconds = Date().timeIntervalSince(date)
        return Int(seconds / 86_400)
    }
}
