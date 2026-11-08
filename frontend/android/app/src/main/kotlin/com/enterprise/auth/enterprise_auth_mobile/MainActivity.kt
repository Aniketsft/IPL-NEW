package com.enterprise.auth.enterprise_auth_mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val DEVICE_NAME_CHANNEL = "com.enterprise.auth/device_name"
    private val BLUETOOTH_CHANNEL = "com.enterprise.auth/bluetooth"
    private val QUNSUO_EVENT_CHANNEL = "com.qunsuo.scanner/stream"

    // Supported Actions (configured action + factory defaults)
    private val ACTION_BARCODE_DATA = "com.qunsuo.barcode.action"
    private val ACTION_SERVER_BROADCAST = "com.android.server.scannerservice.broadcast"
    private val ACTION_GENERIC_SCANRESULT = "android.intent.action.SCANRESULT"

    // Extra keys
    private val EXTRA_BARCODE_DATA = "barcode_data"
    private val EXTRA_SCANNER_DATA = "scannerdata"
    private val EXTRA_DATA = "data"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Device name MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_NAME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceName" -> {
                    val deviceName = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                    result.success(deviceName)
                }
                "getHardwareIdentifier" -> {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    result.success(androidId)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Bluetooth paired devices MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPairedDevices" -> {
                    try {
                        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                        val adapter = bluetoothManager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
                        if (adapter == null || !adapter.isEnabled) {
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }
                        val paired = adapter.bondedDevices ?: emptySet()
                        val list = paired.map { device ->
                            mapOf(
                                "name" to (device.name ?: "Unknown Device"),
                                "address" to device.address
                            )
                        }
                        result.success(list)
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", e.message, null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val generalIntent = Intent(Settings.ACTION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(generalIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("ERROR", e2.message, null)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Qunsuo PDA602 & QS-1003 Hardware Scanner EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, QUNSUO_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var broadcastReceiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    broadcastReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            val action = intent.action
                            if (action == ACTION_BARCODE_DATA || 
                                action == ACTION_SERVER_BROADCAST || 
                                action == ACTION_GENERIC_SCANRESULT) {
                                
                                // Try String extra first across known keys
                                var barcode: String? = intent.getStringExtra(EXTRA_BARCODE_DATA)
                                    ?: intent.getStringExtra(EXTRA_SCANNER_DATA)
                                    ?: intent.getStringExtra(EXTRA_DATA)

                                // Some Qunsuo firmware builds send raw byte arrays
                                if (barcode == null) {
                                    val bytes = intent.getByteArrayExtra(EXTRA_BARCODE_DATA)
                                        ?: intent.getByteArrayExtra(EXTRA_SCANNER_DATA)
                                        ?: intent.getByteArrayExtra(EXTRA_DATA)
                                    if (bytes != null && bytes.isNotEmpty()) {
                                        barcode = String(bytes, Charsets.UTF_8).trim()
                                    }
                                }

                                if (!barcode.isNullOrEmpty()) {
                                    events?.success(barcode.trim())
                                }
                            }
                        }
                    }

                    val filter = IntentFilter().apply {
                        addAction(ACTION_BARCODE_DATA)
                        addAction(ACTION_SERVER_BROADCAST)
                        addAction(ACTION_GENERIC_SCANRESULT)
                    }

                    // Android 13+ (API 33+) requires explicit receiver export flag
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(broadcastReceiver, filter, Context.RECEIVER_EXPORTED)
                    } else {
                        registerReceiver(broadcastReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    broadcastReceiver?.let {
                        try {
                            unregisterReceiver(it)
                        } catch (e: Exception) {
                            // Receiver might already be unregistered
                        }
                    }
                    broadcastReceiver = null
                }
            }
        )
    }
}
