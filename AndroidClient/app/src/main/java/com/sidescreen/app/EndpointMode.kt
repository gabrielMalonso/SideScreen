package com.sidescreen.app

enum class EndpointMode {
    LAN,
    TAILNET,
    MANUAL,
    ;

    val isTailnet: Boolean
        get() = this == TAILNET

    val shouldBindWifi: Boolean
        get() = this == LAN

    val displayName: String
        get() =
            when (this) {
                LAN -> "LAN"
                TAILNET -> "Tailnet"
                MANUAL -> "Manual"
            }

    val routeDescription: String
        get() =
            when (this) {
                LAN -> "LAN mode binds sockets to Wi-Fi when Android exposes a Wi-Fi route."
                TAILNET -> "Tailnet mode uses Android's default VPN route; Wi-Fi binding stays off."
                MANUAL -> "Manual mode uses Android's default route for the host you entered."
            }

    val failureChecklist: String
        get() =
            when (this) {
                LAN ->
                    "Check that the Mac and tablet are on the same Wi-Fi, the Mac app is running, and the firewall allows the selected port."
                TAILNET ->
                    "Check Tailscale on both devices, make sure Remote Mac is not excluded from split tunneling, and try switching between MagicDNS and the Mac's 100.x Tailnet IP."
                MANUAL ->
                    "Check that the host and port are reachable from Android, then scan a fresh QR if the Mac settings changed."
            }

    companion object {
        fun fromWire(value: String?): EndpointMode =
            when (value?.lowercase()) {
                "tailnet" -> TAILNET
                "manual" -> MANUAL
                else -> LAN
            }
    }
}
