package com.vela

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import java.util.concurrent.Executors

class VelaRustModule(
  reactContext: ReactApplicationContext,
) : ReactContextBaseJavaModule(reactContext) {
  private val executor = Executors.newSingleThreadExecutor()

  init {
    System.loadLibrary("vela_ffi")
    initializeRust(reactContext)
  }

  override fun getName(): String = NAME

  private external fun initializeRust(context: ReactApplicationContext)

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

  private external fun loadMyWorkJsonNative(
    serviceUrl: String,
    bearerToken: String,
    top: Int,
  ): String

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
  }
}
