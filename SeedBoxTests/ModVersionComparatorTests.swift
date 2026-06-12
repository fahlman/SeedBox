import XCTest
@testable import SeedBox

final class ModVersionComparatorTests: XCTestCase {
    func testComparesReleaseComponentsNumerically() {
        XCTAssertEqual(ModVersionComparator.compare("1.10.0", to: "1.9.0"), .orderedDescending)
        XCTAssertEqual(ModVersionComparator.compare("1.2.3", to: "1.2.4"), .orderedAscending)
        XCTAssertEqual(ModVersionComparator.compare("2.0.0", to: "2.0.0"), .orderedSame)
    }

    func testTreatsMissingReleaseComponentsAsZero() {
        XCTAssertEqual(ModVersionComparator.compare("1.0", to: "1.0.0"), .orderedSame)
        XCTAssertEqual(ModVersionComparator.compare("1", to: "1.0.1"), .orderedAscending)
    }

    func testOrdersPrereleaseBeforeRelease() {
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-beta", to: "1.0.0"), .orderedAscending)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0", to: "1.0.0-beta"), .orderedDescending)
        XCTAssertEqual(ModVersionComparator.compare("1.0.1-beta", to: "1.0.0"), .orderedDescending)
    }

    func testOrdersPrereleaseIdentifiersPerSemanticVersioning() {
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-alpha", to: "1.0.0-beta"), .orderedAscending)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-beta.2", to: "1.0.0-beta.10"), .orderedAscending)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-beta", to: "1.0.0-beta.2"), .orderedAscending)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-BETA", to: "1.0.0-beta"), .orderedSame)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0-1", to: "1.0.0-alpha"), .orderedAscending)
    }

    func testIgnoresBuildMetadata() {
        XCTAssertEqual(ModVersionComparator.compare("1.0.0+build.5", to: "1.0.0"), .orderedSame)
        XCTAssertEqual(ModVersionComparator.compare("1.0.0+abc", to: "1.0.0+xyz"), .orderedSame)
    }

    func testFallsBackToNumericStringComparisonForNonSemanticVersions() {
        XCTAssertEqual(ModVersionComparator.compare("not-a-version", to: "not-a-version"), .orderedSame)
        XCTAssertEqual(ModVersionComparator.compare("1.0a", to: "1.0b"), .orderedAscending)
    }

    func testSatisfiesMinimumUsesSemanticOrdering() {
        XCTAssertTrue(ModVersionComparator.version("1.10.0", satisfiesMinimum: "1.9.0"))
        XCTAssertFalse(ModVersionComparator.version("1.0.0-beta", satisfiesMinimum: "1.0.0"))
        XCTAssertTrue(ModVersionComparator.version("1.0.0", satisfiesMinimum: "1.0.0-beta"))
        XCTAssertTrue(ModVersionComparator.version("1.0.0-beta.10", satisfiesMinimum: "1.0.0-beta.2"))
    }

    func testSatisfiesMinimumHandlesMissingValues() {
        XCTAssertTrue(ModVersionComparator.version(nil, satisfiesMinimum: nil))
        XCTAssertTrue(ModVersionComparator.version(nil, satisfiesMinimum: "  "))
        XCTAssertFalse(ModVersionComparator.version(nil, satisfiesMinimum: "1.0.0"))
        XCTAssertTrue(ModVersionComparator.version("1.0.0", satisfiesMinimum: nil))
    }
}
