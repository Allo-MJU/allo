package ai.allo.car.sync

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.IOException
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only ciphertext is persisted. Account material is never stored in logs or plain preferences. */
class KeystoreRefreshTokenStore(context: Context, project: String, apiKey: String, localEmulator: Boolean = false) : RefreshTokenStore {
    private val namespace = MessageDigest.getInstance("SHA-256").digest((if (localEmulator) "local-emulator:$project:$apiKey" else "$project:$apiKey").toByteArray())
        .joinToString("") { "%02x".format(it) }
    private val alias = "allo.firebase.$namespace"
    private val prefs = context.getSharedPreferences(if (localEmulator) "firebase_identity_local_emulator" else "firebase_identity", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun read(): String? {
        val encrypted = prefs.getString(namespace, null) ?: return null
        return try {
            val pieces = encrypted.split(':')
            require(pieces.size == 2)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(pieces[0], Base64.NO_WRAP)))
            String(cipher.doFinal(Base64.decode(pieces[1], Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) { throw IOException("Stored Firebase identity cannot be opened") }
    }
    override fun write(value: String) {
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
            val encrypted = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
            if (!prefs.edit().putString(namespace, encrypted).commit()) throw IOException("save failed")
        } catch (_: Exception) { throw IOException("Firebase identity could not be saved") }
    }
}
