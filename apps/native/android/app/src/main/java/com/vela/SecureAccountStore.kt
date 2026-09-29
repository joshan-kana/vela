package com.vela

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

data class StoredAccount(
  val id: String,
  val serviceUrl: String,
  val authKind: String,
)

class SecureAccountStore(
  context: Context,
) {
  private val preferences =
    context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

  fun accounts(): List<StoredAccount> =
    entries()
      .map { (id, secret) ->
        StoredAccount(
          id = id,
          serviceUrl = secret.getString("service_url"),
          authKind = secret.getString("auth_kind"),
        )
      }.sortedBy { it.serviceUrl.lowercase() }

  fun savePermanentToken(
    serviceUrl: String,
    bearerToken: String,
  ): StoredAccount {
    val normalizedUrl = serviceUrl.trim()
    val existing =
      entries().firstOrNull { (_, secret) ->
        secret.optString("service_url") == normalizedUrl
      }
    val id = existing?.first ?: UUID.randomUUID().toString().lowercase()
    val secret =
      JSONObject()
        .put("service_url", normalizedUrl)
        .put("bearer_token", bearerToken)
        .put("auth_kind", PERMANENT_TOKEN)

    preferences.edit().putString(id, encrypt(secret.toString())).apply()

    return StoredAccount(id, normalizedUrl, PERMANENT_TOKEN)
  }

  fun bearerToken(accountId: String): String {
    val encoded =
      preferences.getString(accountId, null)
        ?: error("Stored YouTrack account was not found")
    val secret = JSONObject(decrypt(encoded))
    check(secret.getString("auth_kind") == PERMANENT_TOKEN) {
      "Stored YouTrack authentication method is unsupported"
    }

    return secret.getString("bearer_token")
  }

  fun delete(accountId: String) {
    preferences.edit().remove(accountId).apply()
  }

  private fun entries(): List<Pair<String, JSONObject>> =
    preferences.all.mapNotNull { (id, value) ->
      val encoded = value as? String ?: return@mapNotNull null
      id to JSONObject(decrypt(encoded))
    }

  private fun encrypt(plaintext: String): String {
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, key())

    val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
    val ciphertext =
      Base64.encodeToString(
        cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8)),
        Base64.NO_WRAP,
      )

    return "$iv.$ciphertext"
  }

  private fun decrypt(encoded: String): String {
    val parts = encoded.split('.', limit = 2)
    check(parts.size == 2) { "Stored YouTrack credentials are invalid" }

    val cipher = Cipher.getInstance(TRANSFORMATION)
    val iv = Base64.decode(parts[0], Base64.NO_WRAP)
    val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, iv))

    return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
  }

  private fun key(): SecretKey {
    val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

    val generator =
      KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
    generator.init(
      KeyGenParameterSpec.Builder(
          KEY_ALIAS,
          KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .setRandomizedEncryptionRequired(true)
        .build(),
    )

    return generator.generateKey()
  }

  companion object {
    private const val PREFERENCES_NAME = "vela_secure_accounts"
    private const val KEY_ALIAS = "vela-youtrack-account-key-v1"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val PERMANENT_TOKEN = "permanent_token"
  }
}
