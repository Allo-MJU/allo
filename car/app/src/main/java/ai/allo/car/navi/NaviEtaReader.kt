package ai.allo.car.navi

import android.content.Context
import android.util.Log
import ai.pleos.playground.navi.constants.NaviErrorCode
import ai.pleos.playground.navi.constants.NavigationStatus
import ai.pleos.playground.navi.data.CurrentLocationInfo
import ai.pleos.playground.navi.data.DestinationInfo
import ai.pleos.playground.navi.data.DrivingInfo
import ai.pleos.playground.navi.data.RouteInfo
import ai.pleos.playground.navi.data.TripInfo
import ai.pleos.playground.navi.helper.NaviHelper
import ai.pleos.playground.navi.helper.listener.NaviHelperEventListener
import ai.allo.car.vehicle.GeoPoint
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * NaviHelper → 남은 시간(etaSec) + 현재 위치(차 안 전용). 판정하지 않는다 — 폰의 HatchTimer 가 ETA 50% 지점을 계산한다.
 * ⚠️ 좌표(현재 위치·DestinationInfo.latitude 등)는 읽어도 밖으로 내보내지 않는다 (CLAUDE.md 규칙 2).
 *    현재 위치는 RegionTagger(지역 태그)와 DestinationSuggester(가까운 목적지)에만 쓴다. 로그에도 찍지 않는다.
 * 남은 시간 출처는 DestinationInfo.remainTime. 단위·갱신 주기는 docs/verification.md #3 실측 기준.
 */
class NaviEtaReader(context: Context) {
    private val navi = NaviHelper(context.applicationContext)

    private val _etaSec = MutableStateFlow<Long?>(null)
    val etaSec: StateFlow<Long?> = _etaSec

    /** 현재 위치. 메모리에만 둔다. 내비가 아직 안 알려줬으면 null */
    private val _position = MutableStateFlow<GeoPoint?>(null)
    val position: StateFlow<GeoPoint?> = _position

    /** 마지막 목적지 도착 시각 (세션 종료 판단용). 도착 이벤트가 없었으면 null */
    private val _arrivedAt = MutableStateFlow<Long?>(null)
    val arrivedAt: StateFlow<Long?> = _arrivedAt

    @Volatile private var status: String? = null
    @Volatile private var remainSec: Int? = null
    @Volatile private var ready = false

    private val listener = object : NaviHelperEventListener {
        override fun onNavigationStatus(s: NavigationStatus) {
            status = s.name
            if (s != NavigationStatus.ROUTE_DRIVE) remainSec = null
            publish("status=${s.name}")
        }
        override fun onDestinationInfo(info: DestinationInfo) {
            remainSec = info.remainTime
            publish("destination remainTime=${info.remainTime} remainDistance=${info.remainDistance}")
        }
        override fun onDrivingInfo(info: DrivingInfo) {
            Log.d(TAG, "drivingInfo destination duration=${info.destination?.duration} distance=${info.destination?.distance}")
        }
        override fun onTripInfo(info: TripInfo) {
            Log.d(TAG, "tripInfo eta=${info.eta} distance=${info.distance}")
        }
        override fun onRouteEnded() { status = null; remainSec = null; publish("route ended") }
        override fun onRouteCancelled() { status = null; remainSec = null; publish("route cancelled") }
        override fun onDestinationArrived(info: ai.pleos.playground.navi.data.DestinationArrivedInfo) {
            remainSec = null; _arrivedAt.value = System.currentTimeMillis(); publish("arrived")
        }
        override fun onCurrentLocationInfo(info: CurrentLocationInfo) {
            _position.value = GeoPoint(info.latitude, info.longitude)
        }
        override fun onError(code: NaviErrorCode) { Log.w(TAG, "navi error $code") }
    }

    fun start() {
        runCatching {
            navi.initialize({
                ready = true
                navi.addListener(listener)
                poll()
            }, { e -> Log.w(TAG, "navi init failed: ${e.message}") })
        }.onFailure { Log.e(TAG, "navi start failed", it) }
    }

    /** 이벤트가 안 오는 구간을 메우려고 SessionManager 가 주기적으로 부른다. */
    fun poll() {
        if (!ready) return
        runCatching { navi.getDestinationInfo() }.onFailure { Log.w(TAG, "getDestinationInfo failed", it) }
        runCatching { navi.getCurrentLocationInfo() }.onFailure { Log.w(TAG, "getCurrentLocationInfo failed", it) }
    }

    /** 목적지 설정. 목적지 제안(A-5)과 디버그 확인에 쓴다. 좌표는 내비에만 넘기고 Firebase 로 보내지 않는다. */
    /** @return 내비에 요청을 넘겼으면 true. 초기화 전이거나 SDK 예외면 false */
    fun requestRoute(latitude: Double, longitude: Double, name: String): Boolean {
        if (!ready) { Log.w(TAG, "requestRoute before init"); return false }
        return runCatching {
            navi.requestRoute(RouteInfo(latitude = latitude, longitude = longitude, poiName = name, poiId = "", address = "", poiSubId = ""))
        }.onFailure { Log.w(TAG, "requestRoute failed", it) }.isSuccess
    }

    fun stop() {
        runCatching { navi.removeListener(listener); navi.release() }
        ready = false
    }

    private fun publish(why: String) {
        _etaSec.value = NaviEta.etaSec(status, remainSec)
        Log.d(TAG, "$why → etaSec=${_etaSec.value}")
    }

    private companion object { const val TAG = "NaviEtaReader" }
}
