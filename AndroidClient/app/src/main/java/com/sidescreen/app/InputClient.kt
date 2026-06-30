package com.sidescreen.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import android.view.KeyEvent
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class InputClient(
    private val host: String,
    private val port: Int,
    private val token: ByteArray,
    private val deviceId: String,
    private val sessionId: ByteArray?,
    private val context: Context?,
    private val endpointMode: EndpointMode,
) {
    private val executor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "RemoteInputThread").apply {
                priority = Thread.MAX_PRIORITY
            }
    }
    private val heartbeatExecutor =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "RemoteInputHeartbeat").apply {
                priority = Thread.NORM_PRIORITY + 1
                isDaemon = true
            }
        }
    private val readerExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "RemoteInputReader").apply {
                priority = Thread.NORM_PRIORITY + 1
                isDaemon = true
            }
        }
    private val sequence = AtomicLong(1)
    private val closed = AtomicBoolean(false)
    private val lock = Any()
    private var socket: Socket? = null
    private var output: BufferedOutputStream? = null
    private var heartbeatTask: ScheduledFuture<*>? = null

    @Volatile
    var isConnected: Boolean = false
        private set

    var onBackendAccepted: ((String) -> Unit)? = null
    var onInputLatencyMeasured: ((Double) -> Unit)? = null

    fun connect() {
        if (closed.get()) return
        executor.execute {
            synchronized(lock) {
                if (isConnected) return@execute
            }
            try {
                val sock = Socket()
                sock.tcpNoDelay = true
                bindIfNeeded(sock)
                sock.connect(InetSocketAddress(host, port), 5000)
                val out = BufferedOutputStream(sock.getOutputStream(), 8192)
                out.write(
                    RemoteInputProtocol.hello(
                        token = token,
                        deviceId = deviceId,
                        sessionId = sessionId,
                        capabilities = capabilities(),
                    ),
                )
                out.flush()

                val input = BufferedInputStream(sock.getInputStream(), 64)
                val response = ByteArray(5)
                readFully(input, response)
                val accepted =
                    response[0] == 0x52.toByte() &&
                        response[1] == 0x4D.toByte() &&
                        response[2] == 0x49.toByte() &&
                        response[3] == 0x41.toByte() &&
                        response[4] == 0.toByte()
                if (!accepted) throw IOException("input channel rejected")
                val backendId = input.read()
                if (backendId < 0) throw IOException("input channel closed before backend id")
                val backendName = backendName(backendId)

                synchronized(lock) {
                    socket = sock
                    output = out
                    isConnected = true
                }
                startReader(input)
                startHeartbeat()
                DiagLog.log("IC", "Input channel connected to $host:$port mode=$endpointMode backend=$backendName")
                onBackendAccepted?.invoke(backendName)
            } catch (e: Exception) {
                Log.e(TAG, "Input channel connect failed", e)
                closeSocketOnly()
            }
        }
    }

    fun disconnect() {
        if (closed.get()) return
        executor.execute {
            sendAllInputsUpInternal()
            stopHeartbeat()
            closeSocketOnly()
        }
    }

    fun shutdown() {
        if (!closed.compareAndSet(false, true)) return
        executor.execute {
            sendAllInputsUpInternal()
            stopHeartbeat()
            closeSocketOnly()
        }
        executor.shutdown()
        heartbeatExecutor.shutdownNow()
        readerExecutor.shutdownNow()
    }

    fun sendKey(event: KeyEvent): Boolean {
        return sendKey(event, RemoteInputProtocol.FLAG_FROM_ACTIVITY)
    }

    fun sendKey(
        event: KeyEvent,
        sourceFlag: Int,
    ): Boolean {
        val usageId = AndroidKeyToHid.usageId(event) ?: return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        val down = event.action == KeyEvent.ACTION_DOWN
        send(
            RemoteInputProtocol.EVENT_KEYBOARD_KEY,
            RemoteInputProtocol.keyboardPayload(event, usageId, down, sourceFlag),
        )
        return true
    }

    fun sendPointerRelative(
        dx: Float,
        dy: Float,
        fromPointerCapture: Boolean,
    ) {
        if (dx == 0f && dy == 0f) return
        send(
            RemoteInputProtocol.EVENT_POINTER_RELATIVE,
            RemoteInputProtocol.pointerRelativePayload(dx, dy, fromPointerCapture),
        )
    }

    fun sendPointerButton(
        button: Int,
        down: Boolean,
    ) {
        send(
            RemoteInputProtocol.EVENT_POINTER_BUTTON,
            RemoteInputProtocol.pointerButtonPayload(button, down),
        )
    }

    fun sendPointerWheel(
        deltaX: Float,
        deltaY: Float,
    ) {
        if (deltaX == 0f && deltaY == 0f) return
        send(
            RemoteInputProtocol.EVENT_POINTER_WHEEL,
            RemoteInputProtocol.pointerWheelPayload(deltaX, deltaY),
        )
    }

    fun sendAllInputsUp() {
        if (closed.get()) return
        executor.execute { sendAllInputsUpInternal() }
    }

    private fun send(
        eventType: Int,
        payload: ByteArray,
    ) {
        if (closed.get()) return
        executor.execute {
            writeFrame(RemoteInputProtocol.envelope(eventType, sequence.getAndIncrement(), payload))
        }
    }

    private fun sendAllInputsUpInternal() {
        writeFrame(RemoteInputProtocol.envelope(RemoteInputProtocol.EVENT_ALL_INPUTS_UP, sequence.getAndIncrement(), ByteArray(0)))
    }

    private fun sendHeartbeat() {
        writeFrame(
            RemoteInputProtocol.envelope(
                RemoteInputProtocol.EVENT_INPUT_PING,
                sequence.getAndIncrement(),
                RemoteInputProtocol.inputPingPayload(),
            ),
        )
    }

    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatTask =
            heartbeatExecutor.scheduleAtFixedRate(
                {
                    if (!closed.get()) {
                        executor.execute { sendHeartbeat() }
                    }
                },
                INPUT_HEARTBEAT_SECONDS,
                INPUT_HEARTBEAT_SECONDS,
                TimeUnit.SECONDS,
            )
    }

    private fun stopHeartbeat() {
        heartbeatTask?.cancel(false)
        heartbeatTask = null
    }

    private fun startReader(input: BufferedInputStream) {
        readerExecutor.execute {
            try {
                while (!closed.get() && isConnected) {
                    val headerBytes = ByteArray(RemoteInputProtocol.ENVELOPE_HEADER_LENGTH)
                    readFully(input, headerBytes)
                    val header = RemoteInputProtocol.parseEnvelopeHeader(headerBytes)
                    if (header.payloadLength > MAX_SERVER_PAYLOAD_BYTES) {
                        throw IOException("server input payload too large: ${header.payloadLength}")
                    }
                    val payload = ByteArray(header.payloadLength)
                    if (payload.isNotEmpty()) readFully(input, payload)
                    handleServerFrame(header, payload)
                }
            } catch (e: Exception) {
                if (!closed.get()) {
                    Log.e(TAG, "Input channel read failed", e)
                    closeSocketOnly()
                }
            }
        }
    }

    private fun handleServerFrame(
        header: RemoteInputProtocol.EnvelopeHeader,
        payload: ByteArray,
    ) {
        when (header.eventType) {
            RemoteInputProtocol.EVENT_INPUT_PONG -> {
                val pong = RemoteInputProtocol.parseInputPongPayload(payload)
                val rttMs = ((System.nanoTime() - pong.clientTimestampNanos).coerceAtLeast(0L)) / 1_000_000.0
                onInputLatencyMeasured?.invoke(rttMs)
            }
            else -> DiagLog.log("IC", "Ignoring server input event type=${header.eventType}")
        }
    }

    private fun writeFrame(frame: ByteArray) {
        try {
            val out =
                synchronized(lock) {
                    if (!isConnected) return
                    output
                } ?: return
            out.write(frame)
            out.flush()
        } catch (e: IOException) {
            Log.e(TAG, "Input channel write failed", e)
            closeSocketOnly()
        }
    }

    private fun bindIfNeeded(sock: Socket) {
        if (!endpointMode.shouldBindWifi) {
            DiagLog.log("IC", "$endpointMode input channel using default route")
            return
        }
        val wifiNetwork =
            context?.let { ctx ->
                val cm = ctx.getSystemService(ConnectivityManager::class.java)
                cm.allNetworks.firstOrNull { net ->
                    val caps = cm.getNetworkCapabilities(net)
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                }
            }
        if (wifiNetwork != null) {
            DiagLog.log("IC", "LAN input channel binding socket to WiFi")
            wifiNetwork.bindSocket(sock)
        } else {
            DiagLog.log("IC", "LAN input channel using default route")
        }
    }

    private fun capabilities(): Int {
        var capabilities =
            RemoteInputProtocol.CAP_KEYBOARD_ACTIVITY or
                RemoteInputProtocol.CAP_POINTER_CAPTURE or
                RemoteInputProtocol.CAP_GENERIC_MOTION or
                RemoteInputProtocol.CAP_HID_USAGE_MAPPING
        if (context?.let { SideScreenAccessibilityService.isEnabled(it) } == true) {
            capabilities = capabilities or RemoteInputProtocol.CAP_ACCESSIBILITY_ASSIST
        }
        return capabilities
    }

    private fun readFully(
        input: BufferedInputStream,
        buffer: ByteArray,
    ) {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            if (read < 0) throw IOException("input channel closed during handshake")
            offset += read
        }
    }

    private fun closeSocketOnly() {
        stopHeartbeat()
        synchronized(lock) {
            isConnected = false
            try {
                output?.close()
            } catch (_: IOException) {
            }
            try {
                socket?.close()
            } catch (_: IOException) {
            }
            output = null
            socket = null
        }
    }

    companion object {
        private const val TAG = "InputClient"
        private const val INPUT_HEARTBEAT_SECONDS = 2L
        private const val MAX_SERVER_PAYLOAD_BYTES = 4096

        private fun backendName(id: Int): String =
            when (id) {
                1 -> "CGEvent"
                2 -> "Virtual HID"
                else -> "None"
            }
    }
}
