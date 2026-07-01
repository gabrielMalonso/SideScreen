package com.sidescreen.app

object RemoteInputPorts {
    const val MIN_VIDEO_PORT = 1
    const val MAX_VIDEO_PORT = 65534

    fun isValidVideoPort(videoPort: Int): Boolean = videoPort in MIN_VIDEO_PORT..MAX_VIDEO_PORT

    fun inputPortFor(videoPort: Int): Int {
        require(isValidVideoPort(videoPort)) {
            "video port must be $MIN_VIDEO_PORT..$MAX_VIDEO_PORT so input can use port + 1"
        }
        return videoPort + 1
    }
}
