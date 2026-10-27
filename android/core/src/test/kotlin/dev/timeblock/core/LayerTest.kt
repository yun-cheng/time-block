package dev.timeblock.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Several activities in one block at once. */
class LayerTest {
    /** 07:00–23:00. */
    private val hours = Schedule.standard
    private val activity = Track.ACTIVITY

    private fun log(steps: DayLog.() -> DayLog): DayLog = DayLog("2026-10-24", hours.wakeMinute).steps()

    private fun DayLog.set(range: Span, to: String?, layer: String? = null) = set(range, to, activity, hours, layer = layer)
    private fun DayLog.toggle(categoryID: String, range: Span) = toggle(categoryID, range, hours)

    private fun snapshot(log: DayLog) =
        DaySnapshot(DayStatus(hours, 12 * 60), log.logs(hours), BlockCategories.defaults)

    @Test fun anAddedActivityGoesOnTopOfWhatTheBlocksHold() {
        val cells = snapshot(log { set(0 upTo 10, "work").toggle("email", 4 upTo 6) }).cells
        assertEquals(listOf("work"), cells[3].categoryIDs)
        assertEquals(listOf("work", "email"), cells[4].categoryIDs)
        assertEquals("email", cells[5].categoryID)
        assertEquals(listOf("work"), cells[6].categoryIDs)
    }

    @Test fun theRunUnderneathStaysWhole() {
        val log = log { set(0 upTo 10, "work").toggle("email", 4 upTo 6) }
        assertEquals(listOf(0 upTo 10, 4 upTo 6), log.logs.map { it.range })
    }

    @Test fun addingWhatEveryBlockHoldsTakesItOff() {
        val cells = snapshot(log {
            set(0 upTo 10, "work").toggle("email", 4 upTo 6).toggle("email", 4 upTo 6)
                // Taking off the one underneath leaves the rest.
                .toggle("email", 2 upTo 4).toggle("work", 0 upTo 10)
        }).cells
        assertEquals(emptyList(), cells[1].categoryIDs)
        assertEquals(listOf("email"), cells[2].categoryIDs)
        assertEquals(emptyList(), cells[4].categoryIDs)
    }

    @Test fun addingWhatSomeBlocksHoldSpreadsItAndPutsItOnTop() {
        val log = log { toggle("email", 4 upTo 6).toggle("work", 0 upTo 10).toggle("email", 2 upTo 6) }
        assertEquals(listOf("work 0..<10", "email 2..<6"), log.logs.map { "${it.categoryID} ${it.range}" })
        assertEquals(listOf("work", "email"), snapshot(log).cells[4].categoryIDs)
    }

    @Test fun aClickedActivityReplacesEveryLayer() {
        val cells = snapshot(log { set(0 upTo 10, "work").toggle("email", 4 upTo 6).set(3 upTo 7, "lunch") }).cells
        assertEquals(listOf("work"), cells[2].categoryIDs)
        assertTrue((3 upTo 7).all { cells[it].categoryIDs == listOf("lunch") })
        assertEquals(listOf("work"), cells[7].categoryIDs)
    }

    @Test fun aRunIsBlocksHoldingTheSameActivities() {
        val snapshot = snapshot(log { set(0 upTo 10, "work").toggle("email", 4 upTo 6) })
        assertEquals(0 upTo 4, snapshot.run(1))
        assertEquals(4 upTo 6, snapshot.run(5))
        assertEquals(6 upTo 10, snapshot.run(8))
    }

    @Test fun eachActivityCountsItsFullTime() {
        val snapshot = snapshot(log {
            set(0 upTo 12, "work").toggle("lunch", 6 upTo 12)
                // Two of one group in a block count once for it.
                .toggle("meeting", 0 upTo 6)
        })
        assertEquals(listOf("Work 12", "Life 6"), snapshot.legendTotals.map { "${it.name} ${it.blocks}" })
        assertEquals(12, snapshot.loggedCount)
        assertEquals(12, snapshot.longestRun("work"))
    }

    @Test fun totalsAsLargeKeepTheDaysOrder() {
        // A tie whose order changed between drawings made the day's bar flicker.
        val snapshot = snapshot(log { set(0 upTo 2, "walk").set(2 upTo 4, "coding").set(4 upTo 6, "lunch") })
        assertEquals(listOf("Health", "Work", "Life"), snapshot.legendTotals.map { it.name })
    }

    @Test fun movingTakesEveryLayerAlong() {
        val cells = snapshot(log {
            set(0 upTo 4, "work").toggle("email", 2 upTo 4).move(0 upTo 4, 10, activity, hours)
        }).cells
        assertEquals(emptyList(), cells[0].categoryIDs)
        assertEquals(listOf("work"), cells[10].categoryIDs)
        assertEquals(listOf("work", "email"), cells[12].categoryIDs)
    }

