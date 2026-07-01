package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EndpointModeTest {
    @Test
    fun parsesLegacyAsLanAndTailnetExplicitly() {
        assertEquals(EndpointMode.LAN, EndpointMode.fromWire(null))
        assertEquals(EndpointMode.LAN, EndpointMode.fromWire("lan"))
        assertEquals(EndpointMode.TAILNET, EndpointMode.fromWire("tailnet"))
        assertEquals(EndpointMode.MANUAL, EndpointMode.fromWire("manual"))
    }

    @Test
    fun bindsWifiOnlyForLan() {
        assertTrue(EndpointMode.LAN.shouldBindWifi)
        assertFalse(EndpointMode.TAILNET.shouldBindWifi)
        assertFalse(EndpointMode.MANUAL.shouldBindWifi)
    }

    @Test
    fun inputPortUsesNextPortWithoutOverflow() {
        assertEquals(54322, RemoteInputPorts.inputPortFor(54321))
        assertEquals(65535, RemoteInputPorts.inputPortFor(65535))
    }
}
