package ai.allo.car.gleo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ai.allo.car.AlloApp
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Gleo → 앱 브로드캐스트. action = schema.json 의 function.name.
 * 응답은 APP_ACTION_RESPONSE 브로드캐스트로 돌려준다 (검증 #7 에서 실제 포맷 확인 후 조정).
 * 보낸 쪽 신원을 확인할 방법이 문서에 없으므로 입력 extras 를 신뢰하지 않고, 읽기 전용 상태만 응답한다.
 */
class GleoReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val function = intent.action?.takeIf { it in GleoFunctions.FUNCTIONS } ?: return
        val app = context.applicationContext as AlloApp
        val callback = GleoFunctions.respond(function, app.session.game.value)
        context.sendBroadcast(Intent(RESPONSE_ACTION).apply {
            putExtra("result", callback.status)
            putExtra("packageName", context.packageName)
            putExtra("response", Json.encodeToString(callback))
        })
    }

    companion object {
        const val RESPONSE_ACTION = "ai.pleos.playground.intent.action.APP_ACTION_RESPONSE"
    }
}
