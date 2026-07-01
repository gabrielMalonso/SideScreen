package com.sidescreen.app

import org.json.JSONArray
import org.json.JSONObject

data class RemoteDisplay(
    val id: Long,
    val name: String,
    val isMain: Boolean,
    val width: Int,
    val height: Int,
    val scale: Double,
) {
    val label: String
        get() = "$name · ${width}x$height"
}

sealed class DisplayControlMessage {
    data object RequestDisplayList : DisplayControlMessage()

    data class DisplayList(
        val selectedDisplayId: Long,
        val displays: List<RemoteDisplay>,
    ) : DisplayControlMessage()

    data class SelectDisplay(
        val displayId: Long,
    ) : DisplayControlMessage()

    data class SelectDisplayResult(
        val displayId: Long,
        val status: String,
        val message: String? = null,
    ) : DisplayControlMessage() {
        val ok: Boolean
            get() = status == STATUS_OK
    }

    companion object {
        const val STATUS_OK = "ok"
        const val STATUS_ERROR = "error"
    }
}

object DisplayControlCodec {
    const val MAX_PAYLOAD_BYTES = 64 * 1024

    fun encode(message: DisplayControlMessage): ByteArray {
        val json =
            when (message) {
                DisplayControlMessage.RequestDisplayList ->
                    JSONObject().put("type", "requestDisplayList")
                is DisplayControlMessage.DisplayList ->
                    JSONObject()
                        .put("type", "displayList")
                        .put("selectedDisplayId", message.selectedDisplayId)
                        .put(
                            "displays",
                            JSONArray().also { array ->
                                message.displays.forEach { display ->
                                    array.put(
                                        JSONObject()
                                            .put("id", display.id)
                                            .put("name", display.name)
                                            .put("isMain", display.isMain)
                                            .put("width", display.width)
                                            .put("height", display.height)
                                            .put("scale", display.scale),
                                    )
                                }
                            },
                        )
                is DisplayControlMessage.SelectDisplay ->
                    JSONObject()
                        .put("type", "selectDisplay")
                        .put("displayId", message.displayId)
                is DisplayControlMessage.SelectDisplayResult ->
                    JSONObject()
                        .put("type", "selectDisplayResult")
                        .put("displayId", message.displayId)
                        .put("status", message.status)
                        .apply {
                            message.message?.let { put("message", it) }
                        }
            }
        return json.toString().toByteArray(Charsets.UTF_8).also { payload ->
            require(payload.size <= MAX_PAYLOAD_BYTES) { "display control payload too large" }
        }
    }

    fun decode(payload: ByteArray): DisplayControlMessage {
        require(payload.size <= MAX_PAYLOAD_BYTES) { "display control payload too large" }
        val json = JSONObject(payload.toString(Charsets.UTF_8))
        return when (val type = json.getString("type")) {
            "requestDisplayList" -> DisplayControlMessage.RequestDisplayList
            "displayList" -> {
                val displaysJson = json.getJSONArray("displays")
                val displays =
                    buildList {
                        for (index in 0 until displaysJson.length()) {
                            val display = displaysJson.getJSONObject(index)
                            add(
                                RemoteDisplay(
                                    id = display.getLong("id"),
                                    name = display.getString("name"),
                                    isMain = display.optBoolean("isMain", false),
                                    width = display.getInt("width"),
                                    height = display.getInt("height"),
                                    scale = display.optDouble("scale", 1.0),
                                ),
                            )
                        }
                    }
                require(displays.isNotEmpty()) { "displayList requires at least one display" }
                DisplayControlMessage.DisplayList(
                    selectedDisplayId = json.getLong("selectedDisplayId"),
                    displays = displays,
                )
            }
            "selectDisplay" ->
                DisplayControlMessage.SelectDisplay(json.getLong("displayId"))
            "selectDisplayResult" -> {
                val status = json.getString("status")
                require(status == DisplayControlMessage.STATUS_OK || status == DisplayControlMessage.STATUS_ERROR) {
                    "invalid selectDisplayResult status"
                }
                DisplayControlMessage.SelectDisplayResult(
                    displayId = json.getLong("displayId"),
                    status = status,
                    message = json.optString("message").ifBlank { null },
                )
            }
            else -> throw IllegalArgumentException("unknown display control message: $type")
        }
    }
}
