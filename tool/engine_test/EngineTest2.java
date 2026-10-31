import com.baz.djmusi.engine.DeckEngine;
import com.baz.djmusi.engine.BeatDetector;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

public class EngineTest2 {
    static void check(boolean ok, String what) {
        System.out.println((ok ? "PASS " : "FAIL ") + what);
        if (!ok) System.exit(1);
    }
    static ShortBuffer tone(int sr, int secs, double hz) {
        int frames = sr * secs;
        ShortBuffer pcm = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
        for (int i = 0; i < frames; i++) {
            short v = (short) (Math.sin(2 * Math.PI * hz * i / sr) * 12000);
            pcm.put(i * 2, v); pcm.put(i * 2 + 1, v);
        }
        return pcm;
    }
    static double energy(DeckEngine d, int out, int buffers) {
        float[] buf = new float[256 * 2]; double e = 0;
        for (int b = 0; b < buffers; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 256, out); for (float f : buf) e += f * f; }
        return e;
    }
    public static void main(String[] a) {
        int sr = 44100, out = 48000;
        // EQ low cut on a 60 Hz tone
        DeckEngine d = new DeckEngine(); d.load(tone(sr, 10, 60), sr * 10, sr); d.setPlaying(true);
        energy(d, out, 40);
        double flat = energy(d, out, 100);
        d.setEq(-26, 0, 0); energy(d, out, 20);
        double cut = energy(d, out, 100);
        check(cut < flat * 0.05, "low EQ kill cuts bass: " + (int)(10*Math.log10(cut/flat)) + " dB");
        d.setEq(0, 0, -26); energy(d, out, 20);
        double hiCutOnBass = energy(d, out, 100);
        check(hiCutOnBass > flat * 0.8, "high EQ cut leaves bass alone");

        // Filter: low-pass on an 8 kHz tone
        d = new DeckEngine(); d.load(tone(sr, 10, 8000), sr * 10, sr); d.setPlaying(true);
        energy(d, out, 40); flat = energy(d, out, 100);
        d.setFilter(-0.8); energy(d, out, 20);
        cut = energy(d, out, 100);
        check(cut < flat * 0.05, "low-pass filter muffles highs: " + (int)(10*Math.log10(cut/flat)) + " dB");
        d.setFilter(0);
        // Echo: tail continues after pausing
        d.setFx(DeckEngine.FX_ECHO, 0.8, 200); energy(d, out, 100);
        d.setPlaying(false); energy(d, out, 4); // past motor ramp (60 ms)
        double tail = energy(d, out, 30);
        check(tail > 1, "echo rings on after the music stops: " + tail);
        d.setFx(DeckEngine.FX_FLANGER, 0.8, 0); d.setPlaying(true);
        double fl = energy(d, out, 100);
        check(fl > 1 && !Double.isNaN(fl), "flanger runs");

        // BPM: clicks at 128 BPM, first beat at 250 ms
        int secs = 60, frames = sr * secs;
        ShortBuffer pcm = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
        java.util.Random rnd = new java.util.Random(1);
        double beat = 60.0 / 128;
        for (int i = 0; i < frames; i++) {
            double t = i / (double) sr - 0.25;
            double since = t - Math.floor(t / beat) * beat;
            double kick = t >= 0 ? Math.exp(-since * 30) * Math.sin(2 * Math.PI * 55 * since) : 0;
            double hat = rnd.nextGaussian() * 0.02;
            short v = (short) ((kick * 0.8 + hat) * 20000);
            pcm.put(i * 2, v); pcm.put(i * 2 + 1, v);
        }
        BeatDetector.Result r = BeatDetector.detect(pcm, frames, sr);
        check(Math.abs(r.bpm - 128) < 0.6, "detects 128 BPM, got " + r.bpm);
        double beatMs = 60000 / 128.0;
        double phaseErr = Math.abs(((r.firstBeatMs - 250) % beatMs + beatMs + beatMs/2) % beatMs - beatMs/2);
        check(phaseErr < 15, "finds the beat phase (250 ms), got " + r.firstBeatMs);

        for (double want : new double[] {96, 123.5, 140, 174}) {
            ShortBuffer p2 = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
            double bt = 60.0 / want;
            for (int i = 0; i < frames; i++) {
                double t = i / (double) sr - 0.1;
                double since = t - Math.floor(t / bt) * bt;
                double kick = t >= 0 ? Math.exp(-since * 30) * Math.sin(2 * Math.PI * 55 * since) : 0;
                short v = (short) ((kick * 0.8 + rnd.nextGaussian() * 0.02) * 20000);
                p2.put(i * 2, v); p2.put(i * 2 + 1, v);
            }
            BeatDetector.Result r2 = BeatDetector.detect(p2, frames, sr);
            check(Math.abs(r2.bpm - want) < 0.25, "detects " + want + " BPM, got " + r2.bpm);
        }
        // CPU: rendering 10 s with EQ + filter + echo should be far faster than real time
        d = new DeckEngine(); d.load(tone(sr, 30, 440), sr * 30, sr); d.setPlaying(true);
        d.setEq(-6, 2, 3); d.setFilter(0.3); d.setFx(DeckEngine.FX_ECHO, 0.5, 375);
        long t0 = System.nanoTime();
        energy(d, out, out * 10 / 256);
        double ms = (System.nanoTime() - t0) / 1e6;
        check(ms < 1000, "10 s of audio rendered in " + (int) ms + " ms");
        System.out.println("ALL PASS");
    }
}
