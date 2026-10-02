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
  private val accounts =
    context.getSharedPreferences(ACCOUNTS_PREFERENCES_NAME, Context.MODE_PRIVATE)
  private val pendingOAuth =
    context.getSharedPreferences(PENDING_PREFERENCES_NAME, Context.MODE_PRIVATE)

  fun accounts(): List<StoredAccount> =
    accountEntries()
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
    val id = existingAccountId(normalizedUrl) ?: UUID.randomUUID().toString().lowercase()
    val secret =
      JSONObject()
        .put("service_url", normalizedUrl)
        .put("bearer_token", bearerToken)
        .put("auth_kind", PERMANENT_TOKEN)

    saveAccountSecret(id, secret)
    return StoredAccount(id, normalizedUrl, PERMANENT_TOKEN)
  }

  fun saveOAuthAccount(
    serviceUrl: String,
    hubUrl: String,
    clientId: String,
    scope: String,
    accessToken: String,
    refreshToken: String?,
    expiresInSeconds: Long?,
  ): StoredAccount {
    val normalizedUrl = serviceUrl.trim()
    val id = existingAccountId(normalizedUrl) ?: UUID.randomUUID().toString().lowercase()
    val secret =
      JSONObject()
        .put("service_url", normalizedUrl)
        .put("hub_url", hubUrl)
        .put("client_id", clientId)
        .put("scope", scope)
        .put("access_token", accessToken)
        .put("auth_kind", OAUTH_PKCE)
        .put(
          "expires_at_ms",
          expiresInSeconds?.let { System.currentTimeMillis() + (it * 1000) },
        )

    if (refreshToken != null) {
      secret.put("refresh_token", refreshToken)
    }

    saveAccountSecret(id, secret)
    return StoredAccount(id, normalizedUrl, OAUTH_PKCE)
  }

  fun accountSecret(accountId: String): JSONObject {
    val encoded =
      accounts.getString(accountId, null)
        ?: error("Stored YouTrack account was not found")
    return JSONObject(decrypt(encoded))
  }

  fun updateOAuthTokens(
    accountId: String,
    accessToken: String,
    refreshToken: String?,
    expiresInSeconds: Long?,
  ) {
    val secret = accountSecret(accountId)
    check(secret.getString("auth_kind") == OAUTH_PKCE) {
      "Stored YouTrack authentication method is not OAuth"
    }

    secret.put("access_token", accessToken)
    if (refreshToken != null) {
      secret.put("refresh_token", refreshToken)
    }
    secret.put(
      "expires_at_ms",
      expiresInSeconds?.let { System.currentTimeMillis() + (it * 1000) },
    )
    saveAccountSecret(accountId, secret)
  }

  fun delete(accountId: String) {
    accounts.edit().remove(accountId).apply()
  }

  fun savePendingOAuth(state: String, pending: JSONObject) {
    pendingOAuth.edit().putString(state, encrypt(pending.toString())).apply()
  }

  fun pendingOAuth(state: String): JSONObject {
    val encoded =
      pendingOAuth.getString(state, null)
        ?: error("OAuth authorization request is no longer available")
    return JSONObject(decrypt(encoded))
  }

  fun deletePendingOAuth(state: String) {
    pendingOAuth.edit().remove(state).apply()
  }

  private fun existingAccountId(serviceUrl: String): String? =
    accountEntries().firstOrNull { (_, secret) ->
      secret.optString("service_url") == serviceUrl
    }?.first

  private fun accountEntries(): List<Pair<String, JSONObject>> =
    accounts.all.mapNotNull { (id, value) ->
      val encoded = value as? String ?: return@mapNotNull null
      id to JSONObject(decrypt(encoded))
    }

  private fun saveAccountSecret(
    accountId: String,
    secret: JSONObject,
  ) {
    accounts.edit().putString(accountId, encrypt(secret.toString())).apply()
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
    const val PERMANENT_TOKEN = "permanent_token"
    const val OAUTH_PKCE = "oauth_pkce"

    private const val ACCOUNTS_PREFERENCES_NAME = "vela_secure_accounts"
    private const val PENDING_PREFERENCES_NAME = "vela_secure_oauth_pending"
    private const val KEY_ALIAS = "vela-youtrack-account-key-v1"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
  }
}
