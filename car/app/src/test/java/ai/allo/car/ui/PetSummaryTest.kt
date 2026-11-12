package ai.allo.car.ui

import ai.allo.car.model.GameState
import ai.allo.car.model.CompanionDisplay
import kotlin.test.*

class PetSummaryTest {
    private val catalog = SpeciesCatalog.parse("""{"species":[{"id":"tide_keeper","nameKo":"물결지기","attribute":"water","sprite":"species/tide_keeper.png"}]}""")

    @Test fun `hatched state uses species identity instead of showing an egg`() {
        val result = PetSummary.from(GameState(stage = "hatched", speciesId = "tide_keeper"), true, catalog)
        assertEquals("물결지기", result.title)
        assertEquals("함께 가는 중", result.status)
        assertFalse(result.showEgg)
        assertEquals("species/tide_keeper.png", result.species?.sprite)
    }

    @Test fun `incubating state only shows bounded factual progress`() {
        assertEquals("알을 품는 중 · 42%", PetSummary.from(GameState(stage = "incubating", progress = 0.42), true, catalog).status)
        for ((value, percent) in listOf(Double.NaN to 0, Double.POSITIVE_INFINITY to 0, -2.0 to 0, 1.5 to 100)) {
            val result = PetSummary.from(GameState(stage = "incubating", progress = value), true, catalog)
            assertEquals("알을 품는 중 · $percent%", result.status)
            assertTrue(result.showEgg)
        }
    }

    @Test fun `disconnected snapshot does not claim current companion state`() {
        val result = PetSummary.from(GameState(ts = 1, stage = "hatched", speciesId = "tide_keeper"), false, catalog)
        assertEquals("물결지기", result.title)
        assertEquals("마지막으로 받은 상태", result.status)
        assertFalse(result.showEgg)
        val empty = PetSummary.from(GameState(), false, catalog)
        assertEquals("폰 연결을 기다리고 있어요", empty.status)
    }

    @Test fun `unknown species and stages never expose raw IDs or invented pet needs`() {
        val pet = PetSummary.from(GameState(stage = "hatched", speciesId = "unexpected-secret"), true, catalog)
        assertEquals("함께하는 친구", pet.title)
        assertNull(pet.species)
        assertEquals("폰에서 시작을 기다려요", PetSummary.from(GameState(stage = "unexpected"), true, catalog).status)
    }

    @Test fun `catalog excludes paths outside the species asset folder`() {
        val invalid = SpeciesCatalog.parse("""{"species":[{"id":"bad","nameKo":"친구","sprite":"../secret.png"}]}""")
        assertNull(invalid["bad"]?.sprite)
        assertTrue(SpeciesCatalog.parse("not json").entries.isEmpty())
    }
    @Test fun `v2 companion survives incubation of another egg`() {
        val game = GameState(contractVersion = 2, gameRevision = 3, stage = "incubating",
            speciesId = "other", companion = CompanionDisplay("pet", 1, "tide_keeper", "car"))
        val result = PetSummary.from(game, true, catalog)
        assertEquals("물결지기", result.title)
        assertFalse(result.showEgg)
        assertTrue(result.showArt)
    }

    @Test fun `phone companion and absent v2 companion do not show a car pet`() {
        val game = GameState(contractVersion = 2, gameRevision = 3, stage = "hatched",
            speciesId = "tide_keeper", companion = CompanionDisplay("pet", 1, "tide_keeper", "phone"))
        val phone = PetSummary.from(game, true, catalog)
        assertFalse(phone.showArt)
        assertEquals("폰에서 함께하고 있어요", phone.status)
        assertFalse(PetSummary.from(game.copy(companion = null), true, catalog).showArt)
        assertTrue(PetSummary.from(game.copy(companion = null, stage = "incubating"), true, catalog).showEgg)
    }

    @Test fun `unsupported contract cannot substitute a companion`() {
        val game = GameState(contractVersion = 3, gameRevision = 1, stage = "incubating",
            companion = CompanionDisplay("pet", 1, "tide_keeper", "car"))
        assertTrue(PetSummary.from(game, true, catalog).showEgg)
    }
    @Test fun `driving affinity summaries preserve companion and do not invite phone interaction`() {
        for ((phase, label) in listOf("photoRequired" to "사진 퀘스트 대기 중", "resultPending" to "부화 결과 저장 중")) {
            val game=GameState(contractVersion=2,gameRevision=3,stage="incubating",
                affinity=ai.allo.car.model.AffinitySummary(50.0,100,phase=phase,photoCompleted=false))
            val egg=PetSummary.from(game,true,catalog)
            assertEquals(label,egg.status);assertTrue(egg.showEgg)
            val withFriend=PetSummary.from(game.copy(companion=CompanionDisplay("pet",1,"tide_keeper","car")),true,catalog)
            assertEquals("함께 가는 중",withFriend.status);assertFalse(withFriend.showEgg)
            assertEquals("폰 연결을 기다리고 있어요",PetSummary.from(game,false,catalog).status)
        }
    }

}
