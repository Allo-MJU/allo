package ai.allo.car.vehicle

import ai.allo.car.model.Capability

/**
 * 차종마다 읽히는 신호가 다르다. 세션 시작 때 도메인별 checkXXXCapabilities 를 돌려
 * 실제로 읽히는 것만 모은다. 결과는 /vehicle/capabilities 로 올라가고 폰이 속성 풀을 줄인다.
 */
class CapabilityChecker {
    private val supported = linkedSetOf<String>()

    fun mark(name: String, ok: Boolean) { if (ok) supported += name else supported -= name }
    fun has(name: String) = name in supported
    fun snapshot(): List<String> = supported.toList()

    /** 에뮬레이터·실차 모두에서 AAOS 속도·기어는 항상 기대한다. 실패하면 mark 로 뺀다. */
    fun assumeAaos() { mark(Capability.SPEED, true); mark(Capability.GEAR, true) }
}
