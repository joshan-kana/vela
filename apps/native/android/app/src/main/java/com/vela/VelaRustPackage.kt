package com.vela

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class VelaRustPackage : BaseReactPackage() {
  override fun getModule(
    name: String,
    reactContext: ReactApplicationContext,
  ): NativeModule? =
    if (name == VelaRustModule.NAME) {
      VelaRustModule(reactContext)
    } else {
      null
    }

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider =
    ReactModuleInfoProvider {
      mapOf(
        VelaRustModule.NAME to
          ReactModuleInfo(
            VelaRustModule.NAME,
            VelaRustModule::class.java.name,
            false,
            false,
            false,
            false,
          ),
      )
    }
}
