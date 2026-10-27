package dev.timeblock.core

import kotlinx.serialization.Serializable

/** A platform-neutral color, so the model layer can grade colors without a UI toolkit. */
@Serializable
data class RGB(val r: Double, val g: Double, val b: Double) {
    val luminance: Double get() = 0.2126 * r + 0.7152 * g + 0.0722 * b

    fun mixed(other: RGB, amount: Double): RGB =
        RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)

    fun desaturated(amount: Double): RGB {
        val l = luminance
        return mixed(RGB(l, l, l), amount)
    }

    /** As 0xRRGGBB. */
    val hex: Int
        get() = (Math.round(r * 255).toInt() shl 16) or (Math.round(g * 255).toInt() shl 8) or Math.round(b * 255).toInt()

    companion object {
        fun hex(hex: Int) = RGB(
            ((hex shr 16) and 0xFF) / 255.0,
            ((hex shr 8) and 0xFF) / 255.0,
            (hex and 0xFF) / 255.0,
        )
    }
}
