package ai.allo.car.voice

/** Exact transcript lookup: never use another character's recording for a missing line. */
internal object PlazaRecordings {
    data class Entry(val species: String, val text: String, val asset: String)
    val entries = listOf(
        Entry("road_sprout", "풀잎이 반짝인다! 정말 신기해.", "plaza_voice/road_sprout/plaza_1.wav"),
        Entry("road_sprout", "새로운 친구를 만나고 싶어!", "plaza_voice/road_sprout/plaza_2.wav"),
        Entry("puddle_pip", "첨벙첨벙, 물놀이가 제일 좋아!", "plaza_voice/puddle_pip/plaza_1.wav"),
        Entry("puddle_pip", "촉촉한 풀밭에서 놀고 싶어. 삐약!", "plaza_voice/puddle_pip/plaza_2.wav"),
        Entry("storm_lantern", "광장에 씩씩한 등불 등장! 번쩍!", "plaza_voice/storm_lantern/plaza_1.wav"),
        Entry("storm_lantern", "내 작은 불빛으로 환하게 비출게.", "plaza_voice/storm_lantern/plaza_2.wav"),
        Entry("sea_mist", "살며시 다가왔어. 몽글몽글.", "plaza_voice/sea_mist/plaza_1.wav"),
        Entry("sea_mist", "조용히 쉬는 시간이 참 좋아.", "plaza_voice/sea_mist/plaza_2.wav"),
        Entry("lamp_moth", "작은 불빛만 봐도 신나. 반짝!", "plaza_voice/lamp_moth/plaza_1.wav"),
        Entry("lamp_moth", "환한 빛을 따라 산책하고 싶어.", "plaza_voice/lamp_moth/plaza_2.wav"),
        Entry("highway_comet", "광장 한 바퀴, 신나게 달려! 슝!", "plaza_voice/highway_comet/plaza_1.wav"),
        Entry("highway_comet", "쌩쌩 달리고 잠깐 쉬는 거야.", "plaza_voice/highway_comet/plaza_2.wav"),
        Entry("breeze_wyrm", "바람 따라 산책할래. 산들산들.", "plaza_voice/breeze_wyrm/plaza_1.wav"),
        Entry("breeze_wyrm", "나뭇잎 춤을 보고 싶어. 살랑.", "plaza_voice/breeze_wyrm/plaza_2.wav"),
        Entry("cloud_strider", "서두르지 않아도 좋아. 사뿐.", "plaza_voice/cloud_strider/plaza_1.wav"),
        Entry("cloud_strider", "느긋한 산책이 내 취향이야.", "plaza_voice/cloud_strider/plaza_2.wav"),
        Entry("dewcap", "작은 이슬을 구경하고 싶어.", "plaza_voice/dewcap/plaza_1.wav"),
        Entry("dewcap", "쉬는 동안 마음도 촉촉해져.", "plaza_voice/dewcap/plaza_2.wav"),
        Entry("dune_roller", "차근차근 걷는 게 좋아.", "plaza_voice/dune_roller/plaza_1.wav"),
        Entry("dune_roller", "둥근 돌을 떠올렸어. 또르르.", "plaza_voice/dune_roller/plaza_2.wav"),
        Entry("ember_crab", "살짝 인사하러 왔어. 반가워.", "plaza_voice/ember_crab/plaza_1.wav"),
        Entry("ember_crab", "포근하게 쉬고 싶은 날이야.", "plaza_voice/ember_crab/plaza_2.wav"),
        Entry("pebble_orbit", "동그란 모양이 참 재미있어.", "plaza_voice/pebble_orbit/plaza_1.wav"),
        Entry("pebble_orbit", "천천히 둘러보고 싶어. 빙글.", "plaza_voice/pebble_orbit/plaza_2.wav")
    )
    fun request(species: String, text: String) = "$species\n$text"
    fun find(request: String): Entry? = entries.firstOrNull { request(it.species, it.text) == request }
}
