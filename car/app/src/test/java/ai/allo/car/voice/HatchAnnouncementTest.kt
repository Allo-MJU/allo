package ai.allo.car.voice

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 부화 알림은 incubating → hatched 로 바뀌는 순간 한 번만. 재연결·같은 상태 반복에선 다시 말하지 않는다. */
class HatchAnnouncementTest {
    @Test fun `announces when stage turns from incubating to hatched`() {
        assertTrue(HatchAnnouncement.shouldAnnounce(prevStage = "incubating", stage = "hatched"))
    }

    @Test fun `does not repeat while staying hatched`() {
        assertFalse(HatchAnnouncement.shouldAnnounce(prevStage = "hatched", stage = "hatched"))
    }

    @Test fun `does not announce when first state seen is already hatched`() {
        // 앱이 늦게 붙어 이미 부화한 상태를 처음 받은 경우 — 지난 일을 다시 말하지 않는다
        assertFalse(HatchAnnouncement.shouldAnnounce(prevStage = null, stage = "hatched"))
    }

    @Test fun `does not announce for other stages`() {
        assertFalse(HatchAnnouncement.shouldAnnounce(prevStage = "idle", stage = "incubating"))
        assertFalse(HatchAnnouncement.shouldAnnounce(prevStage = "incubating", stage = "incubating"))
    }
}
