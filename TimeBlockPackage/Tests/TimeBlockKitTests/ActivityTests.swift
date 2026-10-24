#if canImport(AppKit)
import AppKit
#endif
import Testing
@testable import TimeBlockKit

struct ActivityTests {
    private func search(_ query: String) -> [String] {
        ActivitySearch.results(for: query, in: BlockCategory.library).map(\.name)
    }

    @Test func searchPutsNamesBeforeOtherWords() {
        let results = search("lun")
        #expect(results.first == "Lunch")
        #expect(search("meal").prefix(4) == ["Meal together", "Breakfast", "Lunch", "Dinner"])
    }

    @Test func searchFindsByOtherWordsAndGroup() {
        #expect(search("slack") == ["Work chat"])
        #expect(search("ping pong") == ["Table tennis"])
        #expect(search("cafe").first == "Café")
        #expect(search("drift").contains("Doomscroll"))
        #expect(search("zzzz").isEmpty)
        #expect(search("  ").isEmpty)
    }

    @Test func idsAreUniqueAndFavoritesExist() {
        let ids = BlockCategory.defaults.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(BlockCategory.defaultFavorites.allSatisfy(ids.contains))
        // The first categories' ids still exist, so old logs still find them.
        let first = ["work", "meeting", "study", "meal", "coffee", "exercise", "outdoor", "social", "family",
                     "commute", "rest", "nap", "screen", "doomscroll"]
        #expect(first.allSatisfy(ids.contains))
    }

    @Test func retiredActivitiesStayKnownButCantBePicked() {
        let retired = BlockCategory.defaults.filter(\.isRetired).map(\.id)
        #expect(retired == ["meal", "screen"])
        #expect(!BlockCategory.library.contains { $0.isRetired })
        #expect(!BlockCategory.defaultFavorites.contains { retired.contains($0) })
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: .standard, nowMinute: 9 * 60),
            logs: [BlockLog(startIndex: 0, length: 3, categoryID: "meal")],
            categories: BlockCategory.defaults, favorites: ["meal", "lunch"])
        #expect(snapshot.cells[0].categoryID == "meal")
        #expect(snapshot.categories["meal"]?.name == "Meal")
        #expect(snapshot.favorites.map(\.id) == ["lunch"])
        #expect(!snapshot.trackCategories.contains { $0.id == "meal" })
    }

    @Test func everyActivityTakesItsGroupsColor() {
        #expect(BlockCategory.defaults.allSatisfy { $0.group.map { $0.color } ?? $0.color == $0.color })
    }

    #if canImport(AppKit)
    @Test func everySymbolExists() {
        let missing = BlockCategory.defaults.map(\.symbol).filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        #expect(missing.isEmpty)
    }
    #endif
}
