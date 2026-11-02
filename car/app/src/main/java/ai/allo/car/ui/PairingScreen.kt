package ai.allo.car.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import ai.allo.car.R
import ai.allo.car.model.SessionMeta
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/**
 * QR + 6자리 코드. QR 내용은 "allo://pair?sid={sessionId}&code={pairCode}" 형식.
 * ⚠️ QR 에 DB URL 은 넣지 않는다. 폰 앱은 자기 firebase_options 로 붙는다.
 */
@Composable
fun PairingScreen(meta: SessionMeta, dbUrl: String, sessionId: String = "") {
    val payload = "allo://pair?sid=$sessionId&code=${meta.pairCode}"
    val qr = remember(payload) { qrBitmap(payload, 512) }
    Row(
        modifier = Modifier.fillMaxSize().padding(48.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Image(bitmap = qr.asImageBitmap(), contentDescription = "pairing QR", modifier = Modifier.size(360.dp))
        Spacer(Modifier.width(48.dp))
        Column {
            Text(stringResource(R.string.pairing_title), style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.pairing_code, meta.pairCode), style = MaterialTheme.typography.displayMedium)
            if (dbUrl.isBlank()) {
                Spacer(Modifier.height(24.dp))
                Text("ALLO_DB_URL 이 비어 있어요 (car/local.properties)", style = MaterialTheme.typography.bodyLarge)
            }
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
