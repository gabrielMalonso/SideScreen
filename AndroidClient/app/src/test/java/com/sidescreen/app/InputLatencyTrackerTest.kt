package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Test

class InputLatencyTrackerTest {
    @Test
    fun tracksLastAverageAndP95() {
        val tracker = InputLatencyTracker(maxSamples = 10)

        listOf(10.0, 20.0, 30.0, 40.0).forEach { tracker.add(it) }
        val stats = tracker.add(50.0)

        assertEquals(50.0, stats.lastMs, 0.001)
        assertEquals(30.0, stats.averageMs, 0.001)
        assertEquals(40.0, stats.p95Ms, 0.001)
        assertEquals(5, stats.sampleCount)
    }

    @Test
    fun keepsOnlyRecentSamples() {
        val tracker = InputLatencyTracker(maxSamples = 3)

        tracker.add(10.0)
        tracker.add(20.0)
        tracker.add(30.0)
        val stats = tracker.add(40.0)

        assertEquals(40.0, stats.lastMs, 0.001)
        assertEquals(30.0, stats.averageMs, 0.001)
        assertEquals(30.0, stats.p95Ms, 0.001)
        assertEquals(3, stats.sampleCount)
    }
}
