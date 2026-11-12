package ai.allo.car.sync

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import kotlin.test.*

class FirebaseEndpointsTest {
    private fun local(debug: Boolean = true, enabled: Boolean = true, project: String = "demo-allo-auth",
        database: String = "https://demo-allo-auth-default-rtdb.firebaseio.com") =
        FirebaseEndpoints.resolve(debug, enabled, project, "asia-northeast3", database)

    @Test fun `local routing is fixed and release ignores local flag`() {
        val endpoints = local()
        assertTrue(endpoints.local)
        assertEquals("http://10.0.2.2:9000", endpoints.databaseUrl)
        assertEquals("demo-allo-auth-default-rtdb", endpoints.databaseNamespace)
        assertEquals("http://10.0.2.2:9099/identitytoolkit.googleapis.com/v1/accounts:signUp", endpoints.identityUrl)
        assertEquals("http://10.0.2.2:9099/securetoken.googleapis.com/v1/token", endpoints.refreshUrl)
        assertEquals("http://10.0.2.2:5001/demo-allo-auth/asia-northeast3/createVehicleSession", endpoints.sessionUrl)
        for (value in listOf(local(debug = false), local(enabled = false))) {
            assertFalse(value.local)
            assertNull(value.databaseNamespace)
            assertEquals("https://demo-allo-auth-default-rtdb.firebaseio.com", value.databaseUrl)
            assertEquals("https://identitytoolkit.googleapis.com/v1/accounts:signUp", value.identityUrl)
        }
    }

    @Test fun `local flag rejects live project or arbitrary database`() {
        assertFailsWith<IllegalArgumentException> { local(project = "live-project") }
        assertFailsWith<IllegalArgumentException> { local(database = "http://example.com") }
        assertFailsWith<IllegalArgumentException> {
            FirebaseEndpoints.resolve(true, true, "demo-allo-auth", "us-central1", "https://demo-allo-auth-default-rtdb.firebaseio.com")
        }
    }

    @Test fun `production endpoints remain unchanged`() {
        val value = FirebaseEndpoints.resolve(false, false, "live-project", "asia-northeast3", "https://live.example")
        assertEquals("https://live.example", value.databaseUrl)
        assertEquals("https://asia-northeast3-live-project.cloudfunctions.net/createVehicleSession", value.sessionUrl)
        assertEquals("https://securetoken.googleapis.com/v1/token", value.refreshUrl)
    }

    @Test fun `database namespace is appended without altering auth or path`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("{}"))
            val tokens = object : FirebaseTokenProvider {
                override val configured = true
                override suspend fun token(forceRefresh: Boolean) = "local-token"
                override fun invalidate() {}
            }
            FirebaseRest(server.url("/").toString(), tokens = tokens, databaseNamespace = "demo-allo-auth-default-rtdb")
                .get("sessions/one/game")
            val request = server.takeRequest().requestUrl!!
            assertEquals("/sessions/one/game.json", request.encodedPath)
            assertEquals("local-token", request.queryParameter("auth"))
            assertEquals("demo-allo-auth-default-rtdb", request.queryParameter("ns"))
            server.enqueue(MockResponse().setBody("{}"))
            FirebaseRest(server.url("/").toString()).get("sessions/one/game")
            assertNull(server.takeRequest().requestUrl!!.queryParameter("ns"))
        }
    }

    @Test fun `database namespace cannot contain query syntax or empty values`() {
        listOf("", "demo&auth=other", "demo/path", "a b").forEach {
            assertFailsWith<IllegalArgumentException> { FirebaseRest("http://localhost", databaseNamespace = it) }
        }
    }
}
