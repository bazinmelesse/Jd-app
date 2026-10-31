package com.baz.djmusi.engine;

/** Mixes the decks and sampler into one output chunk. */
public final class Mixer {
    private Mixer() { }

    /**
     * Mixes one chunk. When a deck's headphone cue is on, the output splits
     * like edjing's "split mode": the left ear gets the crowd mix (mono) and
     * the right ear gets the cued deck(s), so you can line up the next song
     * on headphones. Android-free so it can be tested on a JVM.
     */
    public static void mixChunk(DeckEngine[] decks, SamplerEngine sampler,
                                float[] mix, float[] cue, int frames, int rate) {
        java.util.Arrays.fill(mix, 0, frames * 2, 0f);
        java.util.Arrays.fill(cue, 0, frames * 2, 0f);
        boolean split = false;
        for (DeckEngine d : decks) {
            d.render(mix, cue, frames, rate);
            split |= d.isCueOn();
        }
        sampler.render(mix, frames, rate);
        if (split) {
            for (int i = 0; i < frames; i++) {
                float m = (mix[i * 2] + mix[i * 2 + 1]) * 0.5f;
                float c = (cue[i * 2] + cue[i * 2 + 1]) * 0.5f;
                mix[i * 2] = m;
                mix[i * 2 + 1] = c;
            }
        }
        // Gentle limiter so two loud decks don't distort harshly.
        for (int i = 0; i < frames * 2; i++) {
            float x = mix[i];
            if (x > 0.8f || x < -0.8f) mix[i] = (float) Math.tanh(x);
        }
    }
}
