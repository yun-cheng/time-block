package dev.timeblock.core

/** A run of blocks from [lowerBound] up to but not including [upperBound], as Swift's `Range<Int>`. */
data class Span(val lowerBound: Int, val upperBound: Int) : Iterable<Int> {
    init {
        require(lowerBound <= upperBound) { "Span $lowerBound..<$upperBound runs backwards" }
    }

    val count: Int get() = upperBound - lowerBound
    val isEmpty: Boolean get() = upperBound == lowerBound

    operator fun contains(index: Int): Boolean = index in lowerBound until upperBound

    /** Whether every block of [other] is in this one; an empty one always is. */
    operator fun contains(other: Span): Boolean =
        other.isEmpty || (lowerBound <= other.lowerBound && other.upperBound <= upperBound)

    fun overlaps(other: Span): Boolean =
        !isEmpty && !other.isEmpty && lowerBound < other.upperBound && other.lowerBound < upperBound

    /** This run cut to [limits]. */
    fun clamped(limits: Span): Span = Span(
        lowerBound.coerceIn(limits.lowerBound, limits.upperBound),
        upperBound.coerceIn(limits.lowerBound, limits.upperBound),
    )

    /** The same length, [offset] blocks along. */
    fun shifted(offset: Int): Span = Span(lowerBound + offset, upperBound + offset)

    override fun iterator(): Iterator<Int> = (lowerBound until upperBound).iterator()

    override fun toString(): String = "$lowerBound..<$upperBound"

    companion object {
        val empty = Span(0, 0)

        /** The blocks [length] long from [start]. */
        fun of(start: Int, length: Int) = Span(start, start + length)
    }
}

/** Blocks from this one up to but not including [to]: Swift's `..<`. */
infix fun Int.upTo(to: Int): Span = Span(this, to)
