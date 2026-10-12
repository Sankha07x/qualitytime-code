package com.example.QualityTime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.nio.ByteOrder

/** Blur / background image / denoise on the camera video, before encoding. */
object VideoFx : LocalVideoTrack.ExternalVideoFrameProcessing {
    private const val TAG = "QT_FX"

    private var mode = 0 // 0 off, 1 blur, 2 image
    private var denoise = false
    private var fast = false
    private var bgPath = ""
    private var appCtx: Context? = null
    private var onAutoOff: ((String) -> Unit)? = null

    private var attached: LocalVideoTrack? = null
    private var prevOut: VideoFrame? = null
    private var seg: ImageSegmenter? = null
    private var segBroken = false
    private var blocked = false
    private var failCount = 0
    private var slowEma = 0f
    private var speedCount = 0
    private var tick = 0
    private var mask: FloatArray? = null
    private var maskW = 0
    private var maskH = 0
    private var invert = false
    private var prevY: ByteArray? = null
    private var bgImg: VideoFrame.I420Buffer? = null

    @Synchronized
    fun configure(
        trackId: String, mode: Int, denoise: Boolean, fast: Boolean,
        bgPath: String, context: Context, onAutoOff: (String) -> Unit
    ) {
        this.mode = mode
        this.denoise = denoise
        this.fast = fast
        if (bgPath != this.bgPath) {
            this.bgPath = bgPath
            dropBg()
        }
        this.appCtx = context.applicationContext
        this.onAutoOff = onAutoOff
        if (trackId.isEmpty()) {
            detach()
            releaseAll()
            return
        }
        val t = FlutterWebRTCPlugin.sharedSingleton.getLocalTrack(trackId) as? LocalVideoTrack
        if (t == null) {
            Log.w(TAG, "camera track not found")
            return
        }
        if (t !== attached) {
            detach()
            t.addProcessor(this)
            attached = t
        }
        blocked = false
        segBroken = false
        failCount = 0
        speedCount = 0
        slowEma = 0f
    }

    private fun detach() {
        try { attached?.removeProcessor(this) } catch (_: Throwable) {}
        attached = null
        dropPrev()
    }

    private fun releaseAll() {
        try { seg?.close() } catch (_: Throwable) {}
        seg = null
        mask = null
        prevY = null
        invert = false
        dropBg()
    }

    private fun dropPrev() {
        try { prevOut?.release() } catch (_: Throwable) {}
        prevOut = null
    }

    private fun dropBg() {
        try { bgImg?.release() } catch (_: Throwable) {}
        bgImg = null
    }

    private fun notify(why: String) {
        try { onAutoOff?.invoke(why) } catch (_: Throwable) {}
    }

    @Synchronized
    override fun onFrame(frame: VideoFrame): VideoFrame {
        var m = mode
        if (segBroken) m = 0
        if (blocked || (m == 0 && !denoise)) {
            dropPrev()
            return frame
        }
        val t0 = System.nanoTime()
        var src: VideoFrame.I420Buffer? = null
        try {
            src = frame.buffer.toI420()
            val out = build(frame, src!!, m)
            dropPrev()
            prevOut = out
            failCount = 0
            watchSpeed((System.nanoTime() - t0) / 1_000_000f)
            return out
        } catch (e: Throwable) {
            Log.w(TAG, "frame failed: $e")
            failCount++
            if (failCount >= 5) {
                blocked = true
                notify("error")
            }
            return frame
        } finally {
            try { src?.release() } catch (_: Throwable) {}
        }
    }

    private fun watchSpeed(ms: Float) {
        speedCount++
        slowEma = if (speedCount < 2) ms else slowEma * 0.95f + ms * 0.05f
        if (speedCount > 45 && slowEma > 55f) {
            slowEma = 0f
            speedCount = 0
            if (mode != 0 && !segBroken) {
                segBroken = true
                notify("slow")
            } else {
                blocked = true
                notify("slow")
            }
        }
    }

    private fun even(v: Int) = maxOf(2, v and 1.inv())

    private fun scaled(b: VideoFrame.I420Buffer, w: Int, h: Int): VideoFrame.I420Buffer {
        val s = b.cropAndScale(0, 0, b.width, b.height, w, h)
        val i = s.toI420() ?: throw IllegalStateException("scale failed")
        s.release()
        return i
    }

    private fun build(frame: VideoFrame, src: VideoFrame.I420Buffer, m: Int): VideoFrame {
        val longSide = if (fast) 426 else 640
        val scale = minOf(1f, longSide.toFloat() / maxOf(src.width, src.height))
        val w = even((src.width * scale).toInt())
        val h = even((src.height * scale).toInt())
        val work = scaled(src, w, h)
        val out = JavaI420Buffer.allocate(w, h)
        try {
            var done = false
            if (m != 0 && refreshMask(work)) {
                val bg = background(work, w, h, m)
                try {
                    composite(work, bg, out, w, h)
                    done = true
                } finally {
                    bg.release()
                }
            }
            if (!done) copyPlanes(work, out, w, h)
            if (denoise) denoiseY(out, w, h)
        } catch (t: Throwable) {
            out.release()
            throw t
        } finally {
            work.release()
        }
        return VideoFrame(out, frame.rotation, frame.timestampNs)
    }

