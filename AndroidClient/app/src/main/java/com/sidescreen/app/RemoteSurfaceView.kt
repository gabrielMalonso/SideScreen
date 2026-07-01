package com.sidescreen.app

import android.content.Context
import android.text.InputType
import android.util.AttributeSet
import android.view.SurfaceView
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection

class RemoteSurfaceView
    @JvmOverloads
    constructor(
        context: Context,
        attrs: AttributeSet? = null,
    ) : SurfaceView(context, attrs) {
        var onTextCommit: ((String) -> Boolean)? = null

        init {
            isFocusable = true
            isFocusableInTouchMode = true
        }

        override fun onCheckIsTextEditor(): Boolean = true

        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
            outAttrs.inputType =
                InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                    InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            outAttrs.imeOptions = EditorInfo.IME_ACTION_NONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            return RemoteInputConnection(this)
        }

        private class RemoteInputConnection(
            private val view: RemoteSurfaceView,
        ) : BaseInputConnection(view, false) {
            override fun commitText(
                text: CharSequence?,
                newCursorPosition: Int,
            ): Boolean {
                val value = text?.toString().orEmpty()
                if (value.isEmpty()) return true
                return view.onTextCommit?.invoke(value) ?: false
            }
        }
    }
