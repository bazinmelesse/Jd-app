// DJ Musi web audio engine: a JavaScript port of the Android engine
// (android/app/src/main/java/com/baz/djmusi/engine). Runs inside an
// AudioWorklet when the browser has one, or on the page in a
// ScriptProcessorNode as a fallback. Songs are kept as interleaved 16-bit
// stereo, like on Android, already at the output sample rate.

class Biquad {
  constructor() { this.b0 = 1; this.b1 = 0; this.b2 = 0; this.a1 = 0; this.a2 = 0; this.z1 = [0, 0]; this.z2 = [0, 0]; }
  lowShelf(fs, f, db) { this.shelf(fs, f, db, true); }
  highShelf(fs, f, db) { this.shelf(fs, f, db, false); }
  peak(fs, f, q, db) {
    const A = Math.pow(10, db / 40), w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q);
    const cos = Math.cos(w), a0 = 1 + alpha / A;
    this.set((1 + alpha * A) / a0, -2 * cos / a0, (1 - alpha * A) / a0, -2 * cos / a0, (1 - alpha / A) / a0);
  }
  lowPass(fs, f, q) {
    const w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q), cos = Math.cos(w), a0 = 1 + alpha;
    this.set((1 - cos) / 2 / a0, (1 - cos) / a0, (1 - cos) / 2 / a0, -2 * cos / a0, (1 - alpha) / a0);
  }
  highPass(fs, f, q) {
    const w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q), cos = Math.cos(w), a0 = 1 + alpha;
    this.set((1 + cos) / 2 / a0, -(1 + cos) / a0, (1 + cos) / 2 / a0, -2 * cos / a0, (1 - alpha) / a0);
  }
  shelf(fs, f, db, low) {
    const A = Math.pow(10, db / 40), w = 2 * Math.PI * f / fs, cos = Math.cos(w);
    const alpha = Math.sin(w) / 2 * Math.SQRT2, sq = 2 * Math.sqrt(A) * alpha;
    const s = low ? 1 : -1;
    const a0 = (A + 1) + s * (A - 1) * cos + sq;
    this.set(A * ((A + 1) - s * (A - 1) * cos + sq) / a0,
      s * 2 * A * ((A - 1) - s * (A + 1) * cos) / a0,
      A * ((A + 1) - s * (A - 1) * cos - sq) / a0,
      -s * 2 * ((A - 1) + s * (A + 1) * cos) / a0,
      ((A + 1) + s * (A - 1) * cos - sq) / a0);
  }
  set(b0, b1, b2, a1, a2) { this.b0 = b0; this.b1 = b1; this.b2 = b2; this.a1 = a1; this.a2 = a2; }
  process(x, ch) {
    const y = this.b0 * x + this.z1[ch];
    this.z1[ch] = this.b1 * x - this.a1 * y + this.z2[ch];
    this.z2[ch] = this.b2 * x - this.a2 * y;
    return y;
  }
}

const SCRATCH_LAG_S = 0.012, MAX_SCRATCH_RATE = 12.0, MOTOR_RAMP_S = 0.06;
const FX_NONE = 0, FX_ECHO = 1, FX_FLANGER = 2;
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

