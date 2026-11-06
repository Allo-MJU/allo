package ai.allo.car.vehicle

import kotlin.test.*

class RegionTaggerTest {
    @Test fun `known places`() {
        assertEquals("city", RegionTagger.classify(GeoPoint(37.40, 127.11)))      // 판교
        assertEquals("coast", RegionTagger.classify(GeoPoint(35.159, 129.160)))   // 해운대: 도시이지만 바다 우선
        assertEquals("mountain", RegionTagger.classify(GeoPoint(38.17, 128.49)))  // 설악산
        assertEquals("coast", RegionTagger.classify(GeoPoint(33.39, 126.24)))     // 협재
        assertNull(RegionTagger.classify(GeoPoint(36.0, 127.9)))                  // 내륙 시골
    }

    @Test fun `override wins and missing position gives null`() {
        val t = RegionTagger()
        assertNull(t.tag(null, null))
        t.override = "coast"
        assertEquals("coast", t.tag(37.40, 127.11))
    }

    @Test fun `geopoint does not print coordinates`() {
        assertFalse("37" in GeoPoint(37.40, 127.11).toString())
    }
}
