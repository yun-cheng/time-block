package dev.timeblock.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.util.UUID

/**
 * What kind of time an activity is. Each group owns a hue, and every activity in it shares that color, so a day reads
 * as a story at a glance however finely it was logged: blue work, violet learning, green health, pink people, orange
 * running your life, teal transit, yellow leisure, and dull plum for time that drifted away. Groups you add pick their
 * own name and color.
 */
@Serializable
data class CategoryGroup(val id: String, val name: String, val color: RGB) {
    val isBuiltIn: Boolean get() = builtIn.any { it.id == id }

    companion object {
        val work = CategoryGroup("work", "Work", RGB.hex(0x2F6BFF))
        val learn = CategoryGroup("learn", "Learn", RGB.hex(0xB45CF0))
        val health = CategoryGroup("health", "Health", RGB.hex(0x22C55E))
        val people = CategoryGroup("people", "People", RGB.hex(0xF0508C))
        val life = CategoryGroup("life", "Life", RGB.hex(0xFF8A3D))
        val transit = CategoryGroup("transit", "Transit", RGB.hex(0x14B8A6))
        val leisure = CategoryGroup("leisure", "Leisure", RGB.hex(0xFACC15))
        val drift = CategoryGroup("drift", "Drift", RGB.hex(0x8E6A9E))

        /** The groups every library starts with, in order. Your own come after them. */
        val builtIn = listOf(work, learn, health, people, life, transit, leisure, drift)

        private val legacy = mapOf("focus" to "work", "fuel" to "life", "body" to "health", "recharge" to "leisure")

        /** The built-in group with [id], or with the id it had before groups were renamed. */
        fun builtIn(id: String): CategoryGroup? {
            val current = legacy[id] ?: id
            return builtIn.firstOrNull { it.id == current }
        }

        /** Colors for your own groups, picked in turn, away from the built-in hues and from overtime red. */
        val ownColors = listOf(0x8B95A7, 0xA0673A, 0x84CC16, 0x38BDF8, 0xD946EF, 0x6366F1).map(RGB::hex)

        /** A group the user adds, ready to be named. */
        fun new(color: RGB, name: String = "New group") =
            CategoryGroup("group-${UUID.randomUUID().toString().uppercase()}", name, color)
    }
}

/**
 * One way of looking at the day. Each track is logged apart, so 10:00 can be Work in Activity and Standing in Body at
 * the same time. The app shows one track at a time.
 */
@Serializable
enum class Track(val title: String, val symbol: String) {
    /** What you were doing. */
    @SerialName("activity") ACTIVITY("Activity", "square.grid.3x3.fill"),

    /** What your body was doing: lying, sitting, standing, walking, exercising. */
    @SerialName("body") BODY("Body", "figure.walk"),
}

/**
 * Something a block can be logged as: in Activity, a detailed activity such as Lunch or Email; in Body, a posture such
 * as Sitting. [symbol] is an SF Symbol name, which the Android app maps to an icon of its own.
 */
@Serializable(with = BlockCategorySerializer::class)
data class BlockCategory(
    val id: String,
    val name: String,
    val track: Track,
    /** Activities belong to a group, which sets their color and how time is summed up. Categories in other tracks
     *  have none and are summed up one by one. */
    val group: CategoryGroup?,
    val color: RGB,
    val symbol: String,
    /** Other words search should find it by, such as "meal" for Lunch. */
    val keywords: List<String> = emptyList(),
    /** Whether you removed it (see [AppSettings.removedCategories]). Not saved with it: settings keep the list. */
    val isRemoved: Boolean = false,
) {
    /** In [group], taking its color. */
    fun withGroup(group: CategoryGroup?): BlockCategory = copy(group = group, color = group?.color ?: color)

    /** Whether this is retired, by the app (a built-in activity no longer offered) or by you (removed): it shows on old
     *  blocks but can't be logged again. */
    val isRetired: Boolean get() = isRemoved || BlockCategories.retired.any { it.id == id }

    companion object {
        /** An Activity, in its group's color. */
        fun activity(id: String, name: String, group: CategoryGroup, symbol: String, keywords: List<String> = emptyList()) =
            BlockCategory(id, name, Track.ACTIVITY, group, group.color, symbol, keywords)

        /** An activity the user adds, ready to be named. */
        fun new(track: Track, group: CategoryGroup = CategoryGroup.life, name: String = "New activity"): BlockCategory {
            val id = "custom-${UUID.randomUUID().toString().uppercase()}"
            return when (track) {
                Track.ACTIVITY -> activity(id, name, group, "star.fill")
                Track.BODY -> BlockCategory(id, name, track, null, RGB.hex(0x8A8F98), "star.fill")
            }
        }
    }
}

/** A category as it's saved: its group by id alone. */
@Serializable
private class SavedCategory(
    val id: String,
    val name: String,
    val track: Track,
    val group: String? = null,
    val color: RGB? = null,
    val symbol: String,
    val keywords: List<String> = emptyList(),
)

object BlockCategorySerializer : KSerializer<BlockCategory> {
    override val descriptor = SavedCategory.serializer().descriptor

    override fun serialize(encoder: Encoder, value: BlockCategory) {
        encoder.encodeSerializableValue(
            SavedCategory.serializer(),
            SavedCategory(value.id, value.name, value.track, value.group?.id, value.color, value.symbol, value.keywords))
    }

