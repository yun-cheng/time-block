package dev.timeblock.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant

/**
 * JSON as the Swift app writes it, so either reads what the other saved: every key written, defaults too, since Swift
 * requires them; nothing written for null, as Swift leaves them out; keys it doesn't know skipped.
 */
val TimeBlockJson = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
}

/** A moment as Swift's `JSONEncoder` writes a `Date`: seconds since the start of 2001, UTC. */
object AppleDateSerializer : KSerializer<Instant> {
    private val referenceDate: Instant = Instant.parse("2001-01-01T00:00:00Z")

    override val descriptor = PrimitiveSerialDescriptor("dev.timeblock.AppleDate", PrimitiveKind.DOUBLE)

    override fun serialize(encoder: Encoder, value: Instant) {
        encoder.encodeDouble(seconds(value))
    }

    override fun deserialize(decoder: Decoder): Instant = instant(decoder.decodeDouble())

    fun seconds(instant: Instant): Double =
        (instant.epochSecond - referenceDate.epochSecond) + instant.nano / 1_000_000_000.0

    fun instant(seconds: Double): Instant {
        val whole = Math.floor(seconds)
        return referenceDate.plusSeconds(whole.toLong()).plusNanos(((seconds - whole) * 1_000_000_000).toLong())
    }
}

/** Seconds between two moments, as Swift's `timeIntervalSince`. */
fun Instant.secondsSince(other: Instant): Double =
    (epochSecond - other.epochSecond) + (nano - other.nano) / 1_000_000_000.0

/** This moment [seconds] later. */
fun Instant.plusSeconds(seconds: Double): Instant =
    plusNanos(Math.round(seconds * 1_000_000_000))
