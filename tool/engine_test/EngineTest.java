import com.baz.djmusi.engine.DeckEngine;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

public class EngineTest {
    static void check(boolean ok, String what) {
        System.out.println((ok ? "PASS " : "FAIL ") + what);
        if (!ok) System.exit(1);
    }

    public static void main(String[] a) {
        int sr = 44100, out = 48000, secs = 10, frames = sr * secs;
        ShortBuffer pcm = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
        for (int i = 0; i < frames; i++) {
            short v = (short) (Math.sin(2 * Math.PI * 440 * i / sr) * 12000);
            pcm.put(i * 2, v); pcm.put(i * 2 + 1, v);
        }
        DeckEngine d = new DeckEngine();
        d.load(pcm, frames, sr);
        check(d.durationMs() == 10000, "duration 10 s, got " + d.durationMs());
        check(d.getPeaks().length == secs * DeckEngine.PEAKS_PER_SECOND, "peaks count " + d.getPeaks().length);

        float[] buf = new float[240 * 2];
        // 1 s of normal play
        d.setPlaying(true);
        for (int b = 0; b < out / 240; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); }
        long p = d.positionMs();
        check(Math.abs(p - 970) < 40, "plays ~1 s (minus 60 ms motor start), pos=" + p);

        // Scratch: hand on record, pull back 500 ms over ~100 ms of finger events (60 Hz)
        d.scratchStart();
        long before = d.positionMs();
        int buffersPerEvent = out / 60 / 240 + 1;
        double maxStepMs = 0; long last = before; boolean wentBackwards = false;
        for (int e = 0; e < 6; e++) {
            d.scratchMoveMs(-500.0 / 6);
            for (int b = 0; b < buffersPerEvent; b++) {
                java.util.Arrays.fill(buf, 0); d.render(buf, 240, out);
                long now = d.positionMs();
                maxStepMs = Math.max(maxStepMs, Math.abs(now - last));
                if (now < last) wentBackwards = true;
                last = now;
            }
        }
        // let it settle while held still
        for (int b = 0; b < 20; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); }
        long after = d.positionMs();
        check(wentBackwards, "playhead runs backwards during a backward scratch");
        check(Math.abs((before - after) - 500) < 15, "lands 500 ms back, moved " + (before - after));
        check(maxStepMs < 60, "no jumps: biggest move per 5 ms buffer = " + maxStepMs + " ms");

        // Held still: silence (record not moving)
        java.util.Arrays.fill(buf, 0); d.render(buf, 240, out);
        double peak = 0; for (float f : buf) peak = Math.max(peak, Math.abs(f));
        check(peak < 0.01, "silent while held still, peak=" + peak);

        // Forward scratch makes sound
        d.scratchMoveMs(200);
        double energy = 0;
        for (int b = 0; b < 10; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); for (float f : buf) energy += f * f; }
        check(energy > 1, "forward scratch produces sound, energy=" + energy);

        // Release: motor resumes forward
        d.scratchEnd();
        long r0 = d.positionMs();
        for (int b = 0; b < out / 240 / 2; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); }
        long r1 = d.positionMs();
        check(r1 - r0 > 400 && r1 - r0 < 560, "resumes normal play after release, +" + (r1 - r0) + " ms in 0.5 s");

        // Loop 3000..3500 ms
        d.seekMs(3000); d.setLoopMs(3000, 3500);
        long maxPos = 0;
        for (int b = 0; b < out * 2 / 240; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); maxPos = Math.max(maxPos, d.positionMs()); }
        long lp = d.positionMs();
        check(maxPos <= 3501 && lp >= 3000, "loops between 3.0 and 3.5 s, max=" + maxPos + " now=" + lp);
        d.setLoopMs(-1, -1);

        // Tempo +8%
        d.seekMs(1000); d.setTempo(1.08);
        for (int b = 0; b < 10; b++) d.render(buf, 240, out); // settle ramp
        long t0 = d.positionMs();
        for (int b = 0; b < out / 240; b++) { java.util.Arrays.fill(buf, 0); d.render(buf, 240, out); }
        long t1 = d.positionMs();
        check(Math.abs((t1 - t0) - 1080) < 15, "tempo +8% plays 1.08 s per second: " + (t1 - t0));

        // Pause ramps down, then stops
        d.setPlaying(false);
        for (int b = 0; b < 40; b++) d.render(buf, 240, out);
        long s0 = d.positionMs();
        for (int b = 0; b < 40; b++) d.render(buf, 240, out);
        check(d.positionMs() == s0, "stops after pause");

        // Plays to end and stops
        d.seekMs(9900); d.setTempo(1); d.setPlaying(true);
        for (int b = 0; b < out / 240; b++) d.render(buf, 240, out);
        check(!d.isPlaying() && d.positionMs() >= 9990, "stops at the end, pos=" + d.positionMs());
        System.out.println("ALL PASS");
    }
}