    override fun deserialize(decoder: Decoder): BlockCategory {
        val saved = decoder.decodeSerializableValue(SavedCategory.serializer())
        // Only the group's id is saved. One of your own stands in as a placeholder until `AppSettings` finds it.
        val group = saved.group?.let { CategoryGroup.builtIn(it) ?: CategoryGroup(it, "", CategoryGroup.life.color) }
        // Activities used to pick a shade; they now all take their group's color.
        val color = group?.color ?: saved.color ?: throw SerializationException("Category ${saved.id} has no color")
        return BlockCategory(saved.id, saved.name, saved.track, group, color, saved.symbol, saved.keywords)
    }
}

/**
 * A run of blocks given to one category. Logs of one track can overlap: a block can hold several activities at once
 * (see [DayGrid.cells] for which is on top).
 */
@Serializable
data class BlockLog(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val startIndex: Int,
    val length: Int,
    val categoryID: String,
    val note: String? = null,
    val source: Source = Source.MANUAL,
    /** The template that pre-logged it, so laying that one out again finds its own blocks. */
    val templateID: String? = null,
) {
    @Serializable
    enum class Source {
        @SerialName("manual") MANUAL,

        /** A recurring pre-log such as a meal. */
        @SerialName("template") TEMPLATE,

        @SerialName("calendar") CALENDAR,
    }

    val range: Span get() = Span.of(startIndex, length)
}

/** One block as the UI draws it. */
data class BlockCell(
    val index: Int,
    val phase: Phase,
    val isOvertime: Boolean,
    /** Whether it's one of the blocks before bedtime set aside to wind down. */
    val isWindDown: Boolean,
    /** What it holds, bottom first (see [DayGrid.cells] for the order). Empty when it's unlogged. */
    val layers: List<Layer> = emptyList(),
) {
    enum class Phase { PAST, CURRENT, FUTURE }

    /** One of the activities a block holds at once. */
    data class Layer(
        val categoryID: String,
        val source: BlockLog.Source = BlockLog.Source.MANUAL,
        val note: String? = null,
    )

    /** The activity on top. */
    val categoryID: String? get() = layers.lastOrNull()?.categoryID
    val source: BlockLog.Source? get() = layers.lastOrNull()?.source
    val note: String? get() = layers.lastOrNull()?.note

    /** Every activity it holds, bottom first. */
    val categoryIDs: List<String> get() = layers.map { it.categoryID }

    /** The layer of [categoryID], when it holds it. */
    fun layer(categoryID: String): Layer? = layers.firstOrNull { it.categoryID == categoryID }

    /** The same block holding [layers]: what an edit would make it. */
    fun holding(layers: List<Layer>): BlockCell = copy(layers = layers)

    /** The same block logged by hand as [categoryID] alone, or emptied with null. */
    fun logged(categoryID: String?): BlockCell = holding(categoryID?.let { listOf(Layer(it)) } ?: emptyList())
}

object DayGrid {
    /**
     * One cell per block from wake time to bedtime, plus any overtime already started.
     *
     * Logs that overlap are layers, and what breaks into something else goes on top: in each block, the activity whose
     * unbroken stretch is shortest, so a trip to the toilet sits on a morning of work, a podcast on a commute and
     * dinner on an evening of TV. Of stretches as long, the one starting later broke in; of those, the one logged last
     * is on top. A stretch is measured whole, so two activities keep one order in every block they share.
     */
    fun cells(status: DayStatus, logs: List<BlockLog>): List<BlockCell> {
        class Placed(val layer: BlockCell.Layer, val order: Int)

        val layersAt = HashMap<Int, MutableList<Placed>>()
        val held = HashMap<String, MutableSet<Int>>()
        logs.forEachIndexed { order, log ->
            val layer = BlockCell.Layer(log.categoryID, log.source, log.note)
            for (index in log.range) layersAt.getOrPut(index) { mutableListOf() }.add(Placed(layer, order))
            held.getOrPut(log.categoryID) { mutableSetOf() }.addAll(log.range)
        }

        /** The unbroken stretch of [categoryID] that block [index] is in. */
        fun stretch(categoryID: String, index: Int): Span {
            val blocks = held[categoryID] ?: emptySet()
            var start = index
            var end = index + 1
            while (start - 1 in blocks) start -= 1
            while (end in blocks) end += 1
            return Span(start, end)
        }

        val current = status.currentIndex ?: if (status.isOver) status.visibleBlocks else -1
        val windDown = status.windDownRange
        return (0 until status.visibleBlocks).map { index ->
            val phase = when {
                index < current -> BlockCell.Phase.PAST
                index == current -> BlockCell.Phase.CURRENT
                else -> BlockCell.Phase.FUTURE
            }
            val layers = (layersAt[index] ?: emptyList()).sortedWith { lower, upper ->
                val a = stretch(lower.layer.categoryID, index)
                val b = stretch(upper.layer.categoryID, index)
                when {
                    a.count != b.count -> b.count.compareTo(a.count)
                    a.lowerBound != b.lowerBound -> a.lowerBound.compareTo(b.lowerBound)
                    else -> lower.order.compareTo(upper.order)
                }
            }
            BlockCell(
                index, phase, isOvertime = index >= status.schedule.awakeBlocks, isWindDown = index in windDown,
                layers = layers.map { it.layer })
        }
    }
}
