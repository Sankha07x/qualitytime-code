package com.example.QualityTime

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION = "com.qualitytime.app.PIP_ACTION"
    }

    private var channel: MethodChannel? = null
    private var auto = false
    private var receiverOn = false
    private var callUi = false
    private var screenOffOn = false

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!callUi) allowOnLock(false)
        }
    }

    private fun allowOnLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        }
    }

    private fun fromCallNotification(i: Intent?): Boolean =
        i?.action == "SELECT_NOTIFICATION"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        allowOnLock(fromCallNotification(intent))
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        screenOffOn = true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (fromCallNotification(intent)) allowOnLock(true)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val a = intent?.getStringExtra("a") ?: return
            channel?.invokeMethod("pipAction", a)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qt/pip")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAuto" -> {
                    auto = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "callUi" -> {
                    callUi = call.arguments as? Boolean ?: false
                    allowOnLock(callUi)
                    result.success(null)
                }
                "shareOn" -> {
                    val i = Intent(this, ScreenShareService::class.java)
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i)
                    else startService(i)
                    result.success(null)
                }
                "shareOff" -> {
                    stopService(Intent(this, ScreenShareService::class.java))
                    result.success(null)
                }
"fxVideo" -> {
                    try {
                        val a = call.arguments as? Map<*, *>
                        VideoFx.configure(
                            trackId = a?.get("trackId")?.toString() ?: "",
                            mode = (a?.get("mode") as? Int) ?: 0,
                            denoise = (a?.get("denoise") as? Boolean) ?: false,
                            fast = (a?.get("fast") as? Boolean) ?: false,
                            bgPath = a?.get("bgPath")?.toString() ?: "",
                            context = applicationContext,
                            onAutoOff = { why ->
                                runOnUiThread { channel?.invokeMethod("fxAutoOff", why) }
                            }
                        )
                    } catch (e: Throwable) {
                        Log.w("QT_FX", "fxVideo failed: $e")
                    }
                    result.success(null)
                }
                "fxAudio" -> {
                    try {
                        RnnoiseFx.setEnabled((call.arguments as? Boolean) ?: false)
                    } catch (e: Throwable) {
                        Log.w("QT_FX", "fxAudio failed: $e")
                    }
                    result.success(null)
                }
                "leave" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        fun act(code: Int, name: String, icon: Int, title: String): RemoteAction {
            val pi = PendingIntent.getBroadcast(
                this, code,
                Intent(ACTION).setPackage(packageName).putExtra("a", name),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            return RemoteAction(Icon.createWithResource(this, icon), title, title, pi)
        }
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(9, 16))
            .setActions(
                listOf(
                    act(1, "mute", R.drawable.ic_pip_mic, "Mute"),
                    act(2, "video", R.drawable.ic_pip_video, "Camera"),
                    act(3, "end", R.drawable.ic_pip_end, "End call")
                )
            )
            .build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!auto) return
        try {
            pipParams()?.let { enterPictureInPictureMode(it) }
        } catch (_: Exception) {
        }
    }

    private fun listen() {
        if (receiverOn) return
        val f = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, f, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, f)
        }
        receiverOn = true
    }

    private fun unlisten() {
        if (!receiverOn) return
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        receiverOn = false
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) listen() else unlisten()
        channel?.invokeMethod("pip", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        unlisten()
        if (screenOffOn) {
            try {
                unregisterReceiver(screenOff)
            } catch (_: Exception) {
            }
            screenOffOn = false
        }
        super.onDestroy()
    }
}