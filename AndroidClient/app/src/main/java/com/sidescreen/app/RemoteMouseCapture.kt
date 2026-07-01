package com.sidescreen.app

import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent

class RemoteMouseCapture(
    private val inputClient: () -> InputClient?,
    private val pointerTuning: () -> PointerTuning,
    private val recordInputEvent: () -> Unit,
) {
    private var lastButtonMask = 0

    fun reset() {
        lastButtonMask = 0
    }

    fun handle(
        event: MotionEvent,
        fromPointerCapture: Boolean,
    ): Boolean {
        val client = inputClient() ?: return false
        val source = event.source
        val isMouse =
            (source and InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE ||
                (source and InputDevice.SOURCE_MOUSE_RELATIVE) == InputDevice.SOURCE_MOUSE_RELATIVE
        if (!isMouse) return false

        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_MOVE, MotionEvent.ACTION_MOVE -> {
                val dx =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        event.getAxisValue(MotionEvent.AXIS_RELATIVE_X)
                    } else {
                        0f
                    }
                val dy =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        event.getAxisValue(MotionEvent.AXIS_RELATIVE_Y)
                    } else {
                        0f
                    }
                val (scaledDx, scaledDy) = pointerTuning().relative(dx, dy)
                client.sendPointerRelative(scaledDx, scaledDy, fromPointerCapture)
                recordInputEvent()
                sendMouseButtonDiff(client, event.buttonState)
                return true
            }
            MotionEvent.ACTION_SCROLL -> {
                val (wheelX, wheelY) =
                    pointerTuning().wheel(
                        rawHorizontal = event.getAxisValue(MotionEvent.AXIS_HSCROLL),
                        rawVertical = event.getAxisValue(MotionEvent.AXIS_VSCROLL),
                    )
                client.sendPointerWheel(deltaX = wheelX, deltaY = wheelY)
                recordInputEvent()
                return true
            }
            MotionEvent.ACTION_BUTTON_PRESS, MotionEvent.ACTION_BUTTON_RELEASE -> {
                sendMouseButtonDiff(client, event.buttonState)
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                client.sendAllInputsUp(RemoteInputProtocol.ALL_INPUTS_UP_POINTER_CAPTURE_LOST)
                recordInputEvent()
                reset()
                return true
            }
        }
        return false
    }

    private fun sendMouseButtonDiff(
        client: InputClient,
        newMask: Int,
    ) {
        val changed = lastButtonMask xor newMask
        if (changed == 0) return
        listOf(
            MotionEvent.BUTTON_PRIMARY to 0,
            MotionEvent.BUTTON_SECONDARY to 1,
            MotionEvent.BUTTON_TERTIARY to 2,
            MotionEvent.BUTTON_BACK to 3,
            MotionEvent.BUTTON_FORWARD to 4,
        ).forEach { (androidButton, remoteButton) ->
            if ((changed and androidButton) != 0) {
                client.sendPointerButton(remoteButton, (newMask and androidButton) != 0)
                recordInputEvent()
            }
        }
        lastButtonMask = newMask
    }
}
