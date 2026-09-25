import XCTest
@testable import Undertone

final class NamingTests: XCTestCase {
    func testColorFamiliesAndReadableNames() {
        XCTAssertEqual(ColorNamer.family("012169"), .blue)
        XCTAssertEqual(ColorNamer.name("012169"), "Deep Blue")
        XCTAssertEqual(ColorNamer.family("E57E55"), .orange)
        XCTAssertEqual(ColorNamer.name("FFFFFF"), "White")
        XCTAssertEqual(ColorNamer.name("000000"), "Black")
        XCTAssertEqual(ColorNamer.family("7655A3"), .violet)
    }

    func testGeneratedNamesAreStableAndShort() {
        let recipe = GradientRecipe()
        let first = NameGenerator.name(for: recipe, seed: 3)
        XCTAssertEqual(first, NameGenerator.name(for: recipe, seed: 3))
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue((2...3).contains(first.split(separator: " ").count))
    }

    func testSuggestionsAreDistinct() {
        let names = NameGenerator.suggestions(for: GradientRecipe(), startingAt: 10)
        XCTAssertEqual(names.count, 5)
        XCTAssertEqual(Set(names).count, 5)
    }

    func testEmptyGradientIsUntitled() {
        var recipe = GradientRecipe()
        recipe.stops = []
        XCTAssertEqual(NameGenerator.name(for: recipe, seed: 0), NameGenerator.untitled)
    }

    func testModelOutputIsCleanedUp() {
        let cleaned = NameIntelligence.cleaned(["1. \"Harbor Hush\"", "Harbor hush", "A Very Long Name That Rambles On", "Blue Gradient", "  Velvet Tide. "])
        XCTAssertEqual(cleaned, ["Harbor Hush", "Velvet Tide"])
    }
}
