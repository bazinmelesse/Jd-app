package com.baz.djmusi.engine;

import java.nio.ShortBuffer;

/**
 * One turntable's audio: the whole song decoded into memory (16-bit stereo,
 * off the Java heap) and a playhead that can move forwards or backwards at
 * any speed. Scratching sets a target position; the playhead chases it
 * smoothly, which is what makes a finger on the record sound like vinyl.
 *
 * Pure Java (no Android classes) so it can be tested on a desktop JVM.
 * Control methods are called from the UI thread, render() from the audio
 * thread; shared fields are volatile and only written by one side.
 */
public final class DeckEngine {
    /** A decoded song; swapped as one piece so the audio thread never sees
     *  a new buffer with an old length. */
    private static final class Song {
        final ShortBuffer pcm; // interleaved L,R
        final int frames;
        final int rate;
        Song(ShortBuffer pcm, int frames, int rate) { this.pcm = pcm; this.frames = frames; this.rate = rate; }
    }

    private volatile Song song;
    private volatile int frames;               // song length in frames
    private volatile int sourceRate = 44100;   // song's sample rate
    private float[] peaks = new float[0];
    private float[] tones = new float[0];

    // Written by the UI thread.
    private volatile boolean playing;
    private volatile double tempo = 1.0;
    private volatile double gain = 1.0;
    private volatile boolean scratching;
    private volatile double scratchTarget;    // frames
    private volatile double seekRequest = -1; // frames, -1 = none
    private volatile double loopIn = -1, loopOut = -1;

    // EQ (dB), DJ filter (-1 low-pass .. 0 off .. +1 high-pass) and FX.
    private volatile double eqLowDb, eqMidDb, eqHighDb, filterAmount;
    public static final int FX_NONE = 0, FX_ECHO = 1, FX_FLANGER = 2;
    private volatile int fxType = FX_NONE;
    private volatile double fxAmount = 0.5;
    private volatile double echoMs = 375;
    /** Headphone cue (split mode): this deck also goes to the cue ear. */
    private volatile boolean cueOn;

    // Tempo analysis (filled in by load()).
    private volatile double bpm, firstBeatMs;

    // Audio-thread state.
    private double playhead;          // frames, fractional
    private double rate;              // current speed, signed (1 = normal)
    private double appliedGain = 1.0;
    private final Biquad low = new Biquad(), mid = new Biquad(), high = new Biquad(), filter = new Biquad();
    private double setLow = Double.NaN, setMid = Double.NaN, setHigh = Double.NaN, setFilter = Double.NaN;
    private int setRate;
    private float[] tmp = new float[0];
    private float[] delay = new float[0]; // echo/flanger memory, stereo
    private int delayPos;
    private double lfo;

    // Read by the UI thread.
    private volatile double reportedPlayhead;

    /** How quickly the playhead catches up with the finger (seconds). */
    private static final double SCRATCH_LAG_S = 0.012;
    /** Fastest a scratch may run, as a multiple of normal speed. */
    private static final double MAX_SCRATCH_RATE = 12.0;
    /** Motor start/stop ramp, so play and pause don't click. */
    private static final double MOTOR_RAMP_S = 0.06;
    /** Peaks per second of audio, for drawing the waveform. */
    public static final int PEAKS_PER_SECOND = 100;

    public synchronized void load(ShortBuffer stereoPcm, int frameCount, int sampleRate) {
        playing = false;
        scratching = false;
        loopIn = loopOut = -1;
        this.frames = frameCount;
        this.sourceRate = sampleRate;
        reportedPlayhead = 0;
        scratchTarget = 0;
        seekRequest = 0; // the audio thread resets its playhead
        this.song = new Song(stereoPcm, frameCount, sampleRate);
        float[][] wave = computePeaks(stereoPcm, frameCount, sampleRate);
        peaks = wave[0];
        tones = wave[1];
        BeatDetector.Result beats = BeatDetector.detect(stereoPcm, frameCount, sampleRate);
        bpm = beats.bpm;
        firstBeatMs = beats.firstBeatMs;
    }

    public boolean isLoaded() { return song != null; }
    public int getSourceRate() { return sourceRate; }
    public long durationMs() { return frames * 1000L / Math.max(1, sourceRate); }
    public long positionMs() { return (long) (reportedPlayhead * 1000 / Math.max(1, sourceRate)); }
    public float[] getPeaks() { return peaks; }
    /** Per peak: 0 = bass-heavy .. 1 = bright (hi-hats), to color the waveform. */
    public float[] getTones() { return tones; }
    public void setCue(boolean on) { cueOn = on; }
    public boolean isCueOn() { return cueOn; }
    public boolean isPlaying() { return playing; }

    public double getBpm() { return bpm; }
    public double getFirstBeatMs() { return firstBeatMs; }

