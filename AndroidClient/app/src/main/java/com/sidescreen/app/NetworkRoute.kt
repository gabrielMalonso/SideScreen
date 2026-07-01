package com.sidescreen.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

object NetworkRoute {
    fun describeCurrentRoute(
        context: Context?,
        endpointMode: EndpointMode,
    ): String {
        val cm = context?.getSystemService(ConnectivityManager::class.java)
            ?: return "${endpointMode.routeDescription} · route unknown"
        val capabilities = cm.activeNetwork?.let(cm::getNetworkCapabilities)
            ?: return "${endpointMode.routeDescription} · no active network"
        val transports = buildList {
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) add("VPN")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) add("Wi-Fi")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) add("cellular")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) add("ethernet")
        }.ifEmpty { listOf("unknown transport") }
        val validation =
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                "validated"
            } else {
                "not validated"
            }
        val route = "${endpointMode.routeDescription} · active ${transports.joinToString("+")} · $validation"
        return if (endpointMode == EndpointMode.TAILNET && !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            "$route · Tailscale VPN not active for this app"
        } else {
            route
        }
    }

    fun bindWifiIfNeeded(
        context: Context?,
        endpointMode: EndpointMode,
        socket: Socket,
        channelName: String,
        log: (String) -> Unit,
    ) {
        if (!endpointMode.shouldBindWifi) {
            log("$endpointMode $channelName using default route")
            return
        }

        val wifiNetwork = context?.let(::findWifiNetwork)
        if (wifiNetwork != null) {
            log("LAN $channelName binding socket to WiFi")
            wifiNetwork.bindSocket(socket)
        } else {
            log("LAN $channelName using default route")
        }
    }

    private fun findWifiNetwork(context: Context): Network? {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val activeNetwork = cm.activeNetwork
        if (activeNetwork != null && cm.getNetworkCapabilities(activeNetwork).isUsableWifi()) {
            return activeNetwork
        }
        return awaitWifiNetwork(cm)
    }

    private fun awaitWifiNetwork(cm: ConnectivityManager): Network? {
        val found = AtomicReference<Network?>()
        val latch = CountDownLatch(1)
        val request =
            NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
        val callback =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    if (found.compareAndSet(null, network)) {
                        latch.countDown()
                    }
                }
            }

        return try {
            cm.registerNetworkCallback(request, callback)
            latch.await(WIFI_LOOKUP_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            found.get()
        } catch (_: RuntimeException) {
            null
        } finally {
            try {
                cm.unregisterNetworkCallback(callback)
            } catch (_: RuntimeException) {
            }
        }
    }

    private fun NetworkCapabilities?.isUsableWifi(): Boolean =
        this?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
            hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)

    private const val WIFI_LOOKUP_TIMEOUT_MS = 350L
}