class DeckEngine {
  constructor() {
    this.pcm = null; this.frames = 0; this.rate = 48000;
    this.playing = false; this.tempo = 1; this.gain = 1; this.scratching = false;
    this.scratchTarget = 0; this.seekRequest = -1; this.loopIn = -1; this.loopOut = -1;
    this.eqLow = 0; this.eqMid = 0; this.eqHigh = 0; this.filterAmount = 0;
    this.fxType = FX_NONE; this.fxAmount = 0.5; this.echoMs = 375; this.cueOn = false;
    this.playhead = 0; this.speed = 0; this.appliedGain = 1;
    this.low = new Biquad(); this.mid = new Biquad(); this.high = new Biquad(); this.filter = new Biquad();
    this.setLow = NaN; this.setMid = NaN; this.setHigh = NaN; this.setFilter = NaN; this.setRate = 0;
    this.tmp = new Float32Array(0); this.delay = new Float32Array(0); this.delayPos = 0; this.lfo = 0;
  }
  load(pcm, frames, rate) {
    this.playing = false; this.scratching = false; this.loopIn = this.loopOut = -1;
    this.pcm = pcm; this.frames = frames; this.rate = rate;
    this.playhead = 0; this.speed = 0; this.scratchTarget = 0; this.seekRequest = -1;
  }
  positionMs() { return this.playhead * 1000 / Math.max(1, this.rate); }
  seekMs(ms) { const f = clamp(ms * this.rate / 1000, 0, this.frames); this.playhead = f; this.scratchTarget = f; }
  setLoopMs(inMs, outMs) {
    if (inMs < 0 || outMs <= inMs) { this.loopIn = this.loopOut = -1; }
    else { this.loopIn = inMs * this.rate / 1000; this.loopOut = outMs * this.rate / 1000; }
  }
  scratchStart() { this.scratchTarget = this.playhead; this.scratching = true; }
  scratchMoveMs(d) { this.scratchTarget = clamp(this.scratchTarget + d * this.rate / 1000, 0, this.frames); }
  scratchEnd() { this.scratching = false; }

  render(outL, outR, cueL, cueR, n, outRate) {
    const data = this.pcm, frames = this.frames;
    if (!data || frames < 2) return;
    const step = this.rate / outRate;
    const rampPerFrame = 1.0 / (MOTOR_RAMP_S * outRate);
    const scr = this.scratching, target = this.scratchTarget;
    const motorRate = this.playing ? this.tempo : 0.0;
    const g0 = this.appliedGain, g1 = this.gain;
    const lIn = this.loopIn, lOut = this.loopOut;
    if (this.tmp.length < n * 2) this.tmp = new Float32Array(n * 2);
    const tmp = this.tmp; tmp.fill(0, 0, n * 2);
    let playhead = this.playhead, rate = this.speed;
    for (let i = 0; i < n; i++) {
      if (scr) {
        let desired = (target - playhead) / (SCRATCH_LAG_S * this.rate);
        desired = clamp(desired, -MAX_SCRATCH_RATE, MAX_SCRATCH_RATE);
        rate += (desired - rate) * 0.02;
      } else if (rate < motorRate) {
        rate = Math.min(motorRate, rate + rampPerFrame * Math.max(1, motorRate));
      } else if (rate > motorRate) {
        rate = Math.max(motorRate, rate - rampPerFrame * Math.max(1, Math.abs(rate)));
      }
      if (Math.abs(rate) > 1e-4) {
        const idx = playhead | 0;
        if (idx >= 0 && idx < frames - 1) {
          const frac = playhead - idx;
          const l0 = data[idx * 2], r0 = data[idx * 2 + 1], l1 = data[idx * 2 + 2], r1 = data[idx * 2 + 3];
          const k = Math.min(1.0, Math.abs(rate) * 8) / 32768.0;
          tmp[i * 2] = (l0 + (l1 - l0) * frac) * k;
          tmp[i * 2 + 1] = (r0 + (r1 - r0) * frac) * k;
        }
        playhead += rate * step;
      }
      if (!scr && lOut > lIn && lIn >= 0 && rate > 0 && playhead >= lOut) playhead -= (lOut - lIn);
      if (playhead < 0) { playhead = 0; if (!scr) rate = Math.max(rate, 0); }
      if (playhead > frames - 1) { playhead = frames - 1; if (!scr) { this.playing = false; rate = 0; } }
    }
    this.playhead = playhead; this.speed = rate;
    this.effects(tmp, n, outRate);
    for (let i = 0; i < n; i++) {
      const g = g0 + (g1 - g0) * i / n;
      outL[i] += tmp[i * 2] * g;
      outR[i] += tmp[i * 2 + 1] * g;
    }
    if (this.cueOn) for (let i = 0; i < n; i++) { cueL[i] += tmp[i * 2]; cueR[i] += tmp[i * 2 + 1]; }
    this.appliedGain = g1;
  }

