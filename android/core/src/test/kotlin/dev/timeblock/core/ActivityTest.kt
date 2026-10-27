package dev.timeblock.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ActivityTest {
    private fun search(query: String) = ActivitySearch.results(query, BlockCategories.library).map { it.name }

    @Test fun searchPutsNamesBeforeOtherWords() {
        assertEquals("Lunch", search("lun").first())
        assertEquals(listOf("Meal together", "Breakfast", "Lunch", "Dinner"), search("meal").take(4))
    }

    @Test fun searchFindsByOtherWordsAndGroup() {
        assertEquals(listOf("Work chat"), search("slack"))
        assertEquals(listOf("Table tennis"), search("ping pong"))
        assertEquals("Café", search("cafe").first())
        assertTrue("Doomscroll" in search("drift"))
        assertTrue(search("zzzz").isEmpty())
        assertTrue(search("  ").isEmpty())
    }

    @Test fun idsAreUniqueAndFavoritesExist() {
        val ids = BlockCategories.defaults.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(BlockCategories.defaultFavorites.all { it in ids })
        // The first categories' ids still exist, so old logs still find them.
        val first = listOf(
            "work", "meeting", "study", "meal", "coffee", "exercise", "outdoor", "social", "family", "commute", "rest",
            "nap", "screen", "doomscroll")
        assertTrue(first.all { it in ids })
    }

    @Test fun retiredActivitiesStayKnownButCantBePicked() {
        val retired = BlockCategories.defaults.filter { it.isRetired }.map { it.id }
        assertEquals(listOf("meal", "screen"), retired)
        assertFalse(BlockCategories.library.any { it.isRetired })
        assertFalse(BlockCategories.defaultFavorites.any { it in retired })
        val snapshot = DaySnapshot(
            DayStatus(Schedule.standard, 9 * 60), listOf(BlockLog(startIndex = 0, length = 3, categoryID = "meal")),
            BlockCategories.defaults, favorites = listOf("meal", "lunch"))
        assertEquals("meal", snapshot.cells[0].categoryID)
        assertEquals("Meal", snapshot.categories["meal"]?.name)
        assertEquals(listOf("lunch"), snapshot.favorites.map { it.id })
        assertFalse(snapshot.trackCategories.any { it.id == "meal" })
    }

    @Test fun everyActivityTakesItsGroupsColor() {
        assertTrue(BlockCategories.defaults.all { (it.group?.color ?: it.color) == it.color })
    }
}