    private fun copyPlanes(a: VideoFrame.I420Buffer, o: JavaI420Buffer, w: Int, h: Int) {
        val ay = a.dataY; val au = a.dataU; val av = a.dataV
        val oy = o.dataY; val ou = o.dataU; val ov = o.dataV
        for (j in 0 until h) for (i in 0 until w)
            oy.put(j * o.strideY + i, ay.get(j * a.strideY + i))
        for (j in 0 until h / 2) for (i in 0 until w / 2) {
            ou.put(j * o.strideU + i, au.get(j * a.strideU + i))
            ov.put(j * o.strideV + i, av.get(j * a.strideV + i))
        }
    }

    // ---- background (blurred copy, or the chosen image) ----
    private fun background(work: VideoFrame.I420Buffer, w: Int, h: Int, m: Int): VideoFrame.I420Buffer {
        if (m == 2 && bgPath.isNotEmpty()) {
            val img = bgImage(w, h)
            if (img != null) {
                img.retain()
                return img
            }
        }
        val small = scaled(work, even(w / 10), even(h / 10))
        val big = scaled(small, w, h)
        small.release()
        return big
    }

    private fun bgImage(w: Int, h: Int): VideoFrame.I420Buffer? {
        val cur = bgImg
        if (cur != null && cur.width == w && cur.height == h) return cur
        dropBg()
        try {
            val bo = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(bgPath, bo)
            if (bo.outWidth <= 0) return null
            val sample = maxOf(1, minOf(bo.outWidth / w, bo.outHeight / h))
            val bmp = BitmapFactory.decodeFile(
                bgPath, BitmapFactory.Options().apply { inSampleSize = sample }
            ) ?: return null
            val sc = maxOf(w.toFloat() / bmp.width, h.toFloat() / bmp.height)
            val sw = maxOf(w, (bmp.width * sc).toInt())
            val sh = maxOf(h, (bmp.height * sc).toInt())
            val big = Bitmap.createScaledBitmap(bmp, sw, sh, true)
            val px = IntArray(w * h)
            big.getPixels(px, 0, w, (sw - w) / 2, (sh - h) / 2, w, h)
            val b = JavaI420Buffer.allocate(w, h)
            val dy = b.dataY; val du = b.dataU; val dv = b.dataV
            for (j in 0 until h) for (i in 0 until w) {
                val c = px[j * w + i]
                val r = Color.red(c); val g = Color.green(c); val bl = Color.blue(c)
                dy.put(j * b.strideY + i, (((66 * r + 129 * g + 25 * bl + 128) shr 8) + 16).toByte())
                if (j % 2 == 0 && i % 2 == 0) {
                    du.put((j / 2) * b.strideU + i / 2,
                        (((-38 * r - 74 * g + 112 * bl + 128) shr 8) + 128).toByte())
                    dv.put((j / 2) * b.strideV + i / 2,
                        (((112 * r - 94 * g - 18 * bl + 128) shr 8) + 128).toByte())
                }
            }
            bgImg = b
            return b
        } catch (t: Throwable) {
            Log.w(TAG, "background image failed: $t")
            return null
        }
    }

