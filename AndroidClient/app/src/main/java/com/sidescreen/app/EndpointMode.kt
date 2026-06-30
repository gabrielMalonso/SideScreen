package com.sidescreen.app

enum class EndpointMode {
    LAN,
    TAILNET,
    MANUAL,
    ;

    val isTailnet: Boolean
        get() = this == TAILNET

    companion object {
        fun fromWire(value: String?): EndpointMode =
            when (value?.lowercase()) {
                "tailnet" -> TAILNET
                "manual" -> MANUAL
                else -> LAN
            }
    }
}

