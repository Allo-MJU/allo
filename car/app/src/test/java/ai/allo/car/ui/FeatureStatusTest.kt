package ai.allo.car.ui

import ai.allo.car.model.*
import kotlin.test.*

class FeatureStatusTest {
    private val catalog = SpeciesCatalog.EMPTY
    @Test fun `ready affinity never implies a hatch or replaces progress`() {
        val result = FeatureStatus.from(GameState(contractVersion=2, gameRevision=1,
            stage="incubating", progress=.4, affinity=AffinitySummary(10,10,true)), catalog)
        assertEquals("알 품기 진행 · 40%", result.incubation)
        assertEquals("호감도 · 10 / 10 · 준비 완료", result.affinity)
    }
    @Test fun `failed stage has calm completion and no progress success`() {
        val result = FeatureStatus.from(GameState(contractVersion=2,gameRevision=1,stage="failed",progress=1.0),catalog)
        assertEquals("이번 알 품기는 마무리됐어요. 다음 알과 다시 함께해요.",result.incubation)
    }
    @Test fun `base is independent from egg and invalid blocks are hidden`() {
        val game=GameState(contractVersion=2,gameRevision=1,stage="incubating",baseSummary=BaseSummary(structureIds=listOf("nest")))
        assertTrue(FeatureStatus.from(game,catalog).baseLines.contains("시설 · nest"))
        assertTrue(FeatureStatus.from(game.copy(invalidBlocks=setOf("baseSummary")),catalog).baseLines.isEmpty())
        assertTrue(FeatureStatus.from(game.copy(contractVersion=null),catalog).baseLines.isEmpty())
    }
}
