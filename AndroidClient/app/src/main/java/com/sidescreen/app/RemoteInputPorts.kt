package com.sidescreen.app

object RemoteInputPorts {
    fun inputPortFor(videoPort: Int): Int = (videoPort + 1).coerceAtMost(65535)
}
