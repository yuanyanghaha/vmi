package com.example.goods_flutter

import android.content.Intent
import android.os.Bundle
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "goods_flutter/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val text = call.argument<String>("text") ?: "货品库存统计"
                if (path.isNullOrBlank() || !File(path).exists()) {
                    result.error("no_file", "导出文件不存在", null)
                    return@setMethodCallHandler
                }
                try {
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileprovider",
                        File(path)
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_TEXT, text)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(intent, "导出 Excel"))
                    result.success(true)
                } catch (error: Exception) {
                    result.error("share_failed", error.message, null)
                }
            }
    }
}
