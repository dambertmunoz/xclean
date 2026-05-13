import XCTest
@testable import xclean

final class ClassifierTests: XCTestCase {
    private func makeCandidate(category: CleanCategory, lastUsedDaysAgo: Int? = nil) -> Candidate {
        let date = lastUsedDaysAgo.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        return Candidate(
            cleanerID: "test",
            displayName: "test-item",
            sizeBytes: 1024,
            lastUsed: date,
            category: category,
            detail: "fixture",
            removal: .path(URL(fileURLWithPath: "/tmp/does-not-exist"))
        )
    }

    // MARK: - .generic

    func testGenericIsAlwaysSafeWhenCategoryEnabled() {
        let c = Classifier(profile: .balanced)
        XCTAssertEqual(c.verdict(for: makeCandidate(category: .generic)), .safe)
    }

    // MARK: - .age

    func testAgeOlderThanThresholdIsSafe() {
        let c = Classifier(profile: .balanced) // 30d threshold
        let cand = makeCandidate(category: .age, lastUsedDaysAgo: 60)
        XCTAssertEqual(c.verdict(for: cand), .safe)
    }

    func testAgeYoungerThanThresholdIsKept() {
        let c = Classifier(profile: .balanced)
        let cand = makeCandidate(category: .age, lastUsedDaysAgo: 5)
        XCTAssertEqual(c.verdict(for: cand), .keep)
    }

    func testAgeWithoutDateIsRisky() {
        let c = Classifier(profile: .balanced)
        let cand = makeCandidate(category: .age, lastUsedDaysAgo: nil)
        XCTAssertEqual(c.verdict(for: cand), .risky)
    }

    // MARK: - .orphan

    func testOrphanIsSafe() {
        let c = Classifier(profile: .balanced)
        XCTAssertEqual(c.verdict(for: makeCandidate(category: .orphan)), .safe)
    }

    // MARK: - .corruption

    func testCorruptionIsSafe() {
        let c = Classifier(profile: .balanced)
        XCTAssertEqual(c.verdict(for: makeCandidate(category: .corruption)), .safe)
    }

    // MARK: - .duplicate

    func testDuplicateIsSafeUnderBalanced() {
        let c = Classifier(profile: .balanced)
        XCTAssertEqual(c.verdict(for: makeCandidate(category: .duplicate)), .safe)
    }

    func testDuplicateIsKeptUnderConservative() {
        // Conservative profile does not consider duplicates at all.
        let c = Classifier(profile: .conservative)
        XCTAssertEqual(c.verdict(for: makeCandidate(category: .duplicate)), .keep)
    }

    // MARK: - profile filtering

    func testConservativeKeepsAgeCategory() {
        // .age is not in the conservative profile's category set.
        let c = Classifier(profile: .conservative)
        let cand = makeCandidate(category: .age, lastUsedDaysAgo: 365)
        XCTAssertEqual(c.verdict(for: cand), .keep)
    }
}
