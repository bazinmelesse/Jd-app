package com.baz.djmusi.engine;

import java.nio.ShortBuffer;

/**
 * The sampler pads (air horn, siren, ...): short sounds decoded into memory
 * and played over the mix. A pad restarts if tapped again while playing.
 * Pure Java so it can be tested on a desktop JVM.
 */
public final class SamplerEngine {
    public static final int SLOTS = 8;

    private static final class Sample {
        final ShortBuffer pcm; // interleaved L,R
        final int frames, rate;
        Sample(ShortBuffer pcm, int frames, int rate) { this.pcm = pcm; this.frames = frames; this.rate = rate; }
    }

    private final Sample[] samples = new Sample[SLOTS];
    /** Playback position per slot in source frames; -1 = silent. Written by
     *  the UI thread only to (re)start a pad. */
    private final double[] pos = new double[SLOTS];
    private final boolean[] restart = new boolean[SLOTS];
    private volatile double volume = 0.8;

    public SamplerEngine() { java.util.Arrays.fill(pos, -1); }

    public synchronized void load(int slot, ShortBuffer pcm, int frames, int rate) {
        samples[slot] = new Sample(pcm, frames, rate);
    }

    public boolean isLoaded(int slot) { return samples[slot] != null; }

    public void trigger(int slot) {
        synchronized (restart) { restart[slot] = true; }
    }

    public void stop(int slot) {
        synchronized (restart) { restart[slot] = false; pos[slot] = -2; }
    }

    public boolean isPlaying(int slot) { return pos[slot] >= 0; }

    public void setVolume(double v) { volume = v; }

    public void render(float[] out, int outFrames, int outRate) {
        final float vol = (float) (volume / 32768.0);
        for (int s = 0; s < SLOTS; s++) {
            synchronized (restart) {
                if (restart[s]) { pos[s] = 0; restart[s] = false; }
                else if (pos[s] == -2) pos[s] = -1;
            }
            Sample smp = samples[s];
            double p = pos[s];
            if (smp == null || p < 0) continue;
            double step = (double) smp.rate / outRate;
            for (int i = 0; i < outFrames; i++) {
                int idx = (int) p;
                if (idx >= smp.frames - 1) { p = -1; break; }
                double fr = p - idx;
                float l0 = smp.pcm.get(idx * 2), r0 = smp.pcm.get(idx * 2 + 1);
                float l1 = smp.pcm.get(idx * 2 + 2), r1 = smp.pcm.get(idx * 2 + 3);
                out[i * 2] += (float) (l0 + (l1 - l0) * fr) * vol;
                out[i * 2 + 1] += (float) (r0 + (r1 - r0) * fr) * vol;
                p += step;
            }
            synchronized (restart) { if (!restart[s] && pos[s] != -2) pos[s] = p; }
        }
    }
}
