package com.baz.djmusi.engine;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Build;
import android.os.Process;

/**
 * Mixes the two decks and sends them to the speaker on a dedicated
 * high-priority thread, in small chunks for low latency (so the record
 * responds to a finger right away).
 */
public final class DjAudioEngine {
    public final DeckEngine[] decks = { new DeckEngine(), new DeckEngine() };
    public final SamplerEngine sampler = new SamplerEngine();

    private final int outRate;
    private AudioTrack track;
    private Thread thread;
    private volatile boolean running;

    /** Frames mixed per chunk: about 5 ms at 48 kHz. */
    private static final int CHUNK = 256;

    public DjAudioEngine(Context context) {
        int rate = 48000;
        AudioManager am = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (am != null) {
            String s = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE);
            if (s != null) try { rate = Integer.parseInt(s); } catch (NumberFormatException ignored) { }
        }
        outRate = rate;
    }

    public synchronized void start() {
        if (running) return;
        int minBytes = AudioTrack.getMinBufferSize(outRate,
                AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_FLOAT);
        int bufferBytes = Math.max(minBytes, CHUNK * 2 * 4 * 4);
        AudioTrack.Builder builder = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setSampleRate(outRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .build())
                .setBufferSizeInBytes(bufferBytes)
                .setTransferMode(AudioTrack.MODE_STREAM);
        if (Build.VERSION.SDK_INT >= 26) {
            builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY);
        }
        track = builder.build();
        track.play();
        running = true;
        thread = new Thread(this::loop, "dj-audio");
        thread.start();
    }

    private void loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO);
        float[] mix = new float[CHUNK * 2];
        float[] cue = new float[CHUNK * 2];
        while (running) {
            Mixer.mixChunk(decks, sampler, mix, cue, CHUNK, outRate);
            track.write(mix, 0, mix.length, AudioTrack.WRITE_BLOCKING);
        }
    }

    public synchronized void release() {
        running = false;
        if (thread != null) {
            try { thread.join(500); } catch (InterruptedException ignored) { }
            thread = null;
        }
        if (track != null) {
            track.stop();
            track.release();
            track = null;
        }
    }
}
