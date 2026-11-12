package ai.allo.allo_phone

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.media.ExifInterface
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File

/** Transparent proxy stays above Unity so closing the system input restores Unity. */
class EggInputActivity : Activity() {
    private lateinit var id: String
    private var photo: File? = null
    private var photoUri: Uri? = null
    private var completed = false
    private var processing = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        id = intent.getStringExtra("requestId") ?: ""
        state?.getString("photoPath")?.let { path ->
            val file = File(path)
            if (file.parentFile?.canonicalPath == imageDirectory().canonicalPath) {
                photo = file
                photoUri = FileProvider.getUriForFile(this, "$packageName.egg-camera", file)
            }
        }
        // A recreated process has no MethodChannel result: never report a fabricated success.
        if (!EggInputBridge.isPending(id)) {
            cleanup()
            finish()
            return
        }
        if (state != null) {
            if (state.getBoolean("processing")) fail("interrupted", "Photo preparation was interrupted. Please retry.")
            return
        }
        imageDirectory().listFiles()?.forEach { it.delete() }
        when (intent.getStringExtra("kind")) {
            "speech" -> launchSpeech()
            "photo" -> if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                launchCamera()
            } else {
                requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION)
            }
            else -> fail("invalid_request", "Unknown input request.")
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("photoPath", photo?.absolutePath)
        outState.putBoolean("processing", processing)
        super.onSaveInstanceState(outState)
    }

    private fun launchSpeech() {
        launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }, SPEECH)
    }

    private fun launchCamera() {
        try {
            photo = File.createTempFile("capture-", ".jpg", imageDirectory())
            photoUri = FileProvider.getUriForFile(this, "$packageName.egg-camera", photo!!)
            launch(Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                clipData = ClipData.newRawUri("camera output", photoUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }, PHOTO)
        } catch (_: Exception) {
            fail("camera_error", "Cannot prepare camera output.")
        }
    }

    @Suppress("DEPRECATION")
    private fun launch(input: Intent, code: Int) {
        try {
            if (input.resolveActivity(packageManager) == null) {
                fail("unavailable", "No compatible input service is installed.")
                return
            }
            startActivityForResult(input, code)
        } catch (_: SecurityException) {
            fail("permission_denied", "The input service denied permission.")
        } catch (_: Exception) {
            fail("input_error", "Cannot start the input service.")
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code != CAMERA_PERMISSION) return
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) launchCamera()
        else fail("permission_denied", "Camera permission is required to take a photo.")
    }

    @Deprecated("Uses platform activity results for the small proxy activity")
    override fun onActivityResult(code: Int, result: Int, data: Intent?) {
        super.onActivityResult(code, result, data)
        if (code != SPEECH && code != PHOTO) return
        if (result == RESULT_CANCELED) {
            succeed(null)
        } else if (result != RESULT_OK) {
            fail("input_error", "The input service did not finish successfully.")
        } else if (code == SPEECH) {
            val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
            if (text.isNullOrEmpty()) fail("speech_error", "No speech was recognized. Please retry.")
            else if (text.length > 4000) fail("speech_error", "The recognized speech is too long.")
            else succeed(text)
        } else {
            val file = photo
            if (file == null || !file.isFile || file.length() == 0L || file.length() > 64L * 1024 * 1024) {
                fail("photo_error", "The camera did not return a usable photo.")
                return
            }
            processing = true
            Thread {
                val bytes = runCatching { composite(file) }.getOrNull()
                runOnUiThread {
                    if (isDestroyed || completed) return@runOnUiThread
                    if (bytes == null) fail("photo_error", "Cannot prepare the captured photo. Please retry.")
                    else succeed(bytes)
                }
            }.start()
        }
    }

    private fun composite(file: File): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2560) sample *= 2
        val decoded = requireNotNull(BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply {
            inSampleSize = sample
        }))
        val transform = Matrix()
        when (ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> transform.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> transform.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { transform.setRotate(90f); transform.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> transform.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { transform.setRotate(270f); transform.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> transform.setRotate(270f)
        }
        val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
        val scale = minOf(1f, 1280f / maxOf(oriented.width, oriented.height))
        val output = Bitmap.createBitmap(maxOf(1, (oriented.width * scale).toInt()),
            maxOf(1, (oriented.height * scale).toInt()), Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(output)
            canvas.drawBitmap(oriented, null, RectF(0f, 0f, output.width.toFloat(), output.height.toFloat()),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            drawEgg(canvas, output.width.toFloat(), output.height.toFloat())
            // Fresh encoding copies pixels only, dropping source EXIF/GPS metadata.
            return ByteArrayOutputStream().use { stream ->
                check(output.compress(Bitmap.CompressFormat.JPEG, 88, stream))
                stream.toByteArray().also { require(it.isNotEmpty() && it.size <= 5 * 1024 * 1024) }
            }
        } finally {
            output.recycle()
            if (oriented !== decoded) oriented.recycle()
            decoded.recycle()
        }
    }

    private fun drawEgg(canvas: Canvas, width: Float, height: Float) {
        val unit = minOf(width, height) * 0.23f
        val x = width * 0.73f
        val y = height * 0.70f
        canvas.save()
        canvas.translate(x, y)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.argb(75, 55, 39, 23)
        canvas.drawOval(RectF(-unit * .56f, unit * .56f, unit * .56f, unit * .77f), paint)
        val shell = Path().apply {
            moveTo(0f, -unit)
            cubicTo(-unit * .57f, -unit, -unit * .92f, unit * .65f, 0f, unit * .65f)
            cubicTo(unit * .92f, unit * .65f, unit * .57f, -unit, 0f, -unit)
            close()
        }
        paint.color = Color.rgb(255, 240, 193)
        canvas.drawPath(shell, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = unit * .035f
        paint.color = Color.rgb(104, 75, 48)
        canvas.drawPath(shell, paint)
        paint.style = Paint.Style.FILL
        canvas.drawCircle(-unit * .18f, unit * .05f, unit * .045f, paint)
        canvas.drawCircle(unit * .18f, unit * .05f, unit * .045f, paint)
        paint.style = Paint.Style.STROKE
        canvas.drawArc(RectF(-unit * .09f, unit * .10f, unit * .09f, unit * .25f), 0f, 180f, false, paint)
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(244, 170, 138)
        canvas.drawOval(RectF(-unit * .37f, unit * .13f, -unit * .22f, unit * .22f), paint)
        canvas.drawOval(RectF(unit * .22f, unit * .13f, unit * .37f, unit * .22f), paint)
        canvas.restore()
    }

    private fun imageDirectory(): File = File(cacheDir, "egg-camera").apply { mkdirs() }

    private fun succeed(value: Any?) {
        completed = true
        EggInputBridge.complete(id, value)
        cleanup()
        finish()
    }

    private fun fail(code: String, message: String) {
        completed = true
        EggInputBridge.complete(id, error = code, message = message)
        cleanup()
        finish()
    }

    private fun cleanup() {
        photoUri?.let { uri ->
            runCatching { revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) }
        }
        photo?.delete()
        photo = null
    }

    override fun onDestroy() {
        if (isFinishing && !completed && ::id.isInitialized) {
            EggInputBridge.complete(id, error = "interrupted", message = "Input was interrupted. Please retry.")
            cleanup()
        }
        super.onDestroy()
    }

    companion object {
        private const val SPEECH = 1
        private const val PHOTO = 2
        private const val CAMERA_PERMISSION = 3
    }
}
