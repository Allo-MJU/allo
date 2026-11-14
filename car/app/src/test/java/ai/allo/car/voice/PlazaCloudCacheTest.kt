package ai.allo.car.voice

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files

class PlazaCloudCacheTest {
    private fun wav(): ByteArray = ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN).apply {
        put("RIFF".toByteArray()); putInt(40); put("WAVEfmt ".toByteArray()); putInt(16)
        putShort(1); putShort(1); putInt(24000); putInt(48000); putShort(2); putShort(16)
        put("data".toByteArray()); putInt(4); putShort(123); putShort(-123)
    }.array()
    private fun config(revision: String = "1", base: String = "https://voice.example") =
        PlazaCloudConfig(base, revision) { "firebase-user-token" }
    private fun directory() = Files.createTempDirectory("plaza-cache").toFile()

    @Test fun `cache is exact by speaker text endpoint and voice revision`() = runBlocking {
        val dir = directory()
        try {
            var calls = 0
            val requests = mutableListOf<String>()
            val download = PlazaDownload { url, token, species, text ->
                calls++; assertEquals("firebase-user-token", token)
                assertTrue(url.endsWith("/v1/plaza/clip")); requests += "$species\n$text"; wav()
            }
            val first = PlazaRecordings.entries[0]
            val second = PlazaRecordings.entries[2]
            val cache = PlazaCloudCache(dir, config(), download)
            val file = cache.resolve(first)
            assertEquals(file, cache.resolve(first)); assertEquals(1, calls)
            assertNotEquals(file, cache.resolve(second)); assertEquals(2, calls)
            assertNotEquals(file, PlazaCloudCache(dir, config("2"), download).resolve(first))
            assertNotEquals(file, PlazaCloudCache(dir, config(base = "https://other.example"), download).resolve(first))
            assertEquals(4, calls)
            assertEquals(PlazaRecordings.request(second.species, second.text), requests[1])
        } finally { dir.deleteRecursively() }
    }

    @Test fun `invalid or interrupted downloads never become cached audio`() = runBlocking {
        val dir = directory()
        try {
            val invalid = PlazaCloudCache(dir, config(), PlazaDownload { _, _, _, _ -> "bad".toByteArray() })
            try { invalid.resolve(PlazaRecordings.entries[0]); fail("Expected invalid WAV") } catch (_: java.io.IOException) { }
            assertEquals(0, dir.listFiles()!!.size)
            val started = CompletableDeferred<Unit>()
            val hanging = PlazaCloudCache(dir, config(), PlazaDownload { _, _, _, _ -> started.complete(Unit); awaitCancellation() })
            val job = launch { hanging.resolve(PlazaRecordings.entries[0]) }
            started.await(); job.cancelAndJoin()
            assertEquals(0, dir.listFiles()!!.size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun `corrupted cache refetches and unknown line never calls cloud`() = runBlocking {
        val dir = directory()
        try {
            var calls = 0
            val cache = PlazaCloudCache(dir, config(), PlazaDownload { _, _, _, _ -> calls++; wav() })
            val entry = PlazaRecordings.entries[0]
            cache.resolve(entry).writeText("partial")
            assertTrue(PlazaCloudCache.validPcmWav(cache.resolve(entry).readBytes()))
            assertEquals(2, calls)
            try { cache.resolve(entry.copy(species = "other")); fail("Unknown character") } catch (_: IllegalArgumentException) { }
            assertEquals(2, calls)
        } finally { dir.deleteRecursively() }
    }

    @Test fun `wave validator rejects truncated odd data and wrong format`() {
        assertTrue(PlazaCloudCache.validPcmWav(wav()))
        assertFalse(PlazaCloudCache.validPcmWav(wav().copyOf(46)))
        assertFalse(PlazaCloudCache.validPcmWav(wav().also { it[22] = 2 }))
        assertFalse(PlazaCloudCache.validPcmWav(wav().also { it[40] = 3 }))
    }

    @Test fun `tokens only sent to configured https or explicit debug loopback`() {
        assertTrue(PlazaCloudVoice.validBaseUrl("https://voice.example", false))
        assertFalse(PlazaCloudVoice.validBaseUrl("http://voice.example", true))
        assertFalse(PlazaCloudVoice.validBaseUrl("http://10.0.2.2:8091", false))
        assertTrue(PlazaCloudVoice.validBaseUrl("http://10.0.2.2:8091", true))
        assertFalse(PlazaCloudVoice.validBaseUrl("https://user:pass@voice.example", false))
        assertFalse(PlazaCloudVoice.validBaseUrl("https://voice.example?key=secret", false))
    }

    @Test fun `dev token only for debug builds against loopback http`() = runBlocking {
        val firebase: suspend () -> String = { "firebase" }
        assertEquals("dev", PlazaCloudVoice.tokenSupplier("http://10.0.2.2:8787", true, "dev", firebase)())
        assertEquals("firebase", PlazaCloudVoice.tokenSupplier("http://10.0.2.2:8787", false, "dev", firebase)())
        assertEquals("firebase", PlazaCloudVoice.tokenSupplier("https://voice.example", true, "dev", firebase)())
        assertEquals("firebase", PlazaCloudVoice.tokenSupplier("http://10.0.2.2:8787", true, "", firebase)())
    }
}
