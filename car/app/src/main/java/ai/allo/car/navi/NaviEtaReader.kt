package ai.allo.car.navi

import android.content.Context
import android.util.Log
import ai.pleos.playground.navi.constants.NaviErrorCode
import ai.pleos.playground.navi.constants.NavigationStatus
import ai.pleos.playground.navi.data.CurrentLocationInfo
import ai.pleos.playground.navi.data.DestinationInfo
import ai.pleos.playground.navi.data.DrivingInfo
import ai.pleos.playground.navi.data.RouteInfo
import ai.pleos.playground.navi.data.RouteStateInfo
import ai.pleos.playground.navi.data.TBTInfo
import ai.pleos.playground.navi.data.TripInfo
import ai.pleos.playground.navi.helper.NaviHelper
import ai.pleos.playground.navi.helper.listener.NaviHelperEventListener
import ai.allo.car.model.Turn
import ai.allo.car.vehicle.GeoPoint
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * NaviHelper → 남은 시간(etaSec) + 다음 회전(turns) + 진행 방향(headingDeg) + 현재 위치(차 안 전용). 판정하지 않는다 — 폰의 HatchTimer 가 ETA 50% 지점을 계산한다.
 * ⚠️ 좌표(현재 위치·DestinationInfo.latitude 등)는 읽어도 밖으로 내보내지 않는다 (CLAUDE.md 규칙 2).
 *    현재 위치는 RegionTagger(지역 태그)와 DestinationSuggester(가까운 목적지)에만 쓴다. 로그에도 찍지 않는다.
 * 남은 시간 출처는 DestinationInfo.remainTime. 단위·갱신 주기는 docs/verification.md #3 실측 기준.
 */
class NaviEtaReader(context: Context) {
    private val navi = NaviHelper(context.applicationContext)
    var onVisitRouteStarted: (() -> Unit)? = null
    var onVisitDestination: ((String?, String?, String?, String?, Double, Double) -> Unit)? = null
    var onVisitRouteCancelled: (() -> Unit)? = null
    var onVisitRouteEnded: (() -> Unit)? = null
    var onVisitArrived: ((String?, Long) -> Unit)? = null

    private val _etaSec = MutableStateFlow<Long?>(null)
    val etaSec: StateFlow<Long?> = _etaSec

    /** 현재 위치. 메모리에만 둔다. 내비가 아직 안 알려줬으면 null */
    private val _position = MutableStateFlow<GeoPoint?>(null)
    val position: StateFlow<GeoPoint?> = _position

    /** 마지막 목적지 도착 시각 (세션 종료 판단용). 도착 이벤트가 없었으면 null */
    private val _arrivedAt = MutableStateFlow<Long?>(null)
    val arrivedAt: StateFlow<Long?> = _arrivedAt

    /** 경로 안내 상태. ETA 와 독립 ([Guidance]). 처음과 내비 연결 전에는 UNKNOWN */
    private val _guidance = MutableStateFlow(Guidance.UNKNOWN)
    val guidance: StateFlow<Guidance> = _guidance

    /** 다음 회전, 가까운 순 최대 3개 ([NaviTurns]). 경로 안내 중이 아니면 빈 목록. 도로명(description)은 담지 않는다 */
    private val _turns = MutableStateFlow<List<Turn>>(emptyList())
    val turns: StateFlow<List<Turn>> = _turns

    /** 차 진행 방향(도, 0~360, 북쪽 0) ([NaviHeading]). 위치 콜백 전·NaN·내비 중지 시 null. 좌표는 담지 않는다 */
    private val _headingDeg = MutableStateFlow<Double?>(null)
    val headingDeg: StateFlow<Double?> = _headingDeg

    /** onTBTInfo 원본에서 (TurnType 이름, 거리)만 남긴 것. 경로가 끝나거나 취소되면 비운다 */
    @Volatile private var rawTurns: List<Pair<String?, Double>> = emptyList()

    @Volatile private var status: String? = null
    @Volatile private var remainSec: Int? = null
    @Volatile private var ready = false

