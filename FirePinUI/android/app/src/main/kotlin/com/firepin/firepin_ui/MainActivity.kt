package com.firepin.firepin_ui

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ocrExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var ocrChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ocrChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method != "recognize") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    recognize(call, result)
                }
            }
    }

    private fun recognize(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")
        val tessdataPath = call.argument<String>("tessdataPath")
        val language = call.argument<String>("language")
        val mode = call.argument<String>("mode") ?: "fullCard"
        if (imagePath.isNullOrBlank() || tessdataPath.isNullOrBlank() || language.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "imagePath, tessdataPath and language are required", null)
            return
        }
        if (mode !in setOf("fullCard", "arabicNames", "nationalId", "birthDate")) {
            result.error("INVALID_ARGUMENT", "Unknown OCR mode", null)
            return
        }

        val imageFile = File(imagePath)
        if (!imageFile.isFile || imageFile.length() == 0L) {
            result.error("IMAGE_NOT_FOUND", "OCR input image is missing or empty", null)
            return
        }

        val tessdataDirectory = File(tessdataPath, "tessdata")
        val missingLanguages =
            language.split("+").filter { code ->
                val trainedData = File(tessdataDirectory, "$code.traineddata")
                !trainedData.isFile || trainedData.length() == 0L
            }
        if (missingLanguages.isNotEmpty()) {
            result.error(
                "TESSDATA_INVALID",
                "Missing traineddata for: ${missingLanguages.joinToString(",")}",
                null,
            )
            return
        }

        Log.i(
            LOG_TAG,
            "stage=native_start imageBytes=${imageFile.length()} language=$language mode=$mode tessdata=present",
        )
        ocrExecutor.execute {
            var api: TessBaseAPI? = null
            var initialized = false
            try {
                api = TessBaseAPI()
                val initSucceeded = api.init(tessdataPath, language)
                if (!initSucceeded) {
                    Log.e(LOG_TAG, "stage=native_init status=failed initReturned=false")
                    postError(result, "INIT_FAILED", "TessBaseAPI.init returned false")
                    return@execute
                }
                initialized = true
                api.setPageSegMode(
                    when (mode) {
                        "nationalId", "birthDate" -> TessBaseAPI.PageSegMode.PSM_SINGLE_LINE
                        else -> TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT
                    },
                )
                api.setVariable("preserve_interword_spaces", "1")
                if (mode == "nationalId" || mode == "birthDate") {
                    val allowed = if (mode == "nationalId") "0123456789 .·-" else "0123456789/.- "
                    if (!api.setVariable(TessBaseAPI.VAR_CHAR_WHITELIST, allowed)) {
                        postError(result, "CONFIG_FAILED", "Could not configure numeric OCR")
                        return@execute
                    }
                }
                api.setImage(imageFile)
                val recognizedText = api.utF8Text ?: ""
                Log.i(
                    LOG_TAG,
                    "stage=native_complete status=success characters=${recognizedText.length}",
                )
                mainHandler.post { result.success(recognizedText) }
            } catch (error: Throwable) {
                val code = if (initialized) "OCR_EXECUTION_FAILED" else "INIT_FAILED"
                Log.e(
                    LOG_TAG,
                    "stage=${if (initialized) "native_recognize" else "native_init"} " +
                        "status=failed code=$code type=${error.javaClass.simpleName} " +
                        "mode=$mode",
                )
                postError(
                    result,
                    code,
                    "${error.javaClass.simpleName} during $mode",
                )
            } finally {
                try {
                    api?.recycle()
                } catch (recycleError: Throwable) {
                    Log.w(
                        LOG_TAG,
                        "stage=native_cleanup status=failed type=${recycleError.javaClass.simpleName}",
                    )
                }
            }
        }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ocrChannel?.setMethodCallHandler(null)
        ocrChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        ocrExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val OCR_CHANNEL = "firepin/identity_ocr"
        private const val LOG_TAG = "FirePinIdentityOCR"
    }
}
