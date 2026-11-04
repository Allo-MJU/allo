package ai.allo.car.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import ai.pleos.playground.llm.LLM
import ai.pleos.playground.llm.constant.Mode
import ai.pleos.playground.llm.data.ModelParameter
import ai.pleos.playground.llm.listener.ResultListener

/**
 * 디버그 빌드 전용. Pleos 온디바이스 LLM 스모크 테스트 (docs/ai-dialogue-design.md 8절 · 9절).
 * 한국어 품질·지연·검증기 통과율을 재는 용도이고 제품 코드가 아니다. release 빌드엔 들어가지 않는다.
 *
 *   adb shell am broadcast -a ai.allo.car.debug.LLM -n ai.allo.car/.debug.DebugLlmReceiver --es prompt "..." [--es id t01] [--es max 80]
 *   adb logcat -s DebugLlm
 *
 * 로그 한 줄: `result id=t01 ms=1234 len=23 text=...`. 실패: `error id=t01 ms=... msg=...`
 * ⚠️ 프롬프트에 게임 상태 단어만 넣는다. 아이 이름·위치·자유 발화를 넣지 않는다 (설계 원칙 1).
 */
class DebugLlmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prompt = intent.getStringExtra("prompt") ?: return
        val id = intent.getStringExtra("id") ?: "t"
        val max = intent.getStringExtra("max")
        val llm = Holder.get(context.applicationContext)
        max?.let { llm.setModelParameter(ModelParameter.MAX_TOKENS, it, object : ResultListener {
            override fun onResponse(r: String, done: Boolean) { Log.d(TAG, "param MAX_TOKENS=$it → $r") }
            override fun onError(e: String) { Log.w(TAG, "param MAX_TOKENS failed: $e") }
        }) }
        run(llm, id, prompt, attempt = 0, startedAt = SystemClock.elapsedRealtime())
    }

    /** "Model is not running" 이면 initialize 가 아직 안 끝난 것 → 500ms 간격으로 최대 40번(20초) 재시도 */
    private fun run(llm: LLM, id: String, prompt: String, attempt: Int, startedAt: Long) {
        val t0 = SystemClock.elapsedRealtime()
        val sb = StringBuilder()
        llm.generateContent(prompt, object : ResultListener {
            override fun onResponse(text: String, done: Boolean) {
                sb.append(text)
                if (done) {
                    val out = sb.toString().replace("\n", "⏎")
                    Log.d(TAG, "result id=$id ms=${SystemClock.elapsedRealtime() - t0} wait=${t0 - startedAt} len=${sb.length} text=$out")
                }
            }
            override fun onError(e: String) {
                if (e.contains("not running", ignoreCase = true) && attempt < 40) {
                    if (attempt == 0) Log.d(TAG, "waiting for model… id=$id")
                    Handler(Looper.getMainLooper()).postDelayed({ run(llm, id, prompt, attempt + 1, startedAt) }, 500)
                } else {
                    Log.w(TAG, "error id=$id ms=${SystemClock.elapsedRealtime() - startedAt} attempt=$attempt msg=$e")
                }
            }
        })
    }

    private object Holder {
        private var llm: LLM? = null
        fun get(context: Context): LLM = llm ?: LLM(context, Mode.ON_DEVICE).also {
            Log.d(TAG, "initialize ON_DEVICE")
            runCatching { it.initialize() }.onFailure { e -> Log.w(TAG, "initialize failed", e) }
            llm = it
        }
    }

    private companion object { const val TAG = "DebugLlm" }
}
