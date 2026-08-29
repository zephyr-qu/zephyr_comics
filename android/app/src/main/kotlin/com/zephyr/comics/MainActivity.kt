package com.zephyr.comics

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.zephyr.comics/storage"
    private val ALL_FILES_ACCESS_REQUEST = 0x4002

    private var pendingStorageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAllFilesAccessGranted" -> result.success(Environment.isExternalStorageManager())
                "requestAllFilesAccess" -> requestAllFilesAccess(result)
                else -> result.notImplemented()
            }
        }
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