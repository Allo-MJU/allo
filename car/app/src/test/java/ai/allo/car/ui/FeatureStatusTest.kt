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
    @Test fun `photo and pending states never claim hatch and keep base independent`() {
        for ((phase, score) in listOf("photoRequired" to 50.0, "resultPending" to 100.0)) {
            val result = FeatureStatus.from(GameState(contractVersion=2, gameRevision=4,
                stage="incubating", progress=.6, affinity=AffinitySummary(score,100,phase=phase,photoCompleted=score==100.0),
                baseSummary=BaseSummary(structureIds=listOf("nest"))),catalog)
            assertEquals("알 품기 진행 · 60%",result.incubation)
            assertFalse(result.affinity!!.contains("부화 완료"))
            assertTrue(result.affinity.contains(if (phase=="photoRequired") "사진 퀘스트" else "저장 중"))
            assertTrue(result.baseLines.contains("시설 · nest"))
        }
    }
    @Test fun `terminal affinity gives final status rather than accumulating`() {
        for ((phase, stage, label) in listOf(Triple("hatched","hatched","부화 완료"), Triple("failed","failed","품기 종료"), Triple("discarded","failed","보내기 완료"))) {
            val result=FeatureStatus.from(GameState(contractVersion=2,gameRevision=5,stage=stage,
                affinity=AffinitySummary(100.0,100,phase=phase,photoCompleted=true)),catalog)
            assertTrue(result.affinity!!.contains(label)); assertFalse(result.affinity.contains("함께 쌓는 중"))
        }
    }

}
