import com.baz.djmusi.engine.DeckEngine;
import com.baz.djmusi.engine.Mixer;
import com.baz.djmusi.engine.SamplerEngine;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

/** Sampler pads, headphone split cue and waveform colors. */
public class EngineTest3 {
    static void check(boolean ok, String what) {
        System.out.println((ok ? "PASS " : "FAIL ") + what);
        if (!ok) System.exit(1);
    }
    static ShortBuffer tone(int sr, double secs, double hz, double amp) {
        int frames = (int) (sr * secs);
        ShortBuffer pcm = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
        for (int i = 0; i < frames; i++) {
            short v = (short) (Math.sin(2 * Math.PI * hz * i / sr) * amp);
            pcm.put(i * 2, v); pcm.put(i * 2 + 1, v);
        }
        return pcm;
    }
    static double[] run(DeckEngine[] decks, SamplerEngine s, int chunks) {
        float[] mix = new float[512], cue = new float[512];
        double l = 0, r = 0;
        for (int c = 0; c < chunks; c++) {
            Mixer.mixChunk(decks, s, mix, cue, 256, 48000);
            for (int i = 0; i < 256; i++) { l += mix[i * 2] * mix[i * 2]; r += mix[i * 2 + 1] * mix[i * 2 + 1]; }
        }
        return new double[] { l, r };
    }
    public static void main(String[] a) {
        int sr = 44100;
        DeckEngine[] decks = { new DeckEngine(), new DeckEngine() };
        SamplerEngine s = new SamplerEngine();
        check(run(decks, s, 10)[0] == 0, "silent with nothing loaded");

        s.load(0, tone(sr, 0.5, 440, 10000), sr / 2, sr);
        s.trigger(0);
        double[] e = run(decks, s, 20);
        check(e[0] > 1 && e[1] > 1, "sampler pad plays: " + (int) e[0]);
        run(decks, s, 100); // 0.5 s sample is over by now
        check(run(decks, s, 10)[0] == 0 && !s.isPlaying(0), "pad stops at its end");
        s.trigger(0); run(decks, s, 2); s.stop(0);
        run(decks, s, 1);
        check(run(decks, s, 10)[0] == 0, "stop silences a pad");
        s.trigger(0); s.setVolume(0.2);
        double quiet = run(decks, s, 20)[0];
        check(quiet < e[0] * 0.1, "sampler volume works");

        // Split cue: deck A playing loud to the crowd, deck B cued with its fader down.
        decks[0].load(tone(sr, 5, 200, 8000), sr * 5, sr); decks[0].setPlaying(true);
        decks[1].load(tone(sr, 5, 300, 8000), sr * 5, sr); decks[1].setPlaying(true); decks[1].setGain(0);
        run(decks, s, 30);
        double[] noCue = run(decks, s, 50);
        check(Math.abs(noCue[0] - noCue[1]) < noCue[0] * 0.01, "no cue: both ears the same");
        decks[1].setCue(true); decks[0].setGain(0);
        run(decks, s, 5);
        double[] cue = run(decks, s, 50);
        check(cue[0] < 1e-3 && cue[1] > 1, "cue: right ear hears the cued deck under a closed fader");
        decks[0].setGain(1);
        run(decks, s, 5);
        double[] both = run(decks, s, 50);
        check(both[0] > 1 && both[1] > 1, "cue: left ear has the crowd mix");

        // Waveform colors: bass is dark, highs are bright.
        DeckEngine d = new DeckEngine();
        d.load(tone(sr, 2, 60, 10000), sr * 2, sr);
        float bass = d.getTones()[50];
        d.load(tone(sr, 2, 8000, 10000), sr * 2, sr);
        float hats = d.getTones()[50];
        check(bass < 0.15 && hats > 0.8, "waveform tone: 60 Hz=" + bass + ", 8 kHz=" + hats);
        System.out.println("ALL PASS");
    }
}
