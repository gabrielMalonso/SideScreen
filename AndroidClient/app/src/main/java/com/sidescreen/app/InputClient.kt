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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class InputClient(
    private val host: String,
    private val port: Int,
    private val token: ByteArray,
    private val deviceId: String,
    private val context: Context?,
    private val endpointMode: EndpointMode,
) {
    private val executor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "RemoteInputThread").apply {
                priority = Thread.MAX_PRIORITY
            }
    }
    private val sequence = AtomicLong(1)
    private val closed = AtomicBoolean(false)
    private val lock = Any()
    private var socket: Socket? = null
    private var output: BufferedOutputStream? = null

    @Volatile
    var isConnected: Boolean = false
        private set

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
                        capabilities =
                            RemoteInputProtocol.CAP_KEYBOARD_ACTIVITY or
                                RemoteInputProtocol.CAP_POINTER_CAPTURE or
                                RemoteInputProtocol.CAP_GENERIC_MOTION or
                                RemoteInputProtocol.CAP_HID_USAGE_MAPPING,
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
                input.read() // backend id, ignored for now

                synchronized(lock) {
                    socket = sock
                    output = out
                    isConnected = true
                }
                DiagLog.log("IC", "Input channel connected to $host:$port mode=$endpointMode")
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
            closeSocketOnly()
        }
    }

    fun shutdown() {
        if (!closed.compareAndSet(false, true)) return
        executor.execute {
            sendAllInputsUpInternal()
            closeSocketOnly()
        }
        executor.shutdown()
    }

    fun sendKey(event: KeyEvent): Boolean {
        val usageId = AndroidKeyToHid.usageId(event) ?: return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        val down = event.action == KeyEvent.ACTION_DOWN
        send(
            RemoteInputProtocol.EVENT_KEYBOARD_KEY,
            RemoteInputProtocol.keyboardPayload(event, usageId, down),
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
        if (endpointMode.isTailnet) {
            DiagLog.log("IC", "Tailnet input channel using default VPN route")
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
    }
}
