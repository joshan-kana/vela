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
  }

  override fun getName(): String = NAME

  private external fun loadMyWorkJsonNative(
    serviceUrl: String,
    bearerToken: String,
    top: Int,
  ): String

  @ReactMethod
  fun loadMyWorkJson(
    serviceUrl: String,
    bearerToken: String,
    top: Int,
    promise: Promise,
  ) {
    executor.execute {
      try {
        promise.resolve(loadMyWorkJsonNative(serviceUrl, bearerToken, top))
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
