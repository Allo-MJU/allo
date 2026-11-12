package ai.allo.car.sync
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import kotlin.test.*
class FirebaseAuthenticatedTransportTest {
 private class Tokens:FirebaseTokenProvider {
  override val configured=true;var refreshes=0;var invalidations=0
  override suspend fun token(forceRefresh:Boolean):String {if(forceRefresh)refreshes++;return if(refreshes>0||invalidations>0)"fresh-token" else "old-token"}
  override fun invalidate(){invalidations++}
 }
 @Test fun `401 refreshes once and retries same request`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();s.enqueue(MockResponse().setResponseCode(401));s.enqueue(MockResponse().setBody("{}"))
   FirebaseRest(s.url("/").toString(),tokens=tokens).put("sessions/a/vehicle","{}")
   assertEquals("old-token",s.takeRequest().requestUrl!!.queryParameter("auth"));assertEquals("fresh-token",s.takeRequest().requestUrl!!.queryParameter("auth"));assertEquals(1,tokens.refreshes)
  }
 }
 @Test fun `second denial stops without leaking credentials`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();repeat(2){s.enqueue(MockResponse().setResponseCode(401))}
   val error=assertFails{FirebaseRest(s.url("/").toString(),tokens=tokens).get("sessions/a/game")}
   assertEquals(2,s.requestCount);assertFalse(error.message.orEmpty().contains("token"))
  }
 }
 @Test fun `SSE carries ID token`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();s.enqueue(MockResponse().setHeader("Content-Type","text/event-stream").setBody("event: put\ndata: {\"path\":\"/\",\"data\":{\"ok\":true}}\n\n"))
   withTimeout(3000){FirebaseRest(s.url("/").toString(),tokens=tokens).stream("sessions/a/game").first()}
   assertEquals("old-token",s.takeRequest().requestUrl!!.queryParameter("auth"))
  }
 }
 @Test fun `callable bearer and server generated metadata`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();s.enqueue(MockResponse().setBody("""{"result":{"sessionId":"s","pairCode":"123456","createdAt":100,"paired":false,"carAppVersion":"test"}}"""))
   val meta=FirebaseSessionApi(tokens,"allo-test","asia-northeast3",s.url("/create").toString()).create("s","test")
   assertEquals("123456",meta.pairCode);assertEquals(100L,meta.createdAt)
   val req=s.takeRequest();assertEquals("Bearer old-token",req.getHeader("Authorization"));assertTrue(req.body.readUtf8().contains("sessionId"))
  }
 }
 @Test fun `SSE auth revocation invalidates token before reconnect`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();s.enqueue(MockResponse().setHeader("Content-Type","text/event-stream").setBody("event: auth_revoked\ndata: \"expired\"\n\n"))
   assertFails { withTimeout(3000){FirebaseRest(s.url("/").toString(),tokens=tokens).stream("sessions/a/game").toList()} }
   assertEquals(1,tokens.invalidations)
  }
 }

 @Test fun `renewal calls dedicated endpoint with same session and request id`()=runBlocking<Unit>{
  MockWebServer().use { s ->
   s.start();val tokens=Tokens();s.enqueue(MockResponse().setBody("""{"result":{"sessionId":"s","pairCode":"654321","createdAt":100,"paired":false,"carAppVersion":"test"}}"""))
   val meta=FirebaseSessionApi(tokens,"allo-test","asia-northeast3",s.url("/createVehicleSession").toString()).renew("s","test","retry-id")
   assertEquals("654321",meta.pairCode)
   val req=s.takeRequest();assertEquals("/renewVehiclePairing",req.path)
   assertEquals("Bearer old-token",req.getHeader("Authorization"))
   val body=req.body.readUtf8();assertTrue(body.contains("retry-id"));assertFalse(body.contains("carAppVersion"))
  }
 }

}
