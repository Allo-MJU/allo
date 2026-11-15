package ai.allo.car.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import ai.allo.car.model.SessionMeta
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** The QR contains only the session and pairing code; configuration is never shown in the UI. */
@Composable
fun PairingScreen(meta: SessionMeta, dbUrl: String, sessionId: String = "",
    onRenewCode: (() -> Unit)? = null, renewing: Boolean = false, renewalMessage: String? = null) {
    val ready = !renewing && renewalMessage == null && dbUrl.isNotBlank() && sessionId.isNotBlank() && meta.pairCode.matches(Regex("[0-9]{6}"))
    val payload = if (ready) "allo://pair?sid=$sessionId&code=${meta.pairCode}" else null
    val qr = remember(payload) { payload?.let { qrBitmap(it, 512) } }
    ScreenFrame("폰 연결", if (ready) "폰 연결 기다리는 중" else "연결 준비 중") {
        ScreenColumns(
            art = { artSize ->
                val qrSize = (artSize - 40.dp).coerceAtLeast(64.dp)
                if (qr != null) {
                    Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Color.White).padding(20.dp)) {
                        Image(bitmap = qr.asImageBitmap(), contentDescription = "폰 연결 QR 코드",
                            modifier = Modifier.size(qrSize))
                    }
                } else AlloWordmark(Modifier.width(artSize).height(artSize * .65f))
            },
            details = {
                Text(if (ready) "폰과 연결하면 준비 완료" else "연결을 준비하고 있어요",
                    style = MaterialTheme.typography.headlineMedium)
                Text(if (ready) "폰의 알로 앱에서 QR을 스캔해 주세요."
                    else "잠시 후 다시 확인해 주세요. 준비가 끝나면 연결 코드를 보여드려요.",
                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (ready) {
                    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp),
                        color = MaterialTheme.colorScheme.primaryContainer) {
                        BoxWithConstraints(Modifier.padding(20.dp)) {
                            val codeSize = minOf(44f, maxWidth.value / (5.2f * LocalDensity.current.fontScale)).sp
                            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("직접 입력할 연결 코드", style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer)
                                Text(meta.pairCode.chunked(3).joinToString("  "),
                                    fontSize = codeSize, lineHeight = codeSize * 1.2f,
                                    fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1)
                                Text("직접 입력할 세션 ID", style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer)
                                Text(sessionId, style = MaterialTheme.typography.bodyMedium,
                                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onPrimaryContainer)
                            }
                        }
                    }
                }
                if (onRenewCode != null) {
                    ToyButton(if (renewing) "새 코드 확인 중" else if (renewalMessage != null) "새 코드 다시 확인" else "새 연결 코드",
                        onRenewCode, Modifier.fillMaxWidth(), enabled = !renewing)
                    Text(renewalMessage ?: "코드는 10분 동안 유효해요. 만료되면 새 코드를 받아 주세요.",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("폰이 연결되면 함께할 친구를 확인해요.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            },
        )
    }
}

private fun qrBitmap(text: String, size: Int): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
    for (x in 0 until size) for (y in 0 until size)
        bmp.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    return bmp
}
