package com.sidescreen.app

data class InputLatencyStats(
    val lastMs: Double,
    val averageMs: Double,
    val p95Ms: Double,
    val sampleCount: Int,
) {
    fun summary(): String =
        "input ${"%.1f".format(lastMs)} ms · avg ${"%.1f".format(averageMs)} · p95 ${"%.1f".format(p95Ms)}"
}

class InputLatencyTracker(
    private val maxSamples: Int = 60,
) {
    private val samples = ArrayDeque<Double>()

    @Synchronized
    fun add(sampleMs: Double): InputLatencyStats {
        samples.addLast(sampleMs.coerceAtLeast(0.0))
        while (samples.size > maxSamples) {
            samples.removeFirst()
        }
        return snapshotLocked()
    }

    @Synchronized
    fun reset() {
        samples.clear()
    }

    private fun snapshotLocked(): InputLatencyStats {
        val ordered = samples.sorted()
        val average = samples.sum() / samples.size
        val p95Index = ((ordered.size - 1) * 0.95).toInt().coerceIn(0, ordered.lastIndex)
        return InputLatencyStats(
            lastMs = samples.last(),
            averageMs = average,
            p95Ms = ordered[p95Index],
            sampleCount = samples.size,
        )
    }
}
