// Page side of the DJ Musi web engine. Flutter calls window.djEngine.call()
// with the same method names and arguments as the Android "djmusi/engine"
// channel (see MainActivity.kt). Results come back as JSON strings.
(function () {
  const PEAKS_PER_SECOND = 100;
  let ctx = null, node = null, mixer = null, ready = null;
  let lastState = [0, 0, false, false];
  const files = new Map(); // id -> File picked from this device
  let nextId = 1;

  function context() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      ctx = new AC({ latencyHint: 'interactive' });
      try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch (_) {}
    }
    return ctx;
  }

  // Phones only allow sound after a tap: wake the audio up on every tap.
  function unlock() {
    const c = context();
    if (c.state !== 'running') c.resume().catch(() => {});
    if (!unlock.done) {
      unlock.done = true;
      const b = c.createBuffer(1, 1, 22050), s = c.createBufferSource();
      s.buffer = b; s.connect(c.destination); s.start(0);
    }
  }
  for (const ev of ['pointerdown', 'pointerup', 'touchend', 'click', 'keydown']) {
    document.addEventListener(ev, unlock, { capture: true, passive: true });
  }

  function start() {
    if (ready) return ready;
    ready = (async () => {
      const c = context();
      if (c.audioWorklet && window.AudioWorkletNode) {
        try {
          await c.audioWorklet.addModule('dj_engine_core.js');
          node = new AudioWorkletNode(c, 'dj-musi', { numberOfInputs: 0, outputChannelCount: [2] });
          node.port.onmessage = (e) => { lastState = e.data; };
          node.connect(c.destination);
          return;
        } catch (e) { console.warn('AudioWorklet failed, using fallback', e); }
      }
      // Fallback: mix on the page.
      mixer = new window.DjMixer(c.sampleRate);
      node = c.createScriptProcessor(2048, 0, 2);
      node.onaudioprocess = (e) => {
        mixer.process(e.outputBuffer.getChannelData(0), e.outputBuffer.getChannelData(1));
        lastState = mixer.state();
      };
      node.connect(c.destination);
    })();
    return ready;
  }

  function send(msg, transfer) {
    if (mixer) mixer.command(msg);
    else node.port.postMessage(msg, transfer || []);
  }

  function decode(arrayBuffer) {
    const c = context();
    return new Promise((resolve, reject) => {
      const p = c.decodeAudioData(arrayBuffer, resolve, (e) => reject(e || new Error('This file could not be decoded')));
      if (p && p.catch) p.catch(reject);
    });
  }

  /** AudioBuffer -> interleaved 16-bit stereo, like AudioDecoder.java. */
  function toPcm(buf) {
    const n = buf.length, l = buf.getChannelData(0), r = buf.numberOfChannels > 1 ? buf.getChannelData(1) : l;
    const pcm = new Int16Array(n * 2);
    for (let i = 0; i < n; i++) {
      let a = l[i], b = r[i];
      a = a > 1 ? 1 : a < -1 ? -1 : a; b = b > 1 ? 1 : b < -1 ? -1 : b;
      pcm[i * 2] = a * 32767; pcm[i * 2 + 1] = b * 32767;
    }
    return pcm;
  }

  // Same as DeckEngine.computePeaks.
  function computePeaks(data, frames, rate) {
    const win = Math.max(1, Math.floor(rate / PEAKS_PER_SECOND)), n = Math.floor(frames / win);
    const peaks = new Array(n), tones = new Array(n);
    for (let p = 0; p < n; p++) {
      let max = 0, energy = 1e-9, diff = 0;
      const start = p * win;
      let prev = data[start * 2] + data[start * 2 + 1];
      for (let f = start; f < start + win; f += 2) {
        const l = data[f * 2], r = data[f * 2 + 1];
        const v = Math.max(Math.abs(l), Math.abs(r));
        if (v > max) max = v;
        const m = l + r;
        energy += m * m; diff += (m - prev) * (m - prev); prev = m;
      }
      peaks[p] = Math.round(max / 32.768) / 1000;
      tones[p] = Math.round(Math.min(1, Math.sqrt(diff / energy / 4) * 1.6) * 1000) / 1000;
    }
    return { peaks, tones };
  }

  // Same as BeatDetector.java.
  function detectBeats(pcm, frames, rate) {
    const HOP_HZ = 200, hop = Math.floor(rate / HOP_HZ), hopHz = rate / hop;
    const startFrame = frames > rate * 150 ? rate * 30 : 0;
    const endFrame = Math.min(frames, startFrame + rate * 120);
    const n = Math.floor((endFrame - startFrame) / hop);
    if (n < HOP_HZ * 8) return { bpm: 0, firstBeatMs: 0 };
    const onset = new Float64Array(n);
    let prev = 0;
    for (let i = 0; i < n; i++) {
      let e = 0; const base = startFrame + i * hop;
      for (let f = base; f < base + hop; f += 2) { const m = (pcm[f * 2] + pcm[f * 2 + 1]) / 65536; e += m * m; }
      const loud = Math.log1p(e * 1000);
      onset[i] = Math.max(0, loud - prev); prev = loud;
    }
    const minLag = Math.floor(hopHz * 60 / 180), maxLag = Math.floor(hopHz * 60 / 70);
    const ac = new Float64Array(maxLag + 2);
    for (let lag = minLag - 1; lag <= maxLag + 1; lag++) {
      let s = 0; for (let i = lag; i < n; i++) s += onset[i] * onset[i - lag];
      ac[lag] = s / (n - lag);
    }
    let best = minLag, bestScore = -1;
    for (let lag = minLag; lag <= maxLag; lag++) {
      const bpm = hopHz * 60 / lag;
      const weight = Math.exp(-0.5 * Math.pow(Math.log(bpm / 120) / 0.35, 2));
      const twice = 2 * lag < ac.length ? ac[2 * lag] : 0;
      const score = (ac[lag] + 0.5 * twice) * (0.7 + 0.3 * weight);
      if (score > bestScore) { bestScore = score; best = lag; }
    }
    const y0 = ac[best - 1], y1 = ac[best], y2 = ac[best + 1], den = y0 - 2 * y1 + y2;
    const lag = best + (den !== 0 ? 0.5 * (y0 - y2) / den : 0);
    let bestScore2 = -1, bestLag = lag, phase = 0;
    for (let l = lag * 0.99; l <= lag * 1.01; l += lag * 0.0004) {
      for (let off = 0; off < l; off += 0.5) {
        let s = 0;
        for (let t = off; t < n - 1; t += l) { const i0 = t | 0, fr = t - i0; s += onset[i0] * (1 - fr) + onset[i0 + 1] * fr; }
        if (s > bestScore2) { bestScore2 = s; bestLag = l; phase = off; }
      }
    }
    const bpm = hopHz * 60 / bestLag;
    let firstBeatMs = (startFrame / rate) * 1000 + phase * 1000 / hopHz;
    firstBeatMs = firstBeatMs % (60000 / bpm);
    return { bpm: Math.round(bpm * 10) / 10, firstBeatMs };
  }

  async function loadDeck(deck, arrayBuffer) {
    await start();
    const buf = await decode(arrayBuffer);
    const rate = buf.sampleRate, frames = buf.length;
    const pcm = toPcm(buf);
    const { peaks, tones } = computePeaks(pcm, frames, rate);
    const beats = detectBeats(pcm, frames, rate);
    send({ cmd: 'play', deck, playing: false });
    send({ cmd: 'load', deck, pcm, frames, rate }, [pcm.buffer]);
    return {
      durationMs: Math.floor(frames * 1000 / rate), peaks, tones,
      peaksPerSecond: PEAKS_PER_SECOND, bpm: beats.bpm, firstBeatMs: beats.firstBeatMs,
    };
  }

  async function call(method, argsJson) {
    const a = argsJson ? JSON.parse(argsJson) : {};
    switch (method) {
      case 'state': return JSON.stringify(lastState);
      case 'loadLocal': {
        const f = files.get(a.id);
        if (!f) throw new Error('That song is no longer open. Pick it again from your device.');
        return JSON.stringify(await loadDeck(a.deck, await f.arrayBuffer()));
      }
      case 'sampleLoadUrl': {
        await start();
        const res = await fetch(a.url);
        if (!res.ok) throw new Error('Sound file missing: ' + a.url);
        const buf = await decode(await res.arrayBuffer());
        const pcm = toPcm(buf);
        send({ cmd: 'sampleLoad', slot: a.slot, pcm, frames: buf.length, rate: buf.sampleRate }, [pcm.buffer]);
        return 'null';
      }
      default:
        await start();
        send(Object.assign({ cmd: method }, a));
        return 'null';
    }
  }

  /** Opens the phone's file picker. Must run inside a tap. Resolves with
   *  JSON [{id, name}] (empty if nothing was picked). */
  function pickFiles(multiple) {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'audio/*,.mp3,.m4a,.aac,.wav,.ogg,.flac';
      input.multiple = !!multiple;
      input.style.display = 'none';
      document.body.appendChild(input);
      const done = () => {
        const out = [];
        for (const f of input.files || []) {
          const id = 'f' + (nextId++);
          files.set(id, f);
          out.push({ id, name: f.name, size: f.size });
        }
        input.remove();
        resolve(JSON.stringify(out));
      };
      input.addEventListener('change', done, { once: true });
      input.addEventListener('cancel', () => { input.remove(); resolve('[]'); }, { once: true });
      input.click();
    });
  }

  const urls = new Map();
  function urlFor(id) {
    if (!urls.has(id)) { const f = files.get(id); if (!f) return ''; urls.set(id, URL.createObjectURL(f)); }
    return urls.get(id);
  }

  window.djEngine = { call, pickFiles, urlFor };
})();