  effects(buf, n, fs) {
    const lo = this.eqLow, mi = this.eqMid, hi = this.eqHigh, fa = this.filterAmount;
    if (fs !== this.setRate) { this.setRate = fs; this.setLow = this.setMid = this.setHigh = this.setFilter = NaN; }
    if (lo !== this.setLow) { this.low.lowShelf(fs, 180, lo); this.setLow = lo; }
    if (mi !== this.setMid) { this.mid.peak(fs, 1000, 0.7, mi); this.setMid = mi; }
    if (hi !== this.setHigh) { this.high.highShelf(fs, 5000, hi); this.setHigh = hi; }
    const filterOn = Math.abs(fa) > 0.02;
    if (filterOn && fa !== this.setFilter) {
      if (fa < 0) this.filter.lowPass(fs, 20000 * Math.pow(200.0 / 20000, -fa), 0.9);
      else this.filter.highPass(fs, 20 * Math.pow(5000.0 / 20, fa), 0.9);
      this.setFilter = fa;
    }
    const eqOn = lo !== 0 || mi !== 0 || hi !== 0;
    const fx = this.fxType, amt = this.fxAmount;
    if (!eqOn && !filterOn && fx === FX_NONE) return;
    if (fx !== FX_NONE && this.delay.length !== fs * 4) { this.delay = new Float32Array(fs * 4); this.delayPos = 0; }
    const delay = this.delay, len = delay.length / 2;
    for (let i = 0; i < n; i++) {
      for (let c = 0; c < 2; c++) {
        let x = buf[i * 2 + c];
        if (eqOn) x = this.high.process(this.mid.process(this.low.process(x, c), c), c);
        if (filterOn) x = this.filter.process(x, c);
        buf[i * 2 + c] = x;
      }
      if (fx === FX_ECHO) {
        const d = Math.min(len - 1, (this.echoMs * fs / 1000) | 0);
        const rp = (((this.delayPos - d) % len) + len) % len;
        for (let c = 0; c < 2; c++) {
          const x = buf[i * 2 + c], echo = delay[rp * 2 + c];
          delay[this.delayPos * 2 + c] = x + echo * 0.45;
          buf[i * 2 + c] = x + echo * amt;
        }
        this.delayPos = (this.delayPos + 1) % len;
      } else if (fx === FX_FLANGER) {
        this.lfo += 1000.0 / (Math.max(250, this.echoMs) * fs); if (this.lfo > 1) this.lfo -= 1;
        const d = (1 + 4 * (0.5 + 0.5 * Math.sin(2 * Math.PI * this.lfo))) * fs / 1000;
        for (let c = 0; c < 2; c++) {
          const x = buf[i * 2 + c];
          let rpos = this.delayPos - d; while (rpos < 0) rpos += len;
          const r0 = rpos | 0, r1 = (r0 + 1) % len, fr = rpos - r0;
          const wet = delay[r0 * 2 + c] * (1 - fr) + delay[r1 * 2 + c] * fr;
          delay[this.delayPos * 2 + c] = x + wet * 0.5;
          buf[i * 2 + c] = x + wet * amt * 0.8;
        }
        this.delayPos = (this.delayPos + 1) % len;
      }
    }
  }
}

class SamplerEngine {
  constructor() { this.samples = []; this.pos = []; this.volume = 0.8; }
  load(slot, pcm, frames, rate) { this.samples[slot] = { pcm, frames, rate }; this.pos[slot] = -1; }
  trigger(slot) { this.pos[slot] = 0; }
  stop(slot) { this.pos[slot] = -1; }
  render(outL, outR, n, outRate) {
    const vol = this.volume / 32768.0;
    for (let s = 0; s < this.samples.length; s++) {
      const smp = this.samples[s];
      let p = this.pos[s];
      if (!smp || p === undefined || p < 0) continue;
      const step = smp.rate / outRate;
      for (let i = 0; i < n; i++) {
        const idx = p | 0;
        if (idx >= smp.frames - 1) { p = -1; break; }
        const fr = p - idx, d = smp.pcm;
        outL[i] += (d[idx * 2] + (d[idx * 2 + 2] - d[idx * 2]) * fr) * vol;
        outR[i] += (d[idx * 2 + 1] + (d[idx * 2 + 3] - d[idx * 2 + 1]) * fr) * vol;
        p += step;
      }
      this.pos[s] = p;
    }
  }
}

