package ai.allo.car.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import ai.allo.car.model.SessionMeta
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** The QR contains only the session and pairing code; configuration is never shown in the UI. */
@Composable
fun PairingScreen(meta: SessionMeta, dbUrl: String, sessionId: String = "") {
    val ready = dbUrl.isNotBlank() && sessionId.isNotBlank() && meta.pairCode.matches(Regex("[0-9]{6}"))
    val payload = if (ready) "allo://pair?sid=$sessionId&code=${meta.pairCode}" else null
    val qr = remember(payload) { payload?.let { qrBitmap(it, 512) } }
    ScreenFrame("폰 연결", if (ready) "폰 연결 기다리는 중" else "연결 준비 중") {
        BoxWithConstraints(Modifier.fillMaxSize()) {
        val qrSize = if (maxWidth < 720.dp) minOf(160.dp, maxHeight * 0.4f) else 220.dp
        ScreenColumns(
            art = {
                if (qr != null) {
                    Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Color.White).padding(20.dp)) {
                        Image(bitmap = qr.asImageBitmap(), contentDescription = "폰 연결 QR 코드",
                            modifier = Modifier.size(qrSize))
                    }
                } else AlloWordmark(Modifier.width(220.dp).height(140.dp))
            },
            details = {
                Text(if (ready) "폰에서 알로를 열어 주세요" else "연결을 준비하고 있어요",
                    style = MaterialTheme.typography.headlineMedium)
                Text(if (ready) "QR을 스캔하거나 연결 코드를 입력해 주세요."
                    else "잠시 후 다시 확인해 주세요. 준비가 끝나면 연결 코드를 보여드려요.",
                    style = MaterialTheme.typography.bodyLarge, color = AlloColors.MistDim)
                if (ready) {
                    Text("연결 코드", style = MaterialTheme.typography.bodyMedium, color = AlloColors.MistDim)
                    Text(meta.pairCode.chunked(1).joinToString(" "),
                        style = MaterialTheme.typography.headlineLarge, color = AlloColors.Egg)
                }
                Text("폰이 연결되면 함께할 친구를 확인해요.",
                    style = MaterialTheme.typography.bodyMedium, color = AlloColors.MistDim)
            },
        )
        }
    }
}

private fun qrBitmap(text: String, size: Int): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
    for (x in 0 until size) for (y in 0 until size)
        bmp.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    return bmp
}
