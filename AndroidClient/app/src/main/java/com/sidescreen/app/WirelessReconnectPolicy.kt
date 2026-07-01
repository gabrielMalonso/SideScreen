package com.sidescreen.app

object WirelessReconnectPolicy {
    private val delaysMs = longArrayOf(1_000L, 2_000L, 5_000L, 10_000L)

    val maxAttempts: Int
        get() = delaysMs.size

    fun delayForAttempt(attempt: Int): Long? =
        if (attempt in 1..delaysMs.size) delaysMs[attempt - 1] else null
}
