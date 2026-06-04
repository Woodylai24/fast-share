package io.github.woodylai24.fastshare

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.app.Activity

/**
 * Transparent Activity that receives share intents (PROCESS_TEXT, SEND, SEND_MULTIPLE).
 * Does NOT use Flutter - avoids creating a second engine.
 * Saves share data to SharedPreferences and reuses the existing MainActivity task.
 */
class ShareReceiverActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) {
            finish()
            return
        }

        when (intent.action) {
            Intent.ACTION_SEND -> handleSendIntent(intent)
            Intent.ACTION_SEND_MULTIPLE -> handleSendMultipleIntent(intent)
            Intent.ACTION_PROCESS_TEXT -> handleProcessTextIntent(intent)
            else -> finish()
        }
    }

    private fun handleSendIntent(intent: Intent) {
        val type = intent.type ?: return finish()

        if (type.startsWith("text/plain")) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (sharedText != null) {
                savePendingShare("text", sharedText)
                forwardToMainActivity()
            }
        } else {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                // Grant read permission to the entire app (not just this activity)
                grantUriPermission(
                    "io.github.woodylai24.fastshare",
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
                savePendingShare("file", uri.toString(), type)
                forwardToMainActivity()
            }
        }
    }

    private fun handleSendMultipleIntent(intent: Intent) {
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        if (uris != null && uris.isNotEmpty()) {
            for (uri in uris) {
                grantUriPermission(
                    "io.github.woodylai24.fastshare",
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            val paths = uris.joinToString(",") { it.toString() }
            savePendingShare("files", paths, intent.type ?: "*/*")
            forwardToMainActivity()
        }
    }

    private fun handleProcessTextIntent(intent: Intent) {
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        if (text != null) {
            savePendingShare("text", text)
            // Return result to calling app
            setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text))
            forwardToMainActivity()
        }
    }

    private fun savePendingShare(type: String, data: String, mimeType: String = "text/plain") {
        val prefs = getSharedPreferences("fast_share", MODE_PRIVATE)
        prefs.edit()
            .putString("pending_share_type", type)
            .putString("pending_share_data", data)
            .putString("pending_share_mime", mimeType)
            .putBoolean("has_pending_share", true)
            .apply()
    }

    private fun forwardToMainActivity() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            action = "io.github.woodylai24.fastshare.HANDLE_SHARE"
        }
        startActivity(launchIntent)
        finish()
    }
}
