package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
        assertEquals(65535, RemoteInputPorts.inputPortFor(65534))
        assertFalse(RemoteInputPorts.isValidVideoPort(65535))
        try {
            RemoteInputPorts.inputPortFor(65535)
            throw AssertionError("Expected port 65535 to be rejected")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("1..65534"))
        }
    }

    @Test
    fun pairingUrlRejectsVideoPortWithoutInputCompanionPort() {
        val token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        assertNull(PairingURL.parse("sidescreen://mac.example.ts.net:65535?t=$token&name=Mac&mode=tailnet"))
    }
}
