package ai.allo.car.sync
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import kotlin.test.*
class FirebaseIdentityTest {
 private class Store(var value:String?=null):RefreshTokenStore { override fun read()=value; override fun write(value:String){this.value=value} }
 @Test fun `signup caches and expired token refresh keeps identity`()=runBlocking<Unit>{
  MockWebServer().use { server ->
   server.start();var now=1000L;val store=Store()
   val auth=FirebaseIdentity("key",store,identityUrl=server.url("/signup").toString(),refreshUrl=server.url("/refresh").toString(),clockMs={now})
   server.enqueue(MockResponse().setBody("""{"idToken":"first","refreshToken":"persistent","expiresIn":"3600"}"""))
   assertEquals("first",auth.token());assertEquals("first",auth.token());assertEquals(1,server.requestCount);assertEquals("persistent",store.value)
   now+=3_600_000
   server.enqueue(MockResponse().setBody("""{"id_token":"second","refresh_token":"rotated","expires_in":"3600"}"""))
   assertEquals("second",auth.token());assertEquals("rotated",store.value)
   assertTrue(server.takeRequest().path!!.startsWith("/signup"))
   val req=server.takeRequest();assertTrue(req.path!!.startsWith("/refresh"));assertTrue(req.body.readUtf8().contains("refresh_token=persistent"))
  }
 }
 @Test fun `revoked persisted identity never silently signs up new owner`()=runBlocking<Unit>{
  MockWebServer().use { server ->
   server.start();val store=Store("keep-this");val auth=FirebaseIdentity("key",store,refreshUrl=server.url("/refresh").toString())
   server.enqueue(MockResponse().setResponseCode(400).setBody("secret response"))
   val error=assertFails{auth.token()};assertFalse(error.message.orEmpty().contains("secret"));assertEquals("keep-this",store.value)
   assertEquals(1,server.requestCount);assertTrue(server.takeRequest().path!!.startsWith("/refresh"))
  }
 }
 @Test fun `persistence failure prevents new identity use`()=runBlocking<Unit>{
  MockWebServer().use { server ->
   server.start();val store=object:RefreshTokenStore{override fun read():String?=null;override fun write(value:String){error("disk")}}
   val auth=FirebaseIdentity("key",store,identityUrl=server.url("/signup").toString())
   server.enqueue(MockResponse().setBody("""{"idToken":"first","refreshToken":"persistent","expiresIn":"3600"}"""));assertFails{auth.token()}
  }
 }
}
