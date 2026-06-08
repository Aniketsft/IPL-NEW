package com.enterprise.auth.enterprise_auth_mobile

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.enterprise.auth/device_name"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getDeviceName") {
                val deviceName = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                result.success(deviceName)
            } else {
                result.notImplemented()
            }
        }
    }
}
