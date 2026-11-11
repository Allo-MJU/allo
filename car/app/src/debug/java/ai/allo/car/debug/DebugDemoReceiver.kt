package ai.allo.car.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import ai.allo.car.AlloApp
import ai.allo.car.navi.RouteSim

/**
 * 디버그 빌드 전용. PT 시연 조작 (scripts/demo_sea_trip.sh 가 쓴다).
 * 에뮬레이터 내비 위치는 판교로 고정이라 지역 태그가 늘 city 다. 시연에서 바다·산을 보이려면 지역을 덮어쓴다.
 *
 *   adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver --es region coast   # coast|mountain|city|off
 *   adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver --es end now        # 세션 바로 종료
 *   adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver --es route "right:220,left:560,uturn:900"  # 가짜 경로 안내, off 로 끔
 *     (--ef heading 90 을 함께 주면 시작 방향. 켠 뒤 달린 거리로 남은 거리·방향을 계산한다)
 *   adb logcat -s DebugDemo SessionManager
 *
 * 지역 태그(문자열)·경로 안내(회전 종류·남은 거리·방향)만 바뀐다. 좌표는 만들지도 보내지도 않는다.
 */
class DebugDemoReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val session = (context.applicationContext as AlloApp).session
        intent.getStringExtra("region")?.let { r ->
            val v = r.takeUnless { it == "off" }
            if (v != null && v !in REGIONS) { Log.w(TAG, "region must be one of $REGIONS or off: $r"); return@let }
            session.regionTagger.override = v
            Log.d(TAG, "region override=$v")
        }
        intent.getStringExtra("route")?.let { spec ->
            if (spec == "off") { session.routeSim = null; Log.d(TAG, "route off"); return@let }
            val sim = RouteSim.parse(spec, intent.getFloatExtra("heading", 0f).toDouble())
            if (sim == null) { Log.w(TAG, "route must look like right:220,left:560 (types $ROUTE_TYPES): $spec"); return@let }
            session.routeSim = sim
            Log.d(TAG, "route on: $spec")
        }
        if (intent.getStringExtra("end") != null) {
            session.endSession("debug")
            Log.d(TAG, "end requested")
        }
    }

    private companion object {
        const val TAG = "DebugDemo"
        val REGIONS = setOf("coast", "mountain", "city")
        const val ROUTE_TYPES = "left|right|uturn|keepLeft|keepRight"
    }
}
