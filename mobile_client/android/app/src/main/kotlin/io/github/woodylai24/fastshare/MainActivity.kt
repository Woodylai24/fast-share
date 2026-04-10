package io.github.woodylai24.fastshare

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val SHARE_CHANNEL = "fast_share/share_receiver"
    private val FILE_CHANNEL = "fast_share/file_helper"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupFileHelperChannel(flutterEngine)
        checkPendingShare(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == "io.github.woodylai24.fastshare.HANDLE_SHARE") {
            flutterEngine?.let { checkPendingShare(it) }
        }
    }

    private fun setupFileHelperChannel(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resolveContentUri" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null) {
                            val filePath = resolveContentUri(uriString)
                            if (filePath != null) {
                                result.success(filePath)
                            } else {
                                result.error("RESOLVE_FAILED", "Could not resolve URI: $uriString", null)
                            }
                        } else {
                            result.error("NO_URI", "No URI provided", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun resolveContentUri(uriString: String): String? {
        return try {
            val uri = Uri.parse(uriString)

            val inputStream = contentResolver.openInputStream(uri) ?: return null

            var filename: String? = null
            val cursor = contentResolver.query(uri, null, null, null, null)
            if (cursor != null) {
                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && cursor.moveToFirst()) {
                    filename = cursor.getString(nameIndex)
                }
                cursor.close()
            }
            if (filename == null) {
                filename = "shared_file_${System.currentTimeMillis()}"
            }

            val tempFile = File(cacheDir, filename)
            if (tempFile.exists()) tempFile.delete()

            FileOutputStream(tempFile).use { output ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                }
            }
            inputStream.close()

            tempFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "resolveContentUri failed", e)
            null
        }
    }

    private fun checkPendingShare(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        val prefs = getSharedPreferences("fast_share", MODE_PRIVATE)
        if (!prefs.getBoolean("has_pending_share", false)) return

        val type = prefs.getString("pending_share_type", null) ?: return
        val data = prefs.getString("pending_share_data", null) ?: return
        val mimeType = prefs.getString("pending_share_mime", "text/plain") ?: "text/plain"

        prefs.edit().clear().apply()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .invokeMethod("shareReceived", mapOf(
                "type" to type,
                "data" to data,
                "mimeType" to mimeType
            ))
    }
}
