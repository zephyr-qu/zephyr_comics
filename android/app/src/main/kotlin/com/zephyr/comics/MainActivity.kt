package com.zephyr.comics

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.zephyr.comics/storage"
    private val SETTINGS_CHANNEL = "com.zephyr.comics/settings"
    private val VOLUME_KEYS_CHANNEL = "com.zephyr.comics/volume_keys"
    private val ALL_FILES_ACCESS_REQUEST = 0x4002

    private var pendingStorageResult: MethodChannel.Result? = null
    private var volumeKeyPagingEnabled = false
    private var readerActive = false
    private var volumeKeysChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAllFilesAccessGranted" -> result.success(Environment.isExternalStorageManager())
                "requestAllFilesAccess" -> requestAllFilesAccess(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenAwake" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        volumeKeysChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOLUME_KEYS_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setVolumeKeyPaging" -> {
                        volumeKeyPagingEnabled = call.argument<Boolean>("enabled") ?: false
                        result.success(null)
                    }
                    "setReaderActive" -> {
                        readerActive = call.argument<Boolean>("active") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolumeKey = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (volumeKeyPagingEnabled && readerActive && isVolumeKey) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                volumeKeysChannel?.invokeMethod(
                    "volumeKeyPressed",
                    if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                )
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ALL_FILES_ACCESS_REQUEST) {
            val result = pendingStorageResult
            pendingStorageResult = null
            result?.success(Environment.isExternalStorageManager())
        }
    }

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (Environment.isExternalStorageManager()) {
            result.success(true)
            return
        }
        if (pendingStorageResult != null) {
            result.error("ALREADY_ACTIVE", "所有文件访问授权页面已在运行", null)
            return
        }

        pendingStorageResult = result
        val appSettingsIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivityForResult(appSettingsIntent, ALL_FILES_ACCESS_REQUEST)
        } catch (_: ActivityNotFoundException) {
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    ALL_FILES_ACCESS_REQUEST
                )
            } catch (error: Exception) {
                pendingStorageResult = null
                result.error("SETTINGS_UNAVAILABLE", "无法打开所有文件访问设置", error.message)
            }
        } catch (error: Exception) {
            pendingStorageResult = null
            result.error("SETTINGS_UNAVAILABLE", "无法打开所有文件访问设置", error.message)
        }
    }
}
