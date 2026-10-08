package com.vela

import android.net.Uri
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import org.json.JSONObject
import java.util.concurrent.Executors

class VelaRustModule(
  reactContext: ReactApplicationContext,
) : ReactContextBaseJavaModule(reactContext) {
  private val executor = Executors.newSingleThreadExecutor()
  private val accountStore = SecureAccountStore(reactContext)

  init {
    System.loadLibrary("vela_ffi")
    initializeRust(reactContext)
  }

  override fun getName(): String = NAME

  private external fun initializeRust(context: ReactApplicationContext)

  private external fun executeIssueActionJsonNative(
    serviceUrl: String,
    bearerToken: String,
    actionJson: String,
  ): String

  private external fun beginOAuthJsonNative(
    serviceUrl: String,
    hubUrl: String,
    clientId: String,
    redirectUri: String,
    scope: String,
  ): String

  private external fun exchangeOAuthCodeJsonNative(
    hubUrl: String,
    clientId: String,
    redirectUri: String,
    codeVerifier: String,
    code: String,
  ): String

  private external fun refreshOAuthTokenJsonNative(
    hubUrl: String,
    clientId: String,
    scope: String,
    refreshToken: String,
  ): String

  private external fun discoverJsonNative(
    serviceUrl: String,
    bearerToken: String,
  ): String

  private external fun loadProjectSchemaJsonNative(
    serviceUrl: String,
    bearerToken: String,
    projectId: String,
  ): String

  private external fun usersJsonNative(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
  ): String

  private external fun agileBoardsJsonNative(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
  ): String

  private external fun savedQueriesJsonNative(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
  ): String

  private external fun issueDetailsJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
  ): String

  private external fun issueLinksJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
  ): String

  private external fun setIssueSummaryJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    summary: String,
  ): String

  private external fun setIssueDescriptionJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    description: String?,
  ): String

  private external fun setCustomFieldValueJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    fieldId: String,
    fieldType: String,
    valueJson: String,
  ): String

  private external fun applyCustomFieldEventJsonNative(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    fieldId: String,
    fieldType: String,
    eventId: String,
  ): String

  private external fun loadMyWorkJsonNative(
    serviceUrl: String,
    bearerToken: String,
    top: Int,
  ): String

  @ReactMethod
  fun listAccounts(promise: Promise) {
    executor.execute {
      try {
        val accounts = Arguments.createArray()
        accountStore.accounts().forEach { account ->
          accounts.pushMap(accountMap(account))
        }
        promise.resolve(accounts)
      } catch (error: Throwable) {
        promise.reject("vela_accounts", error)
      }
    }
  }

  @ReactMethod
  fun savePermanentTokenAccount(
    serviceUrl: String,
    bearerToken: String,
    promise: Promise,
  ) {
    executor.execute {
      try {
        val account = accountStore.savePermanentToken(serviceUrl, bearerToken)
        promise.resolve(accountMap(account))
      } catch (error: Throwable) {
        promise.reject("vela_accounts", error)
      }
    }
  }

  @ReactMethod
  fun deleteAccount(
    accountId: String,
    promise: Promise,
  ) {
    executor.execute {
      try {
        val account = accountStore.accounts().firstOrNull { it.id == accountId }
        if (account != null) {
          val namespace = "${account.serviceUrl}::$accountId"
          val response = JSONObject(clearCachedAccountJsonNative(cachePath(), namespace))
          if (response.getString("status") != "ok") {
            throw IllegalStateException("Unable to clear cached issue data")
          }
        }
        accountStore.delete(accountId)
        promise.resolve(null)
      } catch (error: Throwable) {
        promise.reject("vela_accounts", error)
      }
    }
  }

  @ReactMethod
  fun loadAccountToken(
    accountId: String,
    promise: Promise,
  ) {
    executor.execute {
      try {
        promise.resolve(resolveAccountToken(accountId))
      } catch (error: Throwable) {
        promise.reject("vela_accounts", error)
      }
    }
  }

  @ReactMethod
  fun beginOAuth(
    serviceUrl: String,
    clientId: String,
    hubUrl: String?,
    scope: String?,
    promise: Promise,
  ) {
    executor.execute {
      try {
        val authorization =
          bridgeData(
            beginOAuthJsonNative(
              serviceUrl.trim(),
              hubUrl?.trim().orEmpty(),
              clientId.trim(),
              OAUTH_REDIRECT_URI,
              scope?.trim().takeUnless { it.isNullOrEmpty() } ?: DEFAULT_OAUTH_SCOPE,
            ),
          )
        val state = authorization.getString("state")
        val pending =
          JSONObject(authorization.toString())
            .put("service_url", serviceUrl.trim())

        accountStore.savePendingOAuth(state, pending)

        promise.resolve(
          Arguments.createMap().apply {
            putString("authorization_url", authorization.getString("authorization_url"))
            putString("state", state)
          },
        )
      } catch (error: Throwable) {
        promise.reject("vela_oauth", error)
      }
    }
  }

  @ReactMethod
  fun completeOAuth(
    callbackUrl: String,
    promise: Promise,
  ) {
    executor.execute {
      try {
        val callback = Uri.parse(callbackUrl)
        check(callback.scheme == OAUTH_SCHEME && callback.path == OAUTH_CALLBACK_PATH) {
          "Unexpected OAuth callback URL"
        }

        val state = callback.getQueryParameter("state")
        callback.getQueryParameter("error")?.let { oauthError ->
          state?.let(accountStore::deletePendingOAuth)
          val description = callback.getQueryParameter("error_description")
          error(description?.let { "$oauthError: $it" } ?: oauthError)
        }

        val callbackState = state ?: error("OAuth callback is missing state")
        val code = callback.getQueryParameter("code") ?: error("OAuth callback is missing code")
        val pending = accountStore.pendingOAuth(callbackState)

        val tokens =
          bridgeData(
            exchangeOAuthCodeJsonNative(
              pending.getString("hub_url"),
              pending.getString("client_id"),
              pending.getString("redirect_uri"),
              pending.getString("code_verifier"),
              code,
            ),
          )

        val account =
          accountStore.saveOAuthAccount(
            serviceUrl = pending.getString("service_url"),
            hubUrl = pending.getString("hub_url"),
            clientId = pending.getString("client_id"),
            scope = pending.getString("scope"),
            accessToken = tokens.getString("access_token"),
            refreshToken = tokens.optionalString("refresh_token"),
            expiresInSeconds = tokens.optionalLong("expires_in"),
          )

        accountStore.deletePendingOAuth(callbackState)
        promise.resolve(accountMap(account))
      } catch (error: Throwable) {
        promise.reject("vela_oauth", error)
      }
    }
  }

  @ReactMethod
  fun executeIssueActionJson(
    serviceUrl: String,
    bearerToken: String,
    actionJson: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      executeIssueActionJsonNative(serviceUrl, bearerToken, actionJson)
    }
  }

  @ReactMethod
  fun discoverJson(
    serviceUrl: String,
    bearerToken: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      discoverJsonNative(serviceUrl, bearerToken)
    }
  }

  @ReactMethod
  fun loadProjectSchemaJson(
    serviceUrl: String,
    bearerToken: String,
    projectId: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      loadProjectSchemaJsonNative(serviceUrl, bearerToken, projectId)
    }
  }

  @ReactMethod
  fun loadUsersJson(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      usersJsonNative(serviceUrl, bearerToken, skip, top)
    }
  }

  @ReactMethod
  fun loadAgileBoardsJson(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      agileBoardsJsonNative(serviceUrl, bearerToken, skip, top)
    }
  }

  @ReactMethod
  fun loadSavedQueriesJson(
    serviceUrl: String,
    bearerToken: String,
    skip: Int,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      savedQueriesJsonNative(serviceUrl, bearerToken, skip, top)
    }
  }

  @ReactMethod
  fun loadIssueDetailsJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      issueDetailsJsonNative(serviceUrl, bearerToken, issueId)
    }
  }

  @ReactMethod
  fun loadIssueLinksJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      issueLinksJsonNative(serviceUrl, bearerToken, issueId)
    }
  }

  @ReactMethod
  fun setIssueSummaryJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    summary: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      setIssueSummaryJsonNative(serviceUrl, bearerToken, issueId, summary)
    }
  }

  @ReactMethod
  fun setIssueDescriptionJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    description: String?,
    promise: Promise,
  ) {
    resolveJson(promise) {
      setIssueDescriptionJsonNative(serviceUrl, bearerToken, issueId, description)
    }
  }

  @ReactMethod
  fun setCustomFieldValueJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    fieldId: String,
    fieldType: String,
    valueJson: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      setCustomFieldValueJsonNative(
        serviceUrl,
        bearerToken,
        issueId,
        fieldId,
        fieldType,
        valueJson,
      )
    }
  }

  @ReactMethod
  fun applyCustomFieldEventJson(
    serviceUrl: String,
    bearerToken: String,
    issueId: String,
    fieldId: String,
    fieldType: String,
    eventId: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      applyCustomFieldEventJsonNative(
        serviceUrl,
        bearerToken,
        issueId,
        fieldId,
        fieldType,
        eventId,
      )
    }
  }

  private external fun storeMyWorkJsonNative(
    cachePath: String,
    namespace: String,
    top: Int,
    workJson: String,
  ): String

  @ReactMethod
  fun storeMyWorkJson(
    serviceUrl: String,
    accountId: String,
    top: Int,
    workJson: String,
    promise: Promise,
  ) {
    resolveJson(promise) {
      storeMyWorkJsonNative(cachePath(), "$serviceUrl::$accountId", top, workJson)
    }
  }

  private external fun clearCachedAccountJsonNative(
    cachePath: String,
    namespace: String,
  ): String

  private external fun cachedMyWorkJsonNative(
    cachePath: String,
    namespace: String,
    top: Int,
  ): String

  private external fun refreshMyWorkJsonNative(
    serviceUrl: String,
    bearerToken: String,
    cachePath: String,
    namespace: String,
    top: Int,
  ): String

  private fun cachePath(): String = java.io.File(reactApplicationContext.filesDir, "vela-cache.sqlite3").absolutePath

  @ReactMethod
  fun cachedMyWorkJson(
    serviceUrl: String,
    accountId: String,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      cachedMyWorkJsonNative(cachePath(), "$serviceUrl::$accountId", top)
    }
  }

  @ReactMethod
  fun refreshMyWorkJson(
    serviceUrl: String,
    bearerToken: String,
    accountId: String,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      refreshMyWorkJsonNative(serviceUrl, bearerToken, cachePath(), "$serviceUrl::$accountId", top)
    }
  }

  @ReactMethod
  fun loadMyWorkJson(
    serviceUrl: String,
    bearerToken: String,
    top: Int,
    promise: Promise,
  ) {
    resolveJson(promise) {
      loadMyWorkJsonNative(serviceUrl, bearerToken, top)
    }
  }

  private fun resolveAccountToken(accountId: String): String {
    val secret = accountStore.accountSecret(accountId)

    return when (secret.getString("auth_kind")) {
      SecureAccountStore.PERMANENT_TOKEN -> {
        secret.getString("bearer_token")
      }

      SecureAccountStore.OAUTH_PKCE -> {
        val accessToken = secret.getString("access_token")
        val expiresAt =
          if (secret.has("expires_at_ms") && !secret.isNull("expires_at_ms")) {
            secret.getLong("expires_at_ms")
          } else {
            null
          }

        if (expiresAt == null || expiresAt > System.currentTimeMillis() + TOKEN_REFRESH_SKEW_MS) {
          return accessToken
        }

        val refreshToken =
          secret.optionalString("refresh_token")
            ?: error("OAuth access token expired and no refresh token is available")
        val tokens =
          bridgeData(
            refreshOAuthTokenJsonNative(
              secret.getString("hub_url"),
              secret.getString("client_id"),
              secret.getString("scope"),
              refreshToken,
            ),
          )
        val nextAccessToken = tokens.getString("access_token")

        accountStore.updateOAuthTokens(
          accountId = accountId,
          accessToken = nextAccessToken,
          refreshToken = tokens.optionalString("refresh_token"),
          expiresInSeconds = tokens.optionalLong("expires_in"),
        )

        nextAccessToken
      }

      else -> {
        error("Stored YouTrack authentication method is unsupported")
      }
    }
  }

  private fun bridgeData(json: String): JSONObject {
    val response = JSONObject(json)
    check(response.optString("status") == "ok") {
      response.optString("message").ifEmpty { "Vela Rust bridge request failed" }
    }
    return response.getJSONObject("data")
  }

  private fun accountMap(account: StoredAccount) =
    Arguments.createMap().apply {
      putString("id", account.id)
      putString("service_url", account.serviceUrl)
      putString("auth_kind", account.authKind)
    }

  private fun JSONObject.optionalString(name: String): String? =
    if (has(name) && !isNull(name)) {
      getString(name)
    } else {
      null
    }

  private fun JSONObject.optionalLong(name: String): Long? =
    if (has(name) && !isNull(name)) {
      getLong(name)
    } else {
      null
    }

  private fun resolveJson(
    promise: Promise,
    operation: () -> String,
  ) {
    executor.execute {
      try {
        promise.resolve(operation())
      } catch (error: Throwable) {
        promise.reject("vela_rust", error)
      }
    }
  }

  override fun invalidate() {
    executor.shutdownNow()
    super.invalidate()
  }

  companion object {
    const val NAME = "VelaRust"

    private const val OAUTH_SCHEME = "io.github.joshankana.vela"
    private const val OAUTH_CALLBACK_PATH = "/oauth/callback"
    private const val OAUTH_REDIRECT_URI = "$OAUTH_SCHEME:$OAUTH_CALLBACK_PATH"
    private const val DEFAULT_OAUTH_SCOPE = "YouTrack"
    private const val TOKEN_REFRESH_SKEW_MS = 60_000L
  }
}
