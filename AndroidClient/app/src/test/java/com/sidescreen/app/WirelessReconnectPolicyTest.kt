package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WirelessReconnectPolicyTest {
    @Test
    fun delayScheduleIsShortBoundedAndPredictable() {
        assertEquals(4, WirelessReconnectPolicy.maxAttempts)
        assertEquals(1_000L, WirelessReconnectPolicy.delayForAttempt(1))
        assertEquals(2_000L, WirelessReconnectPolicy.delayForAttempt(2))
        assertEquals(5_000L, WirelessReconnectPolicy.delayForAttempt(3))
        assertEquals(10_000L, WirelessReconnectPolicy.delayForAttempt(4))
    }

    @Test
    fun attemptsOutsideScheduleAreRejected() {
        assertNull(WirelessReconnectPolicy.delayForAttempt(0))
        assertNull(WirelessReconnectPolicy.delayForAttempt(5))
    }
}
