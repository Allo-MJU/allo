package ai.allo.car.dialogue

import ai.allo.car.gleo.DestinationFlow
import ai.allo.car.gleo.DestinationSuggester
import ai.allo.car.gleo.GleoFunctions
import ai.allo.car.gleo.NoSuggestion
import ai.allo.car.gleo.Suggestion
import ai.allo.car.model.GameState
import java.io.File
import kotlin.random.Random
import kotlin.test.*

class DialogueBankTest {
    @Test fun `josa follows batchim`() {
        assertEquals("가", DialogueBank.josa("물결지기", "이", "가"))
        assertEquals("이", DialogueBank.josa("산정령", "이", "가"))
        assertEquals("으로", DialogueBank.josa("북한산 국립공원", "으로", "로"))
        assertEquals("으로", DialogueBank.josa("을왕리해수욕장", "으로", "로"))   // 장: ㅇ 받침
        assertEquals("로", DialogueBank.josa("대구 동성로", "으로", "로"))        // 로: 받침 없음
        assertEquals("로", DialogueBank.josa("서울", "으로", "로"))   // ㄹ 받침
        assertEquals("로", DialogueBank.josa("N서울타워", "으로", "로"))
        assertEquals("라면", DialogueBank.josa("바다", "이라면", "라면"))
        assertEquals("이라면", DialogueBank.josa("산", "이라면", "라면"))
    }

    @Test fun `render fills placeholders and josa or gives null`() {
        assertEquals("물결지기가 깨어났어요!", DialogueBank.render("{name}{name:이/가} 깨어났어요!", mapOf("name" to "물결지기")))
        assertEquals("산정령이 깨어났어요!", DialogueBank.render("{name}{name:이/가} 깨어났어요!", mapOf("name" to "산정령")))
        assertNull(DialogueBank.render("{name}{name:이/가} 깨어났어요!", emptyMap()))
        assertNull(DialogueBank.render("{place}까지 {km}", mapOf("place" to "을왕리")))
    }

    @Test fun `lookup order species then attribute then any`() {
        val bank = DialogueBank(
            mapOf("q|tide_keeper|s" to listOf("종"), "q|@water|s" to listOf("속성"), "q|*|s" to listOf("전체"), "q|*|t" to listOf("전체만")),
            mapOf("tide_keeper" to DialogueBank.Species("물결지기", "water")),
        )
        assertEquals("종", bank.line("q", "tide_keeper", null, "s"))
        assertEquals("속성", bank.line("q", "puddle_pip", "water", "s"))
        assertEquals("전체", bank.line("q", null, null, "s"))
        assertEquals("전체만", bank.line("q", "tide_keeper", null, "t"))
        assertNull(bank.line("q", null, null, "없는상황"))
    }

    @Test fun `skips lines whose values are missing and avoids repeating`() {
        val bank = DialogueBank(mapOf("q|*|s" to listOf("{name} 안녕", "그냥 안녕", "또 안녕")), random = Random(1))
        repeat(20) { assertNotEquals("{name} 안녕", bank.line("q", null, null, "s")) }
        var prev: String? = null
        repeat(20) { val l = bank.line("q", null, null, "s"); assertNotEquals(prev, l); prev = l }
    }

    @Test fun `unreviewed entries are excluded unless asked`() {
        val json = """{"entries":[{"key":"a|*|s","reviewedBy":null,"lines":["x"]},{"key":"b|*|s","reviewedBy":"B","lines":["y"]}]}"""
        assertEquals(1, DialogueBank.parse(json, null, includeUnreviewed = false).size)
        assertEquals(2, DialogueBank.parse(json, null, includeUnreviewed = true).size)
    }

    // ---- 실제 data/dialogue.json (단위 테스트 작업 디렉터리 = car/app)
    private val real by lazy {
        DialogueBank.parse(File("../../data/dialogue.json").readText(), File("../../data/species.json").readText(), includeUnreviewed = true)
    }

    @Test fun `real bank renders every car voice situation`() {
        val hatched = GameState(stage = "hatched", speciesId = "tide_keeper", attribute = "water", tier = 3)
        val incubating = GameState(stage = "incubating", eggTier = "mid", progress = 0.62)
        val cases = listOf(
            GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, incubating, bank = real),
            GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, hatched, bank = real),
            GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, GameState(), bank = real),
            GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, hatched, bank = real),
            GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, incubating, bank = real),
            GleoFunctions.respondAccept(DestinationSuggester.CANDIDATES.first(), real),
            GleoFunctions.respondAccept(null, real),
        ) + NoSuggestion.values().map { GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), DestinationFlow.Offer.None(it), real) } +
            listOf(false to false, true to false, false to true).map { (unvisited, alt) ->
                val d = DestinationSuggester.CANDIDATES.first { it.region == "mountain" }
                GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), DestinationFlow.Offer.Made(Suggestion(d, unvisited, 28.0, alt)), real)
            }
        for (cb in cases) {
            assertFalse('{' in cb.message, cb.message)
            assertTrue(cb.message.isNotBlank())
        }
        // 고정 문장이 아니라 뱅크에서 왔는지: 부화 문장에 종 이름이 들어간다
        assertTrue("물결지기" in GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, hatched, bank = real).message)
    }

    @Test fun `real bank never claims unvisited on fallback`() {
        val d = DestinationSuggester.CANDIDATES.first { it.region == "coast" }
        repeat(10) {
            val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), DestinationFlow.Offer.Made(Suggestion(d, false, 65.0)), real).message
            assertFalse("안 가보셨" in msg, msg)
            assertTrue("을왕리해수욕장" in msg || d.name in msg)
        }
    }

    @Test fun `every species has hatch and name lines`() {
        val ids = Regex(""""id"\s*:\s*"([a-z_]+)"""").findAll(File("../../data/species.json").readText()).map { it.groupValues[1] }.toList()
        assertEquals(12, ids.size)
        for (id in ids) {
            assertNotNull(real.line("hatch", id, null, "hatched"), id)
            assertNotNull(real.line("ask_name", id, null, "hatched"), id)
        }
    }
}
