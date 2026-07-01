package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DisplayControlMessageTest {
    @Test
    fun displayListRoundTrips() {
        val message =
            DisplayControlMessage.DisplayList(
                selectedDisplayId = 2,
                displays =
                    listOf(
                        RemoteDisplay(
                            id = 1,
                            name = "Main Display",
                            isMain = true,
                            width = 3024,
                            height = 1964,
                            scale = 2.0,
                        ),
                        RemoteDisplay(
                            id = 2,
                            name = "Studio Display",
                            isMain = false,
                            width = 5120,
                            height = 2880,
                            scale = 2.0,
                        ),
                    ),
            )

        val decoded = DisplayControlCodec.decode(DisplayControlCodec.encode(message))

        assertEquals(message, decoded)
    }

    @Test
    fun selectDisplayResultReportsOk() {
        val decoded =
            DisplayControlCodec.decode(
                DisplayControlCodec.encode(
                    DisplayControlMessage.SelectDisplayResult(
                        displayId = 7,
                        status = DisplayControlMessage.STATUS_OK,
                    ),
                ),
            )

        assertTrue((decoded as DisplayControlMessage.SelectDisplayResult).ok)
    }
}
