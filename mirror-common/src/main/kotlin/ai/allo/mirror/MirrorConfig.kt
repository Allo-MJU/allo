package ai.allo.mirror

import java.net.URI

/** Ephemeral connection credentials. Deliberately not a data class (no secret-bearing toString). */
class MirrorConfig(val url: String, val token: String, val certificateSha256: String) {
    init {
        val uri = try { URI(url) } catch (_: Exception) { throw IllegalArgumentException("연결 주소를 확인해 주세요") }
        require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null &&
            (uri.rawPath.isNullOrEmpty() || uri.rawPath == "/") &&
            (uri.port == -1 || uri.port in 1..65535)) { "HTTPS 서버 주소를 확인해 주세요" }
        require(Regex("[A-Za-z0-9_-]{32,128}").matches(token)) { "연결 코드를 확인해 주세요" }
        require(Regex("[a-fA-F0-9]{64}").matches(certificateSha256)) { "서버 인증 정보를 확인해 주세요" }
    }

    override fun toString() = "MirrorConfig(redacted)"

    companion object {
        /** The setup tool emits a flat ASCII JSON object. Reject escapes, duplicate/extra keys. */
        fun parse(json: String): MirrorConfig {
            require(json.length <= 4096) { "연결 정보가 너무 길어요" }
            val text = json.trim()
            require(text.startsWith("{") && text.endsWith("}")) { "연결 정보를 확인해 주세요" }
            val content = text.substring(1, text.length - 1)
            val entries = Regex("\"([A-Za-z0-9]+)\"\\s*:\\s*\"([^\"\\\\\\p{Cntrl}]*)\"").findAll(content).toList()
            require(entries.size == 3) { "연결 정보를 확인해 주세요" }
            var end = 0
            val values = mutableMapOf<String, String>()
            entries.forEachIndexed { index, match ->
                require(content.substring(end, match.range.first).trim() == if (index == 0) "" else ",") { "연결 정보를 확인해 주세요" }
                require(values.put(match.groupValues[1], match.groupValues[2]) == null) { "연결 정보가 중복됐어요" }
                end = match.range.last + 1
            }
            require(content.substring(end).isBlank() && values.keys == setOf("url", "token", "certificateSha256")) { "연결 정보를 확인해 주세요" }
            return MirrorConfig(values.getValue("url"), values.getValue("token"), values.getValue("certificateSha256"))
        }
    }
}
