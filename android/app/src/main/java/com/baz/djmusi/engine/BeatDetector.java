package com.baz.djmusi.engine;

import java.nio.ShortBuffer;

/**
 * Estimates a song's tempo (BPM) and where its first beat falls, from how
 * the loudness jumps (onsets). Good enough for SYNC and beat-sized loops on
 * most dance/pop music.
 */
public final class BeatDetector {
    public static final class Result {
        public final double bpm;
        public final double firstBeatMs;
        Result(double bpm, double firstBeatMs) { this.bpm = bpm; this.firstBeatMs = firstBeatMs; }
    }

    private static final int HOP_HZ = 200; // onset envelope resolution: 5 ms

    public static Result detect(ShortBuffer pcm, int frames, int rate) {
        int hop = rate / HOP_HZ;
        double hopHz = rate / (double) hop; // exact (44100/220 = 200.45, not 200)
        // Analyse up to 2 minutes, skipping a long intro if the song is long.
        int startFrame = frames > rate * 150 ? rate * 30 : 0;
        int endFrame = Math.min(frames, startFrame + rate * 120);
        int n = (endFrame - startFrame) / hop;
        if (n < HOP_HZ * 8) return new Result(0, 0); // too short to tell

        double[] onset = new double[n];
        double prev = 0;
        for (int i = 0; i < n; i++) {
            double e = 0;
            int base = startFrame + i * hop;
            for (int f = base; f < base + hop; f += 2) {
                double m = (pcm.get(f * 2) + pcm.get(f * 2 + 1)) / 65536.0;
                e += m * m;
            }
            double loud = Math.log1p(e * 1000);
            onset[i] = Math.max(0, loud - prev);
            prev = loud;
        }

        // Autocorrelation over 70..180 BPM, gently preferring 90..140.
        int minLag = (int) (hopHz * 60.0 / 180), maxLag = (int) (hopHz * 60.0 / 70);
        double[] ac = new double[maxLag + 2];
        for (int lag = minLag - 1; lag <= maxLag + 1; lag++) {
            double s = 0;
            for (int i = lag; i < n; i++) s += onset[i] * onset[i - lag];
            ac[lag] = s / (n - lag);
        }
        int best = minLag;
        double bestScore = -1;
        for (int lag = minLag; lag <= maxLag; lag++) {
            double bpm = hopHz * 60.0 / lag;
            double weight = Math.exp(-0.5 * Math.pow(Math.log(bpm / 120) / 0.35, 2));
            // Count the double-period too: true beats line up at 2x the lag.
            double twice = 2 * lag < ac.length ? ac[2 * lag] : 0;
            double score = (ac[lag] + 0.5 * twice) * (0.7 + 0.3 * weight);
            if (score > bestScore) { bestScore = score; best = lag; }
        }
        // Parabolic refinement for sub-hop precision.
        double y0 = ac[best - 1], y1 = ac[best], y2 = ac[best + 1];
        double denom = y0 - 2 * y1 + y2;
        double lag = best + (denom != 0 ? 0.5 * (y0 - y2) / denom : 0);
        // Fine search: the beat grid (tempo + phase) that lands on the most
        // onset energy across the whole analysed stretch. Long stretches make
        // tiny tempo errors show up, so this pins the BPM to ~0.05.
        double bestScore2 = -1, bestLag = lag, phase = 0;
        for (double l = lag * 0.99; l <= lag * 1.01; l += lag * 0.0004) {
            for (double off = 0; off < l; off += 0.5) {
                double s = 0;
                for (double t = off; t < n - 1; t += l) {
                    int i0 = (int) t;
                    double fr = t - i0;
                    s += onset[i0] * (1 - fr) + onset[i0 + 1] * fr;
                }
                if (s > bestScore2) { bestScore2 = s; bestLag = l; phase = off; }
            }
        }
        double bpm = hopHz * 60.0 / bestLag;
        double firstBeatMs = (startFrame / (double) rate) * 1000 + phase * 1000.0 / hopHz;
        double beatMs = 60000.0 / bpm;
        firstBeatMs = firstBeatMs % beatMs; // earliest beat in the song
        return new Result(Math.round(bpm * 10) / 10.0, firstBeatMs);
    }
}