    // ---- person mask (MediaPipe selfie segmenter) ----
    private fun getSegmenter(): ImageSegmenter {
        seg?.let { return it }
        val ctx = appCtx ?: throw IllegalStateException("no context")
        val opts = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("selfie_segmenter.tflite").build())
            .setRunningMode(RunningMode.IMAGE)
            .setOutputConfidenceMasks(true)
            .setOutputCategoryMask(false)
            .build()
        val s = ImageSegmenter.createFromOptions(ctx, opts)
        seg = s
        return s
    }

    private fun refreshMask(work: VideoFrame.I420Buffer): Boolean {
        val k = if (fast) 3 else 2
        tick++
        if (mask != null && tick % k != 0) return true
        try {
            val sg = getSegmenter()
            val small = scaled(work, 256, 256)
            val bmp = toBitmap(small)
            small.release()
            val input = BitmapImageBuilder(bmp).build()
            val res = sg.segment(input)
            input.close()
            val list = res.confidenceMasks().orElse(null)
            if (list == null || list.isEmpty()) throw IllegalStateException("no mask")
            val mi = list[if (list.size >= 2) 1 else 0]
            val mw = mi.width
            val mh = mi.height
            val n = mw * mh
            val fb = ByteBufferExtractor.extract(mi).order(ByteOrder.nativeOrder()).asFloatBuffer()
            if (fb.remaining() < n) throw IllegalStateException("bad mask size")
            val fresh = FloatArray(n)
            fb.get(fresh, 0, n)
            for (x in list) x.close()
            orient(fresh, mw, mh)
            val cur = mask
            if (cur == null || cur.size != n) {
                mask = fresh
                maskW = mw
                maskH = mh
            } else {
                for (i in 0 until n) cur[i] = cur[i] * 0.5f + fresh[i] * 0.5f
            }
            return true
        } catch (t: Throwable) {
            Log.w(TAG, "segmentation failed: $t")
            segBroken = true
            notify("model")
            return false
        }
    }

    // The person is normally in the middle of the picture. If the mask says the
    // opposite, flip it (and remember).
    private fun orient(a: FloatArray, w: Int, h: Int) {
        if (!invert) {
            var c = 0f; var cn = 0; var e = 0f; var en = 0
            for (y in 0 until h step 4) for (x in 0 until w step 4) {
                val center = x in (w * 35 / 100)..(w * 65 / 100) && y in (h * 30 / 100)..(h * 70 / 100)
                val edge = x < w / 10 || x >= w * 9 / 10
                if (center) { c += a[y * w + x]; cn++ }
                else if (edge) { e += a[y * w + x]; en++ }
            }
            if (cn > 0 && en > 0 && e / en - c / cn > 0.3f) {
                invert = true
                Log.d(TAG, "mask flipped")
            }
        }
        if (invert) for (i in a.indices) a[i] = 1f - a[i]
    }

    private fun toBitmap(b: VideoFrame.I420Buffer): Bitmap {
        val w = b.width
        val h = b.height
        val px = IntArray(w * h)
        val y = b.dataY; val u = b.dataU; val v = b.dataV
        for (j in 0 until h) for (i in 0 until w) {
            val yy = y.get(j * b.strideY + i).toInt() and 0xFF
            val uu = (u.get((j / 2) * b.strideU + i / 2).toInt() and 0xFF) - 128
            val vv = (v.get((j / 2) * b.strideV + i / 2).toInt() and 0xFF) - 128
            val r = (yy + 1.402f * vv).toInt().coerceIn(0, 255)
            val g = (yy - 0.344f * uu - 0.714f * vv).toInt().coerceIn(0, 255)
            val bl = (yy + 1.772f * uu).toInt().coerceIn(0, 255)
            px[j * w + i] = Color.rgb(r, g, bl)
        }
        return Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
    }

    private fun composite(
        work: VideoFrame.I420Buffer, bg: VideoFrame.I420Buffer,
        out: JavaI420Buffer, w: Int, h: Int
    ) {
        val mk = mask ?: throw IllegalStateException("no mask")
        val mw = maskW
        val mh = maskH
        val wy = work.dataY; val wu = work.dataU; val wv = work.dataV
        val by = bg.dataY; val bu = bg.dataU; val bv = bg.dataV
        val oy = out.dataY; val ou = out.dataU; val ov = out.dataV
        for (j in 0 until h) {
            val row = (j * mh / h) * mw
            for (i in 0 until w) {
                val a = ((mk[row + i * mw / w] - 0.35f) / 0.3f).coerceIn(0f, 1f)
                val s = wy.get(j * work.strideY + i).toInt() and 0xFF
                val b = by.get(j * bg.strideY + i).toInt() and 0xFF
                oy.put(j * out.strideY + i, (s * a + b * (1f - a)).toInt().toByte())
            }
        }
        for (j in 0 until h / 2) {
            val row = ((j * 2) * mh / h) * mw
            for (i in 0 until w / 2) {
                val a = ((mk[row + (i * 2) * mw / w] - 0.35f) / 0.3f).coerceIn(0f, 1f)
                val su = wu.get(j * work.strideU + i).toInt() and 0xFF
                val bU = bu.get(j * bg.strideU + i).toInt() and 0xFF
                val sv = wv.get(j * work.strideV + i).toInt() and 0xFF
                val bV = bv.get(j * bg.strideV + i).toInt() and 0xFF
                ou.put(j * out.strideU + i, (su * a + bU * (1f - a)).toInt().toByte())
                ov.put(j * out.strideV + i, (sv * a + bV * (1f - a)).toInt().toByte())
            }
        }
    }

    // ---- camera denoise: blend with the previous picture where little changed ----
    private fun denoiseY(o: JavaI420Buffer, w: Int, h: Int) {
        val oy = o.dataY
        var p = prevY
        if (p == null || p.size != w * h) {
            p = ByteArray(w * h)
            prevY = p
        }
        for (j in 0 until h) for (i in 0 until w) {
            val cur = oy.get(j * o.strideY + i).toInt() and 0xFF
            val pv = p[j * w + i].toInt() and 0xFF
            val d = Math.abs(cur - pv)
            val v = if (d < 4) pv + (cur - pv) / 4 else if (d < 12) pv + (cur - pv) / 2 else cur
            oy.put(j * o.strideY + i, v.toByte())
            p[j * w + i] = v.toByte()
        }
    }
}