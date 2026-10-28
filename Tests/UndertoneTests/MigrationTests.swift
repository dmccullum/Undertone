import XCTest
@testable import Undertone

final class MigrationTests: XCTestCase {
    private func scratchDefaults() -> (UserDefaults, String) {
        let name = "UndertoneTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testSystemKeysAreFilteredOut() {
        let keys = BundleIDMigration.appKeys([
            "currentGradientID": "A", "sidebarTab": "colors", "NSWindow Frame studio": "0 0 1 1",
            "AppleLanguages": ["en"], "com.apple.something": 1, "exportFormat": "jpeg",
        ])
        XCTAssertEqual(Set(keys.keys), ["currentGradientID", "sidebarTab", "exportFormat"])
    }

    func testCopiesOldKeysOnceIntoAnEmptyDomain() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let old: [String: Any] = ["showsInspector": false, "jpegQuality": 0.8, "NSNavPanelExpandedSizeForSaveMode": "{1, 1}"]

        XCTAssertTrue(BundleIDMigration.migrate(from: old, into: defaults, currentDomain: [:]))
        XCTAssertEqual(defaults.object(forKey: "showsInspector") as? Bool, false)
        XCTAssertEqual(defaults.double(forKey: "jpegQuality"), 0.8)
        XCTAssertNil(defaults.object(forKey: "NSNavPanelExpandedSizeForSaveMode"))
        XCTAssertEqual(defaults.string(forKey: BundleIDMigration.marker), BundleIDMigration.oldBundleID)

        // The marker stops a second run from overwriting newer settings.
        defaults.set(true, forKey: "showsInspector")
        let current = defaults.persistentDomain(forName: name) ?? [:]
        XCTAssertFalse(BundleIDMigration.migrate(from: old, into: defaults, currentDomain: current))
        XCTAssertEqual(defaults.object(forKey: "showsInspector") as? Bool, true)
    }

    func testDomainThatAlreadyHasAppKeysIsLeftAlone() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(BundleIDMigration.migrate(from: ["sidebarTab": "colors"], into: defaults, currentDomain: ["sidebarTab": "gradients"]))
        XCTAssertNil(defaults.object(forKey: "sidebarTab"))
        XCTAssertNotNil(defaults.object(forKey: BundleIDMigration.marker))
    }
}
