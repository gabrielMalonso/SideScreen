package com.sidescreen.app

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.Executors

/**
 * Shared diagnostic file logger for debugging on devices that suppress logcat.
 * Writes to app-private files directory. Log file is capped at 1MB to prevent unbounded growth.
 */
object DiagLog {
    private const val TAG = "DiagLog"
    private const val LOG_FILE = "diag.log"
    private const val MAX_LOG_SIZE = 1_048_576L // 1MB
    private val ERROR_MARKERS = listOf("error", "failed", "rejected", "timeout", "unreachable")

    @Volatile
    private var logFile: File? = null

    private val logExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "DiagLogWriter").apply {
                isDaemon = true
            }
        }

    /** Initialize with app context. Call once from Application.onCreate() or MainActivity. */
    fun init(context: Context) {
        logFile = File(context.filesDir, LOG_FILE)
    }

    fun log(
        tag: String,
        msg: String,
    ) {
        Log.d(tag, msg)
        val f = logFile ?: return
        logExecutor.execute {
            try {
                // Rotate if too large
                if (f.exists() && f.length() > MAX_LOG_SIZE) {
                    val backup = File(f.parent, "diag.log.old")
                    backup.delete()
                    f.renameTo(backup)
                }
                f.appendText("[${System.currentTimeMillis()}] $tag: $msg\n")
            } catch (_: Exception) {
            }
        }
    }

    fun recentErrorSummary(maxLines: Int = 3): String {
        val f = logFile ?: return "Recent errors: log unavailable"
        return try {
            if (!f.exists()) return "Recent errors: none"
            summarizeRecentErrors(f.readLines(), maxLines)
        } catch (_: Exception) {
            "Recent errors: unavailable"
        }
    }

    fun summarizeRecentErrors(
        lines: List<String>,
        maxLines: Int = 3,
    ): String {
        val matches =
            lines
                .asReversed()
                .filter(::isErrorLine)
                .take(maxLines)
                .asReversed()
                .map { it.substringAfter(": ").take(140) }
        return if (matches.isEmpty()) {
            "Recent errors: none"
        } else {
            "Recent errors: " + matches.joinToString(" · ")
        }
    }

    private fun isErrorLine(line: String): Boolean {
        val lower = line.lowercase()
        return ERROR_MARKERS.any { marker -> lower.contains(marker) }
    }
}
