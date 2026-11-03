package ai.allo.car.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ai.allo.car.AlloApp

/**
 * 디버그 빌드 전용. 에뮬레이터 내비에 목적지를 넣어 NaviHelper ETA(검증 #3)를 확인한다.
 *   adb shell am broadcast -a ai.allo.car.debug.ROUTE -n ai.allo.car/.debug.DebugRouteReceiver \
 *     --ef lat 37.7644 --ef lng 128.8996 --es name "Gangneung Station"
 * 좌표는 내비에만 넘긴다. Firebase 로 나가지 않는다.
 */
class DebugRouteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!intent.hasExtra("lat") || !intent.hasExtra("lng")) return
        val session = (context.applicationContext as AlloApp).session
        session.naviEta.requestRoute(
            latitude = intent.getFloatExtra("lat", 0f).toDouble(),
            longitude = intent.getFloatExtra("lng", 0f).toDouble(),
            name = intent.getStringExtra("name") ?: "debug",
        )
    }
}