    @Test fun layersKeepTheirOrderThroughASaveAndLoad() {
        // Even in every way, the one logged last is on top.
        val log = log { toggle("email", 4 upTo 6).toggle("work", 4 upTo 6) }
        val loaded = TimeBlockJson.decodeFromString(
            DayLog.serializer(), TimeBlockJson.encodeToString(DayLog.serializer(), log))
        assertEquals(listOf("email", "work"), snapshot(loaded).cells[4].categoryIDs)
    }

    // What's on top

    @Test fun theShortStretchGoesOnTopWhateverWasLoggedFirst() {
        // A trip to the toilet in a morning of work, logged before the work.
        val cells = snapshot(log { toggle("bathroom", 18 upTo 19).toggle("work", 12 upTo 48) }).cells
        assertEquals(listOf("work", "bathroom"), cells[18].categoryIDs)
    }

    @Test fun dinnerSitsOnAnEveningOfTV() {
        val cells = snapshot(log { toggle("dinner", 6 upTo 15).toggle("shows", 0 upTo 30) }).cells
        assertTrue((6 upTo 15).all { cells[it].categoryIDs == listOf("shows", "dinner") })
    }

    @Test fun ofStretchesAsLongTheOneStartingLaterBrokeIn() {
        val cells = snapshot(log { toggle("email", 3 upTo 9).toggle("work", 0 upTo 6) }).cells
        assertEquals(listOf("work", "email"), cells[4].categoryIDs)
    }

    @Test fun twoActivitiesKeepOneOrderInEveryBlockTheyShare() {
        // Lunch is shorter than Social as a whole, though Social is shorter where they meet.
        val cells = snapshot(log { toggle("social", 4 upTo 14).toggle("lunch", 0 upTo 6) }).cells
        assertEquals(listOf("social", "lunch"), cells[4].categoryIDs)
        assertEquals(listOf("social", "lunch"), cells[5].categoryIDs)
    }

    // One layer picked out

    /** Commute 0..<6 with Podcast over 2..<6. */
    private fun commute(edit: DayLog.() -> DayLog = { this }) =
        snapshot(log { set(0 upTo 6, "commute").toggle("podcast", 2 upTo 6).edit() })

    @Test fun aLayersRunFollowsItsActivityThroughTheStack() {
        val snapshot = commute()
        assertEquals(0 upTo 6, snapshot.layerRun(3, "commute"))
        assertEquals(2 upTo 6, snapshot.layerRun(3, "podcast"))
    }

    @Test fun replacingALayerLeavesTheRest() {
        val cells = commute { set(2 upTo 6, "music", layer = "podcast") }.cells
        assertEquals(listOf("commute", "music"), cells[3].categoryIDs)
        assertEquals(listOf("commute"), cells[0].categoryIDs)
    }

    @Test fun clearingALayerLeavesTheRest() {
        val cells = commute { set(0 upTo 6, null, layer = "commute") }.cells
        assertEquals(emptyList(), cells[0].categoryIDs)
        assertEquals(listOf("podcast"), cells[3].categoryIDs)
    }

    @Test fun aLayerMovesOnTopOfWhereItLands() {
        val cells = commute { move(2 upTo 6, -2, activity, hours, layer = "podcast") }.cells
        assertEquals(listOf("commute", "podcast"), cells[0].categoryIDs)
        assertEquals(listOf("commute"), cells[5].categoryIDs)
    }

    @Test fun aLayerResizesWithoutTouchingTheRest() {
        val cells = commute { resize(2 upTo 6, 1 upTo 4, activity, hours, layer = "podcast") }.cells
        assertEquals(listOf("commute"), cells[0].categoryIDs)
        assertEquals(listOf("commute", "podcast"), cells[1].categoryIDs)
        assertEquals(listOf("commute"), cells[4].categoryIDs)
    }

    @Test fun aNoteGoesOnTheLayerItsWrittenFor() {
        val cells = commute { setNote("Hard Fork", 2 upTo 6, activity, hours, layer = "podcast") }.cells
        assertEquals("Hard Fork", cells[3].layer("podcast")?.note)
        assertNull(cells[3].layer("commute")?.note)
    }

    @Test fun pointingAtAnActivityTakesInItsBlocksUnderOthers() {
        val snapshot = commute()
        // Commute alone at 0, but it runs on under Podcast: all of it, just Commute.
        assertEquals(Target(0 upTo 6, "commute"), snapshot.target(0))
        // On top at 3 is Podcast; its card under it is Commute.
        assertEquals(Target(2 upTo 6, "podcast"), snapshot.target(3))
        assertEquals(Target(0 upTo 6, "commute"), snapshot.target(3, card = "commute"))
        // Nothing stacked: the run, everything it holds.
        val work = commute { set(10 upTo 14, "work") }
        assertEquals(Target(10 upTo 14, null), work.target(11))
    }

    @Test fun clearingTakesTheActivityPointedAt() {
        val snapshot = commute()
        assertEquals(Target(0 upTo 6, "commute"), snapshot.clearable(0))
        assertEquals(Target(2 upTo 4, "podcast"), snapshot.clearable(3, selection = 2 upTo 4, selectedLayer = "podcast"))
    }
}