    private val listener = object : NaviHelperEventListener {
        override fun onNavigationStatus(s: NavigationStatus) {
            status = s.name
            setGuidance(Guidance.fromStatus(s.name))
            if (s != NavigationStatus.ROUTE_DRIVE) remainSec = null
            publish("status=${s.name}")
        }
        override fun onDestinationInfo(info: DestinationInfo) {
            onVisitDestination?.invoke(info.name, info.poiProvider, info.poiId, info.poiSubId, info.latitude, info.longitude)
            remainSec = info.remainTime
            publish("destination remainTime=${info.remainTime} remainDistance=${info.remainDistance}")
        }
        override fun onDrivingInfo(info: DrivingInfo) {
            Log.d(TAG, "drivingInfo destination duration=${info.destination?.duration} distance=${info.destination?.distance}")
        }
        override fun onTripInfo(info: TripInfo) {
            Log.d(TAG, "tripInfo eta=${info.eta} distance=${info.distance}")
        }
        override fun onRouteStarted(info: ai.pleos.playground.navi.data.RouteStartInfo) { onVisitRouteStarted?.invoke(); setGuidance(Guidance.GUIDING); Log.d(TAG, "route started") }
        override fun onRouteEnded() { onVisitRouteEnded?.invoke(); status = null; remainSec = null; clearTurns(); setGuidance(Guidance.IDLE); publish("route ended") }
        override fun onRouteCancelled() { onVisitRouteCancelled?.invoke(); status = null; remainSec = null; clearTurns(); setGuidance(Guidance.IDLE); publish("route cancelled") }
        override fun onDestinationArrived(info: ai.pleos.playground.navi.data.DestinationArrivedInfo) {
            val at = System.currentTimeMillis(); onVisitArrived?.invoke(info.name, at)
            remainSec = null; clearTurns(); _arrivedAt.value = at; publish("arrived")
        }
        /** 회전 안내. description(도로명·교차로명)은 여기서 버린다 — 저장·로그 모두 하지 않는다 */
        override fun onTBTInfo(list: List<TBTInfo>) {
            rawTurns = list.map { it.type.name to it.distance }
            publishTurns()
        }
        /**
         * 앱이 켜지기 전에 시작된 안내는 onNavigationStatus 가 다시 오지 않는다 → poll 의 getRouteStateInfo 로 채운다.
         * 에뮬레이터 실측: 안내 중에 isRouting=false · naviMode=ROUTE_GUIDING (isRouting 은 경로 탐색 중 여부로 보인다)
         * → naviMode 로 판단한다. 안내 중인데 상태를 모르면 ROUTE_DRIVE 로 본다 (목적지 제안이 진행 중인 경로를 바꾸지 않게)
         */
        override fun onRouteStateInfo(info: RouteStateInfo) {
            val g = Guidance.fromNaviMode(info.naviMode?.name)
            if (g != Guidance.UNKNOWN) setGuidance(g)
            val guiding = g == Guidance.GUIDING
            val before = status
            if (guiding) { if (status == null) status = "ROUTE_DRIVE" }
            else if (status == "ROUTE_DRIVE") { status = null; remainSec = null }
            if (status != before) publish("routeState mode=${info.naviMode}")
        }
        override fun onCurrentLocationInfo(info: CurrentLocationInfo) {
            _position.value = GeoPoint(info.latitude, info.longitude)
            _headingDeg.value = NaviHeading.deg(info.heading)
        }
        override fun onError(code: NaviErrorCode) { Log.w(TAG, "navi error $code") }
    }

    /** @param onReady 내비 초기화 결과. 성공하면 true → capabilities 에 `eta` 를 올린다 (docs/schema.md 3.3) */
    fun start(onReady: (Boolean) -> Unit = {}) {
        runCatching {
            navi.initialize({
                ready = true
                navi.addListener(listener)
                poll()
                onReady(true)
            }, { e -> Log.w(TAG, "navi init failed: ${e.message}"); onReady(false) })
        }.onFailure { Log.e(TAG, "navi start failed", it); onReady(false) }
    }

    /** 이벤트가 안 오는 구간을 메우려고 SessionManager 가 주기적으로 부른다. */
    fun poll() {
        if (!ready) return
        runCatching { navi.getRouteStateInfo() }.onFailure { Log.w(TAG, "getRouteStateInfo failed", it) }
        runCatching { navi.getDestinationInfo() }.onFailure { Log.w(TAG, "getDestinationInfo failed", it) }
        runCatching { navi.getCurrentLocationInfo() }.onFailure { Log.w(TAG, "getCurrentLocationInfo failed", it) }
        if (_guidance.value == Guidance.GUIDING) runCatching { navi.getTBTInfo() }.onFailure { Log.w(TAG, "getTBTInfo failed", it) }
    }

    /** 목적지 설정. 목적지 제안(A-5)과 디버그 확인에 쓴다. 좌표는 내비에만 넘기고 Firebase 로 보내지 않는다. */
    /** @return 내비에 요청을 넘겼으면 true. 초기화 전이거나 SDK 예외면 false */
    fun requestRoute(latitude: Double, longitude: Double, name: String): Boolean {
        if (!ready) { Log.w(TAG, "requestRoute before init"); return false }
        return runCatching {
            navi.requestRoute(RouteInfo(latitude = latitude, longitude = longitude, poiName = name, poiId = "", address = "", poiSubId = ""))
        }.onFailure { Log.w(TAG, "requestRoute failed", it) }.isSuccess
    }

    /** 진행 중인 경로 안내 취소. 디버그·시연 초기화용 (DebugRouteReceiver) */
    fun cancelRoute() {
        if (!ready) return
        runCatching { navi.cancelRoute() }.onFailure { Log.w(TAG, "cancelRoute failed", it) }
    }

    fun stop() {
        runCatching { navi.removeListener(listener); navi.release() }
        ready = false
        _headingDeg.value = null
        clearTurns()
        setGuidance(Guidance.UNKNOWN)
    }

    private fun setGuidance(g: Guidance) {
        if (_guidance.value != g) Log.d(TAG, "guidance ${_guidance.value} → $g")
        _guidance.value = g
        if (g != Guidance.GUIDING) rawTurns = emptyList()   // 다음 안내에 지난 경로의 회전이 섞이지 않게
        publishTurns()
    }

    private fun clearTurns() { rawTurns = emptyList(); publishTurns() }

    private fun publishTurns() {
        val next = NaviTurns.turns(guiding = _guidance.value == Guidance.GUIDING, raw = rawTurns)
        if (next != _turns.value) Log.d(TAG, "turns ${next.joinToString { "${it.type}@${it.inM}" }}") // 종류·거리만. 도로명 없음
        _turns.value = next
    }

    private fun publish(why: String) {
        _etaSec.value = NaviEta.etaSec(status, remainSec)
        Log.d(TAG, "$why → etaSec=${_etaSec.value}")
    }

    private companion object { const val TAG = "NaviEtaReader" }
}
