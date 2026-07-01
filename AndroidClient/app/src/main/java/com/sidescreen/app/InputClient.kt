package com.sidescreen.app

import android.content.Context
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
    private val metaKeyMapping: MetaKeyMapping,
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
    private var pointerFlushTask: ScheduledFuture<*>? = null
    private var pendingPointerRelative: PendingPointerRelative? = null
    private val latencyTracker = InputLatencyTracker()

    @Volatile
    var isConnected: Boolean = false
        private set

    var onBackendAccepted: ((String) -> Unit)? = null
    var onInputLatencyMeasured: ((InputLatencyStats) -> Unit)? = null

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
                DiagLog.log(
                    "IC",
                    "Input hello to $host:$port session=${if (sessionId == null) "missing" else "present"}",
                )
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
                val fallbackReason = readBackendFallbackReason(input)
                val backendName = backendDisplayName(backendId, fallbackReason)

                synchronized(lock) {
                    socket = sock
                    output = out
                    isConnected = true
                }
                latencyTracker.reset()
                startReader(input)
                startHeartbeat()
                DiagLog.log("IC", "Input channel connected to $host:$port mode=$endpointMode backend=$backendName")
                onBackendAccepted?.invoke(backendName)
            } catch (e: Exception) {
                Log.e(TAG, "Input channel connect failed", e)
                DiagLog.log("IC", "Input channel connect failed: ${e.javaClass.simpleName}: ${e.message}")
                closeSocketOnly()
            }
        }
    }

    fun disconnect() {
        if (closed.get()) return
        executor.execute {
            sendAllInputsUpInternal(RemoteInputProtocol.ALL_INPUTS_UP_NETWORK_DISCONNECT)
            stopHeartbeat()
            closeSocketOnly()
        }
    }

    fun shutdown() {
        if (!closed.compareAndSet(false, true)) return
        executor.execute {
            sendAllInputsUpInternal(RemoteInputProtocol.ALL_INPUTS_UP_NETWORK_DISCONNECT)
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
        textCommitCharacters(event)?.let { return sendTextCommit(it) }
        val usageId = AndroidKeyToHid.usageId(event, metaKeyMapping) ?: return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        val down = event.action == KeyEvent.ACTION_DOWN
        send(
            RemoteInputProtocol.EVENT_KEYBOARD_KEY,
            RemoteInputProtocol.keyboardPayload(event, usageId, down, sourceFlag),
        )
        return true
    }

    @Suppress("DEPRECATION")
    private fun textCommitCharacters(event: KeyEvent): String? =
        if (event.action == KeyEvent.ACTION_MULTIPLE) event.characters else null

    fun sendTextCommit(text: String): Boolean {
        if (text.isEmpty()) return false
        return try {
            for (chunk in splitTextCommit(text)) {
                send(
                    RemoteInputProtocol.EVENT_TEXT_COMMIT,
                    RemoteInputProtocol.textCommitPayload(chunk),
                )
            }
            true
        } catch (e: IllegalArgumentException) {
            DiagLog.log("IC", "TextCommit rejected: ${e.message}")
            false
        }
    }

    private fun splitTextCommit(text: String): List<String> {
        val chunks = mutableListOf<String>()
        val current = StringBuilder()
        var currentBytes = 0
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAt(index)
            val value = String(Character.toChars(codePoint))
            val byteCount = value.toByteArray(Charsets.UTF_8).size
            if (currentBytes + byteCount > RemoteInputProtocol.MAX_TEXT_COMMIT_BYTES && current.isNotEmpty()) {
                chunks.add(current.toString())
                current.clear()
                currentBytes = 0
            }
            current.append(value)
            currentBytes += byteCount
            index += Character.charCount(codePoint)
        }
        if (current.isNotEmpty()) chunks.add(current.toString())
        return chunks
    }

    fun sendPointerRelative(
        dx: Float,
        dy: Float,
        fromPointerCapture: Boolean,
    ) {
        if (dx == 0f && dy == 0f) return
        if (closed.get()) return
        executor.execute {
            enqueuePointerRelative(dx, dy, fromPointerCapture)
        }
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
        sendAllInputsUp(RemoteInputProtocol.ALL_INPUTS_UP_EXPLICIT_USER_ACTION)
    }

    fun sendAllInputsUp(reason: Int) {
        if (closed.get()) return
        executor.execute { sendAllInputsUpInternal(reason) }
    }

    private fun send(
        eventType: Int,
        payload: ByteArray,
    ) {
        if (closed.get()) return
        executor.execute {
            flushPendingPointerRelative()
            writeFrame(RemoteInputProtocol.envelope(eventType, sequence.getAndIncrement(), payload))
        }
    }

    private fun enqueuePointerRelative(
        dx: Float,
        dy: Float,
        fromPointerCapture: Boolean,
    ) {
        val pending = pendingPointerRelative
        pendingPointerRelative =
            if (pending == null) {
                schedulePointerFlush()
                PendingPointerRelative(dx, dy, fromPointerCapture)
            } else {
                PendingPointerRelative(
                    dx = pending.dx + dx,
                    dy = pending.dy + dy,
                    fromPointerCapture = pending.fromPointerCapture || fromPointerCapture,
                )
            }
    }

    private fun schedulePointerFlush() {
        pointerFlushTask?.cancel(false)
        pointerFlushTask =
            heartbeatExecutor.schedule(
                { executor.execute { flushPendingPointerRelative() } },
                POINTER_FLUSH_DELAY_MS,
                TimeUnit.MILLISECONDS,
            )
    }

    private fun flushPendingPointerRelative() {
        val pending = pendingPointerRelative ?: return
        pendingPointerRelative = null
        pointerFlushTask?.cancel(false)
        pointerFlushTask = null
        writeFrame(
            RemoteInputProtocol.envelope(
                RemoteInputProtocol.EVENT_POINTER_RELATIVE,
                sequence.getAndIncrement(),
                RemoteInputProtocol.pointerRelativePayload(
                    pending.dx,
                    pending.dy,
                    pending.fromPointerCapture,
                ),
            ),
        )
    }

    private fun sendAllInputsUpInternal(reason: Int) {
        flushPendingPointerRelative()
        writeFrame(
            RemoteInputProtocol.envelope(
                RemoteInputProtocol.EVENT_ALL_INPUTS_UP,
                sequence.getAndIncrement(),
                RemoteInputProtocol.allInputsUpPayload(reason),
            ),
        )
    }

    private fun sendHeartbeat() {
        flushPendingPointerRelative()
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
        pointerFlushTask?.cancel(false)
        pointerFlushTask = null
    }

    private fun startReader(input: BufferedInputStream) {
        readerExecutor.execute {
            try {
                while (!closed.get() && isConnected) {
                    val headerBytes = ByteArray(RemoteInputProtocol.ENVELOPE_HEADER_LENGTH)
                    readFully(input, headerBytes)
                    val header = RemoteInputProtocol.parseEnvelopeHeader(headerBytes)
                    if (header.payloadLength > RemoteInputProtocol.MAX_PAYLOAD_BYTES) {
                        throw IOException("server input payload too large: ${header.payloadLength}")
                    }
                    val payload = ByteArray(header.payloadLength)
                    if (payload.isNotEmpty()) readFully(input, payload)
                    handleServerFrame(header, payload)
                }
            } catch (e: Exception) {
                if (!closed.get()) {
                    Log.e(TAG, "Input channel read failed", e)
                    executor.execute { closeSocketOnly() }
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
                onInputLatencyMeasured?.invoke(latencyTracker.add(rttMs))
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
        if (isLoopbackHost()) {
            DiagLog.log("IC", "$endpointMode input channel using loopback route")
            return
        }
        NetworkRoute.bindWifiIfNeeded(context, endpointMode, sock, "input channel") { message ->
            DiagLog.log("IC", message)
        }
    }

    private fun capabilities(): Int {
        var capabilities =
            RemoteInputProtocol.CAP_KEYBOARD_ACTIVITY or
                RemoteInputProtocol.CAP_POINTER_CAPTURE or
                RemoteInputProtocol.CAP_GENERIC_MOTION or
                RemoteInputProtocol.CAP_TEXT_COMMIT or
                RemoteInputProtocol.CAP_HID_USAGE_MAPPING or
                RemoteInputProtocol.CAP_BACKEND_STATUS
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
        pendingPointerRelative = null
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

    private fun isLoopbackHost(): Boolean =
        host.equals("localhost", ignoreCase = true) || host == "127.0.0.1" || host == "::1" || host == "[::1]"

    companion object {
        private const val TAG = "InputClient"
        private const val INPUT_HEARTBEAT_SECONDS = 2L
        private const val POINTER_FLUSH_DELAY_MS = 4L
        private fun backendDisplayName(
            id: Int,
            fallbackReason: String,
        ): String {
            val name = backendName(id)
            return if (fallbackReason.isNotBlank()) "$name fallback: $fallbackReason" else name
        }

        private fun backendName(id: Int): String =
            when (id) {
                1 -> "CGEvent"
                2 -> "Virtual HID"
                else -> "None"
            }
    }

    private fun readBackendFallbackReason(input: BufferedInputStream): String {
        val lengthBytes = ByteArray(2)
        readFully(input, lengthBytes)
        val length = (lengthBytes[0].toInt() and 0xff) or ((lengthBytes[1].toInt() and 0xff) shl 8)
        if (length == 0) return ""
        val reasonBytes = ByteArray(length)
        readFully(input, reasonBytes)
        return reasonBytes.toString(Charsets.UTF_8)
    }

    private data class PendingPointerRelative(
        val dx: Float,
        val dy: Float,
        val fromPointerCapture: Boolean,
    )
}
