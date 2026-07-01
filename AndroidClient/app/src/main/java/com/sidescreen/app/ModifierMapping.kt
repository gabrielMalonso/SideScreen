package com.sidescreen.app

import android.view.KeyEvent

enum class MetaKeyMapping(
    val title: String,
    val leftUsageId: Int?,
    val rightUsageId: Int?,
) {
    COMMAND("Command", 0xE3, 0xE7),
    OPTION("Option", 0xE2, 0xE6),
    CONTROL("Control", 0xE0, 0xE4),
    OFF("Off", null, null);

    fun usageIdFor(event: KeyEvent): Int? =
        usageIdForKeyCode(event.keyCode)

    fun usageIdForKeyCode(keyCode: Int): Int? =
        when (keyCode) {
            KeyEvent.KEYCODE_META_LEFT -> leftUsageId
            KeyEvent.KEYCODE_META_RIGHT -> rightUsageId
            else -> null
        }

    companion object {
        fun fromName(value: String?): MetaKeyMapping =
            entries.firstOrNull { it.name == value } ?: COMMAND
    }
}
