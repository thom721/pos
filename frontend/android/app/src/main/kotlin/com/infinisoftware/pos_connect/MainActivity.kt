package com.infinisoftware.pos_connect

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var btSocket: BluetoothSocket? = null
    private var btOut: OutputStream? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pos_connect/bluetooth")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val mac = call.argument<String>("mac") ?: return@setMethodCallHandler result.error("NO_MAC", "MAC requis", null)
                        Thread {
                            try {
                                btSocket?.close()
                            } catch (_: Exception) {}
                            btSocket = null
                            btOut = null
                            try {
                                val adapter = BluetoothAdapter.getDefaultAdapter()
                                val device = adapter.getRemoteDevice(mac)
                                // Connexion non-sécurisée — compatible avec la majorité des imprimantes génériques
                                val socket = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                                socket.connect()
                                btSocket = socket
                                btOut = socket.outputStream
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }.start()
                    }

                    "sendBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: return@setMethodCallHandler result.error("NO_DATA", "Bytes requis", null)
                        Thread {
                            try {
                                val chunkSize = 4096
                                var offset = 0
                                while (offset < bytes.size) {
                                    val end = minOf(offset + chunkSize, bytes.size)
                                    btOut?.write(bytes, offset, end - offset)
                                    btOut?.flush()
                                    offset = end
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }.start()
                    }

                    "disconnect" -> {
                        try {
                            btOut?.close()
                            btSocket?.close()
                        } catch (_: Exception) {}
                        btSocket = null
                        btOut = null
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
