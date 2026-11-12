package ai.allo.car.gleo

import ai.allo.car.model.AffinitySummary
import ai.allo.car.model.GameState
import ai.allo.car.model.TransferStatus
import ai.allo.car.model.TransferUiState
import org.junit.Assert.*
import org.junit.Test

class GleoV2FunctionsTest {
    private fun game(stage: String, ready: Boolean = false) = GameState(contractVersion = 2,
        gameRevision = 1, stage = stage, progress = .5, affinity = AffinitySummary(if (ready) 3 else 1, 3, ready))

    @Test fun readyMeansWaitingForDeadlineAndNeverHatched() {
        val report = GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, game("incubating", true))
        assertTrue(report.message.contains("준비"))
        assertTrue(report.message.contains("기다"))
        assertFalse(report.message.contains("깨어났"))
        val celebrate = GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, game("incubating", true))
        assertEquals("fail", celebrate.status)
        assertFalse(celebrate.message.contains("깨어났"))
    }

    @Test fun failedIsDistinctAndNonBlamingForBothVoiceCommands() {
        for (command in listOf(GleoFunctions.REPORT_EGG_STATUS, GleoFunctions.CELEBRATE_HATCH)) {
            val cb = GleoFunctions.respond(command, game("failed"))
            assertTrue(cb.message.contains("깨어나지 않았"))
            assertFalse(cb.message.contains("축하"))
            assertFalse(cb.message.contains("잘못"))
            assertFalse(cb.message.contains("아직 품고 있는 알이 없"))
        }
        assertEquals("fail", GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, game("failed")).status)
    }

    @Test fun unsupportedVersionNeverGetsSuccessHatchVoice() {
        val invalid = GameState(contractVersion = 99, gameRevision = 1, stage = "hatched")
        assertEquals("fail", GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, invalid).status)
        assertFalse(GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, invalid).message.contains("깨어났"))
    }

    @Test fun newTransferFunctionCannotPretendCompletionWithoutControllerResult() {
        assertTrue(GleoFunctions.REQUEST_COMPANION_TRANSFER in GleoFunctions.FUNCTIONS)
        val without = GleoFunctions.respond(GleoFunctions.REQUEST_COMPANION_TRANSFER, game("hatched"))
        assertEquals("fail", without.status)
        val pending = GleoFunctions.respondCompanionTransfer(TransferUiState(TransferStatus.Waiting, "폰의 이동 결과를 기다리고 있어요."))
        assertEquals("asking", pending.status)
        assertFalse(pending.message.contains("이동했"))
        assertEquals("fail", GleoFunctions.respondCompanionTransfer(TransferUiState(TransferStatus.Disconnected, "폰 연결을 확인해 주세요.")).status)
        assertEquals("success", GleoFunctions.respondCompanionTransfer(TransferUiState(TransferStatus.AlreadyOnPhone, "친구가 이미 폰에 있어요.")).status)
    }
    @Test fun photoAndPendingAreNotCelebrated() {
        for (phase in listOf("photoRequired", "resultPending")) {
            val g=game("incubating").copy(affinity=AffinitySummary(if(phase=="photoRequired") 50.0 else 100.0,100,
                phase=phase,photoCompleted=phase=="resultPending"))
            val report=GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS,g)
            assertTrue(report.message.contains(if(phase=="photoRequired") "사진 퀘스트" else "저장"))
            val celebration=GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH,g)
            assertEquals("fail",celebration.status);assertFalse(celebration.message.contains("축하"))
        }
    }

}
