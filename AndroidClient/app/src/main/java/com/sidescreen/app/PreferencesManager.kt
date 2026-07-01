package com.sidescreen.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import java.security.SecureRandom
import java.util.UUID

class PreferencesManager(
    context: Context,
) {
    private val prefs: SharedPreferences = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)

    var showStatsOverlay: Boolean
        get() = prefs.getBoolean("show_stats", false)
        set(value) = prefs.edit().putBoolean("show_stats", value).apply()

    var showInputOverlay: Boolean
        get() = prefs.getBoolean("show_input_overlay", false)
        set(value) = prefs.edit().putBoolean("show_input_overlay", value).apply()

    var overlayOpacity: Float
        get() = prefs.getFloat("overlay_opacity", 0.8f)
        set(value) = prefs.edit().putFloat("overlay_opacity", value).apply()

    var overlayX: Float
        get() = prefs.getFloat("overlay_x", -1f)
        set(value) = prefs.edit().putFloat("overlay_x", value).apply()

    var overlayY: Float
        get() = prefs.getFloat("overlay_y", -1f)
        set(value) = prefs.edit().putFloat("overlay_y", value).apply()

    var settingsButtonX: Float
        get() = prefs.getFloat("settings_x", -1f)
        set(value) = prefs.edit().putFloat("settings_x", value).apply()

    var settingsButtonY: Float
        get() = prefs.getFloat("settings_y", -1f)
        set(value) = prefs.edit().putFloat("settings_y", value).apply()

    // Corner position: 0=bottom-right, 1=bottom-left, 2=top-right, 3=top-left
    var settingsButtonCorner: Int
        get() = prefs.getInt("settings_corner", 0)
        set(value) = prefs.edit().putInt("settings_corner", value).apply()

    var connectionMode: ConnectionMode
        get() = ConnectionMode.fromName(prefs.getString("connection_mode", null))
        set(value) = prefs.edit().putString("connection_mode", value.name).apply()

    var metaKeyMapping: MetaKeyMapping
        get() = MetaKeyMapping.fromName(prefs.getString("meta_key_mapping", null))
        set(value) = prefs.edit().putString("meta_key_mapping", value.name).apply()

    var mouseSensitivity: Float
        get() = prefs.getFloat("mouse_sensitivity", PointerTuning.DEFAULT_MOUSE_SENSITIVITY)
        set(value) = prefs.edit().putFloat("mouse_sensitivity", value.coerceIn(PointerTuning.MIN_SENSITIVITY, PointerTuning.MAX_SENSITIVITY)).apply()

    var scrollSensitivity: Float
        get() = prefs.getFloat("scroll_sensitivity", PointerTuning.DEFAULT_SCROLL_SENSITIVITY)
        set(value) = prefs.edit().putFloat("scroll_sensitivity", value.coerceIn(PointerTuning.MIN_SENSITIVITY, PointerTuning.MAX_SENSITIVITY)).apply()

    var naturalScroll: Boolean
        get() = prefs.getBoolean("natural_scroll", false)
        set(value) = prefs.edit().putBoolean("natural_scroll", value).apply()

    val pointerTuning: PointerTuning
        get() =
            PointerTuning.normalized(
                mouseSensitivity = mouseSensitivity,
                scrollSensitivity = scrollSensitivity,
                naturalScroll = naturalScroll,
            )

    val remoteInputDeviceId: String
        get() {
            prefs.getString("remote_input_device_id", null)?.let { return it }
            val generated = UUID.randomUUID().toString()
            prefs.edit().putString("remote_input_device_id", generated).apply()
            return generated
        }

    val remoteDeviceSecret: ByteArray
        get() {
            prefs.getString("remote_device_secret_b64", null)?.let { encoded ->
                try {
                    val decoded = Base64.decode(encoded, Base64.NO_WRAP or Base64.NO_PADDING)
                    if (decoded.size == 32) return decoded
                } catch (_: IllegalArgumentException) {
                }
            }
            val generated = ByteArray(32)
            SecureRandom().nextBytes(generated)
            prefs.edit()
                .putString("remote_device_secret_b64", Base64.encodeToString(generated, Base64.NO_WRAP or Base64.NO_PADDING))
                .apply()
            return generated
        }
}