    public void setEq(double lowDb, double midDb, double highDb) {
        eqLowDb = lowDb; eqMidDb = midDb; eqHighDb = highDb;
    }
    public void setFilter(double amount) { filterAmount = amount; }
    /** [param] is the echo delay in ms, or the flanger sweep period in ms. */
    public void setFx(int type, double amount, double param) {
        fxType = type; fxAmount = amount; echoMs = param;
    }

    public void setPlaying(boolean p) { playing = p; }
    public void setTempo(double t) { tempo = t; }
    public void setGain(double g) { gain = g; }

    public void seekMs(long ms) {
        double f = clamp(ms * (double) sourceRate / 1000.0, 0, frames);
        seekRequest = f;
        scratchTarget = f;
        reportedPlayhead = f;
    }

    /** Loop between two points (ms); pass -1 to clear. */
    public void setLoopMs(long inMs, long outMs) {
        if (inMs < 0 || outMs <= inMs) {
            loopIn = loopOut = -1;
        } else {
            loopIn = inMs * (double) sourceRate / 1000.0;
            loopOut = outMs * (double) sourceRate / 1000.0;
        }
    }

    /** Finger touches the record: it stops under the hand. */
    public void scratchStart() {
        scratchTarget = reportedPlayhead;
        scratching = true;
    }

    /** Finger moved the record by this much song time (negative = back). */
    public void scratchMoveMs(double deltaMs) {
        scratchTarget = clamp(scratchTarget + deltaMs * sourceRate / 1000.0, 0, frames);
    }

    /** Finger lets go: the motor takes over again (if playing). */
    public void scratchEnd() { scratching = false; }

    /**
     * Adds this deck's audio into [out] (interleaved stereo floats).
     * [outRate] is the output device's sample rate.
     */
    public void render(float[] out, int outFrames, int outRate) {
        render(out, null, outFrames, outRate);
    }

    /**
     * Same, and if this deck's headphone cue is on, also adds it (before the
     * channel fader) into [cue].
     */
    public void render(float[] out, float[] cue, int outFrames, int outRate) {
        final Song s = song;
        if (s == null || s.frames < 2) return;
        final ShortBuffer data = s.pcm;
        final int frames = s.frames;
        final int sourceRate = s.rate;

        final double sr = seekRequest;
        if (sr >= 0) {
            playhead = sr;
            seekRequest = -1;
        }

        final double step = (double) sourceRate / outRate; // frames per out frame at speed 1
        final double rampPerFrame = 1.0 / (MOTOR_RAMP_S * outRate);
        final boolean scr = scratching;
        final double target = scratchTarget;
        final double motorRate = playing ? tempo : 0.0;
        final double g0 = appliedGain, g1 = gain;
        final double lIn = loopIn, lOut = loopOut;
        if (tmp.length < outFrames * 2) tmp = new float[outFrames * 2];
        java.util.Arrays.fill(tmp, 0, outFrames * 2, 0f);

        for (int i = 0; i < outFrames; i++) {
            if (scr) {
                // Chase the finger: speed proportional to how far behind we are.
                double desired = (target - playhead) / (SCRATCH_LAG_S * sourceRate);
                desired = clamp(desired, -MAX_SCRATCH_RATE, MAX_SCRATCH_RATE);
                rate += (desired - rate) * 0.02; // smooth out finger jitter
            } else if (rate < motorRate) {
                rate = Math.min(motorRate, rate + rampPerFrame * Math.max(1, motorRate));
            } else if (rate > motorRate) {
                rate = Math.max(motorRate, rate - rampPerFrame * Math.max(1, Math.abs(rate)));
            }

            if (Math.abs(rate) > 1e-4) {
                // Linear interpolation between the two nearest samples.
                int idx = (int) playhead;
                if (idx >= 0 && idx < frames - 1) {
                    double frac = playhead - idx;
                    float l0 = data.get(idx * 2), r0 = data.get(idx * 2 + 1);
                    float l1 = data.get(idx * 2 + 2), r1 = data.get(idx * 2 + 3);
                    // Scratch sound gets quieter as the record slows to a halt.
                    double k = Math.min(1.0, Math.abs(rate) * 8) / 32768.0;
                    tmp[i * 2] = (float) ((l0 + (l1 - l0) * frac) * k);
                    tmp[i * 2 + 1] = (float) ((r0 + (r1 - r0) * frac) * k);
                }
                playhead += rate * step;
            }

            if (!scr && lOut > lIn && lIn >= 0 && rate > 0 && playhead >= lOut) {
                playhead -= (lOut - lIn); // sample-accurate loop
            }
            if (playhead < 0) { playhead = 0; if (!scr) rate = Math.max(rate, 0); }
            if (playhead > frames - 1) {
                playhead = frames - 1;
                if (!scr) { playing = false; rate = 0; } // song ended
            }
        }
        effects(tmp, outFrames, outRate);
        for (int i = 0; i < outFrames; i++) {
            float g = (float) (g0 + (g1 - g0) * i / outFrames);
            out[i * 2] += tmp[i * 2] * g;
            out[i * 2 + 1] += tmp[i * 2 + 1] * g;
        }
        if (cue != null && cueOn) {
            for (int i = 0; i < outFrames * 2; i++) cue[i] += tmp[i];
        }
        appliedGain = g1;
        reportedPlayhead = playhead;
    }

