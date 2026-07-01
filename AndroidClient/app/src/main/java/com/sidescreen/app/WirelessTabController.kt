package com.sidescreen.app

import android.app.Activity
import android.content.Intent
import android.view.View
import android.widget.Button
import android.widget.TextView
import android.widget.Toast

/**
 * Five-state UI machine for the Wireless tab on Android.
 *
 *   ① first-time → ② scanning (QRScannerActivity) → ③ connected
 *                                         ↘ ④ token mismatch / re-pair
 *   ⓹ permission denied permanently
 */
class WirelessTabController(
    private val activity: Activity,
    private val views: Views,
    private val storage: PairedHostStorage,
    private val cameraPerm: CameraPermissionManager,
    private val onConnectRequested: (
        host: String,
        port: Int,
        token: ByteArray,
        deviceName: String,
        macName: String,
        endpointMode: EndpointMode,
    ) -> Unit,
) {
    data class Views(
        val connecting: View,
        val firstTime: View,
        val connected: View,
        val pairedIdle: View,
        val repair: View,
        val permDenied: View,
        val scanButton: Button,
        val rescanButton: Button,
        val disconnectButton: Button,
        val forgetButton: Button,
        val reconnectButton: Button,
        val idleForgetButton: Button,
        val openSettingsButton: Button,
        val connectedMacName: TextView,
        val connectedMacIp: TextView,
        val connectingLabel: TextView,
        val connectingSubtitle: TextView,
        val idleMacName: TextView,
        val idleMacIp: TextView,
        val repairTitle: TextView,
        val repairMessage: TextView,
        val endpointModeText: TextView,
        val routeText: TextView,
        val inputRouteText: TextView,
        val recentErrorsText: TextView,
        val limitationText: TextView,
    )

    enum class State { FIRST_TIME, CONNECTING, CONNECTED, PAIRED_IDLE, REPAIR_NEEDED, PERM_DENIED }

    private var state: State = State.FIRST_TIME

    fun bind() {
        views.scanButton.setOnClickListener { triggerScan() }
        views.rescanButton.setOnClickListener { triggerScan() }
        views.openSettingsButton.setOnClickListener { cameraPerm.openAppSettings() }
        views.forgetButton.setOnClickListener {
            storage.clear()
            transition(State.FIRST_TIME)
        }
        views.idleForgetButton.setOnClickListener {
            storage.clear()
            transition(State.FIRST_TIME)
        }
        views.reconnectButton.setOnClickListener {
            val entry =
                storage.load() ?: run {
                    transition(State.FIRST_TIME)
                    return@setOnClickListener
                }
            updateDiagnostics(entry, "Input: connecting")
            showConnecting("Reconnecting to ${entry.macName}", "${entry.host}:${entry.port}")
            attemptAutoConnect(entry)
        }
        updateDiagnostics(storage.load(), "Input: waiting")
    }

    /**
     * Called when the TCP stream goes down (user tapped Disconnect, network drop, etc).
     * Move the UI to a clean "paired but idle" state showing the Mac info + Reconnect button.
     */
    fun onStreamDisconnected() {
        android.util.Log.i(
            "WirelessTabController",
            "onStreamDisconnected called, current state=$state, storage entry exists=${storage.load() != null}",
        )
        val entry =
            storage.load() ?: run {
                updateDiagnostics(null, "Input: waiting")
                transition(State.FIRST_TIME)
                return
            }
        views.idleMacName.text = entry.macName
        views.idleMacIp.text = entry.endpointSummary()
        updateDiagnostics(entry, "Input: disconnected")
        transition(State.PAIRED_IDLE)
    }

    private fun transition(next: State) {
        android.util.Log.i("WirelessTabController", "transition $state → $next")
        state = next
        views.connecting.visibility = if (next == State.CONNECTING) View.VISIBLE else View.GONE
        views.firstTime.visibility = if (next == State.FIRST_TIME) View.VISIBLE else View.GONE
        views.connected.visibility = if (next == State.CONNECTED) View.VISIBLE else View.GONE
        views.pairedIdle.visibility = if (next == State.PAIRED_IDLE) View.VISIBLE else View.GONE
        views.repair.visibility = if (next == State.REPAIR_NEEDED) View.VISIBLE else View.GONE
        views.permDenied.visibility = if (next == State.PERM_DENIED) View.VISIBLE else View.GONE
    }

    /**
     * Called when the Wireless tab becomes visible. Decides initial state based on
     * cached host + camera permission state.
     *
     * No auto-connect: even when a cached pairing exists, the user must press
     * the Reconnect button to actually start a connection. Auto-connect was
     * confusing because it could run silently while the user toggled tabs.
     */
    fun show() {
        when {
            cameraPerm.isPermanentlyDenied() -> {
                updateDiagnostics(storage.load(), "Input: waiting for camera permission")
                transition(State.PERM_DENIED)
            }
            storage.load() == null -> {
                updateDiagnostics(null, "Input: waiting")
                transition(State.FIRST_TIME)
            }
            else -> {
                val entry = storage.load()!!
                views.idleMacName.text = entry.macName
                views.idleMacIp.text = entry.endpointSummary()
                updateDiagnostics(entry, "Input: ready to reconnect")
                transition(State.PAIRED_IDLE)
            }
        }
    }

    fun onScanResult(url: String) {
        val parsed =
            PairingURL.parse(url) ?: run {
                DiagLog.log("WT", "Invalid pairing QR returned by scanner")
                Toast.makeText(activity, "Invalid Side Screen QR. Scan the QR shown on your Mac.", Toast.LENGTH_LONG)
                    .show()
                views.repairTitle.text = "Invalid QR code"
                views.repairMessage.text =
                    "That QR code is not a valid Side Screen pairing code. Open Side Screen on the Mac and scan the QR from the Wireless tab."
                updateDiagnostics(storage.load(), "Input: waiting for valid QR")
                transition(State.REPAIR_NEEDED)
                return
            }
        val deviceName = (android.os.Build.MODEL ?: "Android").take(64)
        val entry = PairedHostStorage.Entry(parsed.host, parsed.port, parsed.token, parsed.macName, parsed.endpointMode)
        storage.save(entry)
        updateDiagnostics(entry, "Input: waiting for secure session")
        showConnecting("Connecting to ${parsed.macName}", entry.endpointSummary())
        onConnectRequested(parsed.host, parsed.port, parsed.token, deviceName, parsed.macName, parsed.endpointMode)
    }

    fun onConnectError(error: StreamClient.WirelessConnectError) {
        val cached = storage.load()
        updateDiagnostics(cached, "Input: not connected")
        when (error) {
            is StreamClient.WirelessConnectError.NetworkUnreachable -> {
                views.repairTitle.text = "⚠ Couldn't reach Mac"
                views.repairMessage.text =
                    if (cached != null) {
                        "No response from ${cached.macName} at ${cached.host}:${cached.port}.\n\n" +
                            cached.endpointMode.failureChecklist + "\n\n" +
                            "If the Mac changed endpoint or port, scan a fresh QR."
                    } else {
                        "No response from your Mac. Make sure both devices are on the same WiFi " +
                            "and the Mac app is running, then scan the QR again."
                    }
                transition(State.REPAIR_NEEDED)
            }
            is StreamClient.WirelessConnectError.TokenRejected -> {
                views.repairTitle.text = "⚠ Re-pair required"
                views.repairMessage.text =
                    if (cached != null) {
                        "${cached.macName} reset its pairing token (e.g. Reset Token clicked, or " +
                            "reinstalled). Scan the new QR to pair again."
                    } else {
                        "The Mac reset its pairing token. Scan the new QR to pair again."
                }
                transition(State.REPAIR_NEEDED)
            }
            is StreamClient.WirelessConnectError.DeviceRevoked -> {
                views.repairTitle.text = "Device blocked on Mac"
                views.repairMessage.text =
                    if (cached != null) {
                        "${cached.macName} rejected this Android device. Open SideScreen on the Mac, go to Paired Devices, and click Allow for this device."
                    } else {
                        "The Mac rejected this Android device. Open SideScreen on the Mac and allow this device in Paired Devices."
                    }
                transition(State.REPAIR_NEEDED)
            }
            is StreamClient.WirelessConnectError.ProtocolError -> {
                views.repairTitle.text = "⚠ Connection error"
                views.repairMessage.text = "Couldn't complete the secure handshake with the Mac. Scan the QR again."
                transition(State.REPAIR_NEEDED)
            }
        }
    }

    private fun showConnecting(
        title: String,
        subtitle: String,
    ) {
        views.connectingLabel.text = title
        views.connectingSubtitle.text = subtitle
        transition(State.CONNECTING)
    }

    fun onConnectSuccess(
        macName: String,
        ip: String,
    ) {
        val entry = storage.load()
        views.connectedMacName.text = macName
        views.connectedMacIp.text = entry?.endpointSummary() ?: ip
        updateDiagnostics(entry, "Input: connecting on port +1")
        transition(State.CONNECTED)
    }

    fun onReconnectScheduled(
        attempt: Int,
        maxAttempts: Int,
        delayMs: Long,
    ) {
        val entry = storage.load()
        updateDiagnostics(entry, "Input: reconnecting")
        showConnecting(
            "Reconnecting to ${entry?.macName ?: "Mac"}",
            "Attempt $attempt/$maxAttempts in ${delayMs / 1000}s",
        )
    }

    fun onInputBackendAccepted(backendName: String) {
        updateDiagnostics(storage.load(), "Input: $backendName active")
    }

    fun onCameraPermissionResult(granted: Boolean) {
        if (granted) {
            // Re-evaluate; user just granted, jump straight into scanner.
            launchScanner()
        } else if (cameraPerm.isPermanentlyDenied()) {
            transition(State.PERM_DENIED)
        }
        // else: stay in current state; user can tap Scan again to re-prompt.
    }

    private fun triggerScan() {
        if (cameraPerm.isPermanentlyDenied()) {
            transition(State.PERM_DENIED)
            return
        }
        if (!cameraPerm.isGranted()) {
            cameraPerm.request(REQ_CAMERA)
            return
        }
        launchScanner()
    }

    private fun launchScanner() {
        val intent = Intent(activity, QRScannerActivity::class.java)
        activity.startActivityForResult(intent, REQ_SCAN)
    }

    private fun attemptAutoConnect(entry: PairedHostStorage.Entry) {
        val deviceName = (android.os.Build.MODEL ?: "Android").take(64)
        onConnectRequested(entry.host, entry.port, entry.token, deviceName, entry.macName, entry.endpointMode)
    }

    private fun updateDiagnostics(
        entry: PairedHostStorage.Entry?,
        inputState: String,
    ) {
        if (entry == null) {
            views.endpointModeText.text = "Endpoint: not paired"
            views.routeText.text = "Route: scan a QR from the Mac"
            views.inputRouteText.text = inputState
            views.recentErrorsText.text = DiagLog.recentErrorSummary()
            views.limitationText.text =
                "No-root mode captures Activity keyboard events and pointer capture. Android system keys may stay local."
            return
        }
        views.endpointModeText.text = "Endpoint: ${entry.endpointMode.displayName} · ${entry.host}:${entry.port}"
        views.routeText.text = "Route: ${NetworkRoute.describeCurrentRoute(activity, entry.endpointMode)}"
        views.inputRouteText.text =
            if (RemoteInputPorts.isValidVideoPort(entry.port)) {
                "$inputState · input port ${RemoteInputPorts.inputPortFor(entry.port)}"
            } else {
                "$inputState · invalid server port ${entry.port}"
            }
        views.recentErrorsText.text = DiagLog.recentErrorSummary()
        views.limitationText.text =
            "No-root input handles normal keys, modifiers delivered by Android, mouse move, buttons, drag and wheel. Home, Power, Recents and some Meta shortcuts may stay on Android."
    }

    private fun PairedHostStorage.Entry.endpointSummary(): String =
        "${endpointMode.displayName}: $host:$port"

    companion object {
        const val REQ_SCAN = 1001
        const val REQ_CAMERA = 1002
    }
}
