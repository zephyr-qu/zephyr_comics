package com.zephyr.comics

import android.content.Context
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val SAF_CHANNEL = "com.zephyr.comics/saf"
    private val STORAGE_CHANNEL = "com.zephyr.comics/storage"
    private val PICK_DIRECTORY_REQUEST = 0x4001
    private val ALL_FILES_ACCESS_REQUEST = 0x4002

    // 用于保存 MethodChannel 结果，等 pickActivity 完成后再返回
    private var pendingSafResult: MethodChannel.Result? = null
    private var pendingStorageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    // 打开 SAF 目录选择器，返回 { treeUri, path }
                    if (pendingSafResult != null) {
                        result.error("ALREADY_ACTIVE", "目录选择器已在运行", null)
                        return@setMethodCallHandler
                    }
                    pendingSafResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                    }
                    startActivityForResult(intent, PICK_DIRECTORY_REQUEST)
                }
                "listCbzFiles" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("INVALID_ARG", "uri is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val files = listCbzFiles(this, uri)
                        result.success(files)
                    } catch (e: Exception) {
                        Log.e("SAFHelper", "listCbzFiles failed", e)
                        result.error("SAF_ERROR", e.message, null)
                    }
                }
                "copyToCache" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("INVALID_ARG", "uri is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val localPath = copyToCache(this, uri)
                        result.success(localPath)
                    } catch (e: Exception) {
                        Log.e("SAFHelper", "copyToCache failed", e)
                        result.error("SAF_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
            return
        }
        if (requestCode != PICK_DIRECTORY_REQUEST) return

        val res = pendingSafResult
        pendingSafResult = null

        if (resultCode != RESULT_OK || data?.data == null) {
            res?.success(null) // 用户取消
            return
        }

        val treeUri = data.data!!
        // 持久化授权
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (e: SecurityException) {
            // 某些设备可能不支持持久化授权
            Log.w("SAFHelper", "无法持久化 URI 授权: ${e.message}")
        }

        // 构建 Document URI 以解析文件路径
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val realPath = getPathFromTreeUri(docUri)

        // 返回 { treeUri, path }
        val resultMap = mapOf(
            "treeUri" to treeUri.toString(),
            "path" to (realPath ?: "")
        )
        res?.success(resultMap)
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

    private fun getPathFromTreeUri(treeUri: Uri): String? {
        val docId = DocumentsContract.getTreeDocumentId(treeUri) ?: return null
        val parts = docId.split(":")
        if (parts.size < 2) return null

        val storageType = parts[0]  // "primary" or volume id
        val relativePath = parts.getOrElse(1) { "" }

        return if (storageType == "primary") {
            "${Environment.getExternalStorageDirectory()}/$relativePath"
        } else {
            "/storage/$storageType/$relativePath"
        }
    }

    private fun listCbzFiles(context: Context, uriString: String): List<String> {
        val treeUri = Uri.parse(uriString)
        val docFile = DocumentFile.fromTreeUri(context, treeUri) ?: return emptyList()
        val cbzUris = mutableListOf<String>()

        fun scanDir(dir: DocumentFile) {
            val children = dir.listFiles()
            for (child in children) {
                when {
                    child.isDirectory -> scanDir(child)
                    child.name?.lowercase()?.endsWith(".cbz") == true ||
                    child.name?.lowercase()?.endsWith(".cbr") == true ||
                    child.name?.lowercase()?.endsWith(".zip") == true -> {
                        cbzUris.add(child.uri.toString())
                    }
                }
            }
        }

        scanDir(docFile)
        Log.i("SAFHelper", "找到 ${cbzUris.size} 个漫画文件")
        return cbzUris
    }

    private fun copyToCache(context: Context, uriString: String): String {
        val uri = Uri.parse(uriString)
        val (displayName, sourceSize) = queryDocumentInfo(context, uri)
        val cacheRoot = File(context.cacheDir, "saf_imports")
        cacheRoot.mkdirs()
        cleanupLegacySafCopies(cacheRoot)

        val uriKey = MessageDigest.getInstance("SHA-256")
            .digest(uriString.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val sourceDir = File(cacheRoot, uriKey)
        sourceDir.mkdirs()
        val cacheFile = File(sourceDir, sanitizeFileName(displayName))

        if (cacheFile.isFile && sourceSize >= 0 && cacheFile.length() == sourceSize) {
            cleanupStaleSourceFiles(sourceDir, cacheFile)
            Log.i("SAFHelper", "复用缓存: ${cacheFile.absolutePath}")
            return cacheFile.absolutePath
        }

        val inputStream = context.contentResolver.openInputStream(uri)
            ?: throw Exception("无法打开: $uriString")
        val partialFile = File(sourceDir, "${cacheFile.name}.partial")
        inputStream.use { input ->
            partialFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (sourceSize >= 0 && partialFile.length() != sourceSize) {
            partialFile.delete()
            throw Exception("缓存复制不完整: $displayName")
        }
        val previousFile = File(sourceDir, "${cacheFile.name}.previous")
        if (previousFile.exists() && !previousFile.delete()) {
            partialFile.delete()
            throw Exception("无法清理旧缓存备份: ${previousFile.absolutePath}")
        }
        if (cacheFile.exists() && !cacheFile.renameTo(previousFile)) {
            partialFile.delete()
            throw Exception("无法备份现有缓存: ${cacheFile.absolutePath}")
        }
        if (!partialFile.renameTo(cacheFile)) {
            partialFile.delete()
            if (previousFile.exists() && !previousFile.renameTo(cacheFile)) {
                Log.e("SAFHelper", "无法恢复缓存备份: ${cacheFile.absolutePath}")
            }
            throw Exception("无法完成缓存写入: ${cacheFile.absolutePath}")
        }
        if (previousFile.exists() && !previousFile.delete()) {
            Log.w("SAFHelper", "无法清理缓存备份: ${previousFile.absolutePath}")
        }
        cleanupStaleSourceFiles(sourceDir, cacheFile)
        Log.i("SAFHelper", "复制到缓存: ${cacheFile.absolutePath}")
        return cacheFile.absolutePath
    }

    private fun queryDocumentInfo(context: Context, uri: Uri): Pair<String, Long> {
        var displayName: String? = null
        var size = -1L
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    displayName = cursor.getString(nameIndex)
                }
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        val document = DocumentFile.fromSingleUri(context, uri)
        if (size < 0 && document != null && document.length() > 0) {
            size = document.length()
        }
        val fallbackName = document?.name ?: "comic.cbz"
        return Pair(displayName ?: fallbackName, size)
    }

    private fun sanitizeFileName(name: String): String {
        val sanitized = name
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .trim(' ', '.')
        return sanitized.ifEmpty { "comic.cbz" }
    }

    private fun cleanupLegacySafCopies(cacheRoot: File) {
        val legacyName = Regex("comic_\\d+\\.(cbz|cbr|zip)", RegexOption.IGNORE_CASE)
        cacheRoot.listFiles()?.forEach { file ->
            if (file.isFile && legacyName.matches(file.name) && !file.delete()) {
                Log.w("SAFHelper", "无法清理旧缓存: ${file.absolutePath}")
            }
        }
    }

    private fun cleanupStaleSourceFiles(sourceDir: File, currentFile: File) {
        sourceDir.listFiles()?.forEach { file ->
            if (file.isFile && file != currentFile && !file.delete()) {
                Log.w("SAFHelper", "无法清理过期 SAF 缓存: ${file.absolutePath}")
            }
        }
    }
}
