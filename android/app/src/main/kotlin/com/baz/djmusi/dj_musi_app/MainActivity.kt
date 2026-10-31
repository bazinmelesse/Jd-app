package com.baz.djmusi.dj_musi_app

import android.os.Handler
import android.os.Looper
import com.baz.djmusi.engine.AudioDecoder
import com.baz.djmusi.engine.DjAudioEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Hosts the DJ audio engine (two decks that can scratch backwards and
 * forwards) and exposes it to Flutter on the "djmusi/engine" channel.
 */
class MainActivity : FlutterActivity() {
    private var engine: DjAudioEngine? = null
    private val decoder = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private fun engine(): DjAudioEngine =
        engine ?: DjAudioEngine(this).also { it.start(); engine = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "djmusi/engine")
            .setMethodCallHandler { call, result ->
                val e = engine()
                val deck = call.argument<Int>("deck")?.let { e.decks[it] }
                try {
                    when (call.method) {
                        "load" -> {
                            val path = call.argument<String>("path")!!
                            deck!!.setPlaying(false)
                            decoder.execute {
                                try {
                                    val decoded = AudioDecoder.decode(path)
                                    deck.load(decoded.pcm, decoded.frames, decoded.sampleRate)
                                    main.post {
                                        result.success(mapOf(
                                            "durationMs" to deck.durationMs(),
                                            "peaks" to deck.peaks,
                                            "tones" to deck.tones,
                                            "peaksPerSecond" to com.baz.djmusi.engine.DeckEngine.PEAKS_PER_SECOND,
                                            "bpm" to deck.bpm,
                                            "firstBeatMs" to deck.firstBeatMs,
                                        ))
                                    }
                                } catch (t: Throwable) {
                                    main.post { result.error("decode", t.message ?: t.toString(), null) }
                                }
                            }
                            return@setMethodCallHandler
                        }
                        "sampleLoad" -> {
                            val slot = call.argument<Int>("slot")!!
                            val path = call.argument<String>("path")!!
                            decoder.execute {
                                try {
                                    val d = AudioDecoder.decode(path)
                                    e.sampler.load(slot, d.pcm, d.frames, d.sampleRate)
                                    main.post { result.success(null) }
                                } catch (t: Throwable) {
                                    main.post { result.error("decode", t.message ?: t.toString(), null) }
                                }
                            }
                            return@setMethodCallHandler
                        }
                        "sampleTrigger" -> e.sampler.trigger(call.argument<Int>("slot")!!)
                        "sampleStop" -> e.sampler.stop(call.argument<Int>("slot")!!)
                        "sampleVolume" -> e.sampler.setVolume(call.argument<Double>("volume")!!)
                        "cue" -> deck!!.setCue(call.argument<Boolean>("on")!!)
                        "play" -> deck!!.setPlaying(call.argument<Boolean>("playing")!!)
                        "seek" -> deck!!.seekMs((call.argument<Number>("ms")!!).toLong())
                        "tempo" -> deck!!.setTempo(call.argument<Double>("tempo")!!)
                        "gain" -> deck!!.setGain(call.argument<Double>("gain")!!)
                        "loop" -> deck!!.setLoopMs(
                            (call.argument<Number>("inMs")!!).toLong(),
                            (call.argument<Number>("outMs")!!).toLong())
                        "eq" -> deck!!.setEq(
                            call.argument<Double>("low")!!,
                            call.argument<Double>("mid")!!,
                            call.argument<Double>("high")!!)
                        "filter" -> deck!!.setFilter(call.argument<Double>("amount")!!)
                        "fx" -> deck!!.setFx(
                            call.argument<Int>("type")!!,
                            call.argument<Double>("amount")!!,
                            call.argument<Double>("delayMs")!!)
                        "scratchStart" -> deck!!.scratchStart()
                        "scratchMove" -> deck!!.scratchMoveMs(call.argument<Double>("deltaMs")!!)
                        "scratchEnd" -> deck!!.scratchEnd()
                        "state" -> {
                            result.success(listOf(
                                e.decks[0].positionMs(), e.decks[1].positionMs(),
                                e.decks[0].isPlaying, e.decks[1].isPlaying))
                            return@setMethodCallHandler
                        }
                        else -> { result.notImplemented(); return@setMethodCallHandler }
                    }
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("engine", t.message ?: t.toString(), null)
                }
            }
    }

    override fun onDestroy() {
        engine?.release()
        engine = null
        decoder.shutdown()
        super.onDestroy()
    }
}