/** Both decks + sampler, mixed like Mixer.java (split cue + soft limiter). */
class DjMixer {
  constructor(rate) {
    this.rate = rate;
    this.decks = [new DeckEngine(), new DeckEngine()];
    this.sampler = new SamplerEngine();
    this.cueL = new Float32Array(128); this.cueR = new Float32Array(128);
  }
  command(m) {
    const d = m.deck !== undefined ? this.decks[m.deck] : null;
    switch (m.cmd) {
      case 'load': d.load(m.pcm, m.frames, m.rate); break;
      case 'sampleLoad': this.sampler.load(m.slot, m.pcm, m.frames, m.rate); break;
      case 'sampleTrigger': this.sampler.trigger(m.slot); break;
      case 'sampleStop': this.sampler.stop(m.slot); break;
      case 'sampleVolume': this.sampler.volume = m.volume; break;
      case 'cue': d.cueOn = !!m.on; break;
      case 'play': d.playing = !!m.playing; break;
      case 'seek': d.seekMs(m.ms); break;
      case 'tempo': d.tempo = m.tempo; break;
      case 'gain': d.gain = m.gain; break;
      case 'loop': d.setLoopMs(m.inMs, m.outMs); break;
      case 'eq': d.eqLow = m.low; d.eqMid = m.mid; d.eqHigh = m.high; break;
      case 'filter': d.filterAmount = m.amount; break;
      case 'fx': d.fxType = m.type; d.fxAmount = m.amount; d.echoMs = m.delayMs; break;
      case 'scratchStart': d.scratchStart(); break;
      case 'scratchMove': d.scratchMoveMs(m.deltaMs); break;
      case 'scratchEnd': d.scratchEnd(); break;
    }
  }
  state() {
    const [a, b] = this.decks;
    return [a.positionMs(), b.positionMs(), a.playing, b.playing];
  }
  process(outL, outR) {
    const n = outL.length;
    outL.fill(0); outR.fill(0);
    if (this.cueL.length < n) { this.cueL = new Float32Array(n); this.cueR = new Float32Array(n); }
    const cueL = this.cueL, cueR = this.cueR;
    cueL.fill(0, 0, n); cueR.fill(0, 0, n);
    let split = false;
    for (const d of this.decks) { d.render(outL, outR, cueL, cueR, n, this.rate); split = split || d.cueOn; }
    this.sampler.render(outL, outR, n, this.rate);
    for (let i = 0; i < n; i++) {
      if (split) {
        const m = (outL[i] + outR[i]) * 0.5, c = (cueL[i] + cueR[i]) * 0.5;
        outL[i] = m; outR[i] = c;
      }
      let x = outL[i]; if (x > 0.8 || x < -0.8) outL[i] = Math.tanh(x);
      x = outR[i]; if (x > 0.8 || x < -0.8) outR[i] = Math.tanh(x);
    }
  }
}

if (typeof registerProcessor === 'function') {
  class DjProcessor extends AudioWorkletProcessor {
    constructor() {
      super();
      this.mixer = new DjMixer(sampleRate);
      this.blocks = 0;
      this.port.onmessage = (e) => this.mixer.command(e.data);
    }
    process(inputs, outputs) {
      const out = outputs[0];
      this.mixer.process(out[0], out[1] || out[0]);
      if (++this.blocks % 10 === 0) this.port.postMessage(this.mixer.state());
      return true;
    }
  }
  registerProcessor('dj-musi', DjProcessor);
} else if (typeof window !== 'undefined') {
  window.DjMixer = DjMixer;
}
