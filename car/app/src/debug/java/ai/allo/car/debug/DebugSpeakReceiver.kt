package ai.allo.car.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ai.allo.car.AlloApp
import ai.allo.car.gleo.GleoFunctions

/**
 * 디버그 빌드 전용. Firebase·폰 없이 운전자 음성(TTS)을 확인한다. release 빌드엔 들어가지 않는다.
 *   adb shell am broadcast -a ai.allo.car.debug.SPEAK -n ai.allo.car/.debug.DebugSpeakReceiver --es text "안녕"
 *   adb shell am broadcast -a ai.allo.car.debug.SPEAK -n ai.allo.car/.debug.DebugSpeakReceiver --es fn CELEBRATE_HATCH
 */
class DebugSpeakReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val session = (context.applicationContext as AlloApp).session
        val text = intent.getStringExtra("text")
            ?: intent.getStringExtra("fn")?.let { GleoFunctions.respond(it, session.game.value).message }
            ?: return
        session.voice.speak(text)
    }
}
