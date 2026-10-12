package com.example.QualityTime

import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer

/** Bridge to the native RNNoise library. If the library is missing, loaded = false. */
object RnnoiseNative {
    var loaded = false

    init {
        try {
            System.loadLibrary("qt_rnnoise")
            loaded = true
        } catch (t: Throwable) {
            Log.w("QT_FX", "rnnoise library not available: $t")
        }
    }

    external fun create(): Long
    external fun process(handle: Long, frame: FloatArray): Float
    external fun destroy(handle: Long)
}

/** AI noise removal on my microphone. Only touches audio it fully understands. */
object RnnoiseFx : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private const val TAG = "QT_FX"
    private const val N = 480
    private const val WET = 0.85f

    @Volatile private var enabled = false
    private var attached = false
    private var handle = 0L
    private var warned = false
    private var calls = 0
    private var peakSeen = 0f
    private var gain = 1f
    private val tmp = FloatArray(N)

    fun setEnabled(on: Boolean) {
        enabled = on
        if (on && !attached) attach()
    }

    private fun attach() {
        try {
            val ctl = FlutterWebRTCPlugin.sharedSingleton?.getAudioProcessingController()
            if (ctl != null) {
                ctl.capturePostProcessing.addProcessor(this)
                attached = true
            }
            Log.d(TAG, "audio processor attached=$attached")
        } catch (t: Throwable) {
            Log.w(TAG, "audio attach failed: $t")
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        Log.d(TAG, "audio initialize rate=$sampleRateHz channels=$numChannels")
    }

    override fun reset(newRate: Int) {
        gain = 1f
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (!enabled || !RnnoiseNative.loaded) return
        try {
            if (numBands != 1 || numFrames != N) {
                if (!warned) {
                    warned = true
                    Log.w(TAG, "audio format not supported: bands=$numBands frames=$numFrames cap=${buffer.capacity()}")
                }
                return
            }
            val b = buffer.duplicate()
            b.order(buffer.order())
            b.clear()
            val cap = b.capacity()
            val isFloat = cap == N * 4
            val isShort = cap == N * 2
            if (!isFloat && !isShort) {
                if (!warned) {
                    warned = true
                    Log.w(TAG, "audio buffer size not supported: cap=$cap")
                }
                return
            }
            if (handle == 0L) {
                handle = RnnoiseNative.create()
                if (handle == 0L) {
                    enabled = false
                    return
                }
            }
            val fb = if (isFloat) b.asFloatBuffer() else null
            val sb = if (isShort) b.asShortBuffer() else null

            var scale = 1f
            if (isFloat) {
                var pk = 0f
                for (i in 0 until N) {
                    val v = Math.abs(fb!!.get(i))
                    if (v > pk) pk = v
                }
                if (pk > peakSeen) peakSeen = pk
                if (peakSeen in 0.02f..1.5f) scale = 32768f
            }
            for (i in 0 until N) {
                tmp[i] = if (isFloat) fb!!.get(i) * scale else sb!!.get(i).toFloat()
            }
            val dry = tmp.copyOf()

            val vad = RnnoiseNative.process(handle, tmp)

            var sum = 0.0
            for (i in 0 until N) sum += (tmp[i] * tmp[i]).toDouble()
            val rms = Math.sqrt(sum / N).toFloat()
            if (vad > 0.6f && rms > 200f) {
                val want = (3000f / rms).coerceIn(1f, 3f)
                gain += (want - gain) * 0.03f
            } else {
                gain += (1f - gain) * 0.01f
            }

            for (i in 0 until N) {
                val o = (tmp[i] * WET + dry[i] * (1f - WET)) * gain
                val c = o.coerceIn(-32767f, 32767f)
                if (isFloat) fb!!.put(i, c / scale) else sb!!.put(i, c.toInt().toShort())
            }
            calls++
            if (calls == 200) Log.d(TAG, "audio ok float=$isFloat peakSeen=$peakSeen scale=$scale")
        } catch (t: Throwable) {
            Log.w(TAG, "audio process failed, turning off: $t")
            enabled = false
        }
    }
}