    /** EQ, then the DJ filter, then echo/flanger. Runs on the audio thread. */
    private void effects(float[] buf, int n, int fs) {
        double lo = eqLowDb, mi = eqMidDb, hi = eqHighDb, fa = filterAmount;
        if (fs != setRate) { setRate = fs; setLow = setMid = setHigh = setFilter = Double.NaN; }
        if (lo != setLow) { low.lowShelf(fs, 180, lo); setLow = lo; }
        if (mi != setMid) { mid.peak(fs, 1000, 0.7, mi); setMid = mi; }
        if (hi != setHigh) { high.highShelf(fs, 5000, hi); setHigh = hi; }
        boolean filterOn = Math.abs(fa) > 0.02;
        if (filterOn && fa != setFilter) {
            if (fa < 0) filter.lowPass(fs, 20000 * Math.pow(200.0 / 20000, -fa), 0.9);
            else filter.highPass(fs, 20 * Math.pow(5000.0 / 20, fa), 0.9);
            setFilter = fa;
        }
        boolean eqOn = lo != 0 || mi != 0 || hi != 0;
        int fx = fxType;
        double amt = fxAmount;
        if (fx != FX_NONE && delay.length != fs * 4) { delay = new float[fs * 4]; delayPos = 0; }
        int len = delay.length / 2;
        for (int i = 0; i < n; i++) {
            for (int c = 0; c < 2; c++) {
                float x = buf[i * 2 + c];
                if (eqOn) x = high.process(mid.process(low.process(x, c), c), c);
                if (filterOn) x = filter.process(x, c);
                buf[i * 2 + c] = x;
            }
            if (fx == FX_ECHO) {
                int d = (int) Math.min(len - 1, echoMs * fs / 1000);
                int rp = ((delayPos - d) % len + len) % len;
                for (int c = 0; c < 2; c++) {
                    float x = buf[i * 2 + c];
                    float echo = delay[rp * 2 + c];
                    delay[delayPos * 2 + c] = x + echo * 0.45f;
                    buf[i * 2 + c] = x + (float) (echo * amt);
                }
                delayPos = (delayPos + 1) % len;
            } else if (fx == FX_FLANGER) {
                lfo += 1000.0 / (Math.max(250, echoMs) * fs); if (lfo > 1) lfo -= 1;
                double dMs = 1 + 4 * (0.5 + 0.5 * Math.sin(2 * Math.PI * lfo));
                double d = dMs * fs / 1000;
                for (int c = 0; c < 2; c++) {
                    float x = buf[i * 2 + c];
                    double rpos = delayPos - d;
                    while (rpos < 0) rpos += len;
                    int r0 = (int) rpos, r1 = (r0 + 1) % len;
                    double fr = rpos - r0;
                    float wet = (float) (delay[r0 * 2 + c] * (1 - fr) + delay[r1 * 2 + c] * fr);
                    delay[delayPos * 2 + c] = x + wet * 0.5f;
                    buf[i * 2 + c] = (float) (x + wet * amt * 0.8);
                }
                delayPos = (delayPos + 1) % len;
            }
        }
    }

    /**
     * Waveform data: the loudest sample in each slice, and how bright the
     * slice sounds (share of energy in the sample-to-sample changes, which is
     * high for cymbals and low for bass).
     */
    private static float[][] computePeaks(ShortBuffer data, int frames, int rate) {
        int window = Math.max(1, rate / PEAKS_PER_SECOND);
        int n = frames / window;
        float[] result = new float[n];
        float[] tone = new float[n];
        for (int p = 0; p < n; p++) {
            int max = 0;
            double energy = 1e-9, diff = 0;
            int start = p * window;
            int prev = data.get(start * 2) + data.get(start * 2 + 1);
            for (int f = start; f < start + window; f += 2) {
                int l = data.get(f * 2), r = data.get(f * 2 + 1);
                int v = Math.max(Math.abs(l), Math.abs(r));
                if (v > max) max = v;
                int m = l + r;
                energy += (double) m * m;
                diff += (double) (m - prev) * (m - prev);
                prev = m;
            }
            result[p] = max / 32768f;
            // diff/energy is about 0 for deep bass and up to 4 for noise.
            tone[p] = (float) Math.min(1.0, Math.sqrt(diff / energy / 4) * 1.6);
        }
        return new float[][] { result, tone };
    }

    private static double clamp(double v, double lo, double hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
