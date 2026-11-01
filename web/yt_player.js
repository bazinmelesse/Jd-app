// YouTube's official embedded player for the web version of DJ Musi.
// Each player lives in its own box on top of the app, so it keeps playing
// when the full-screen player is minimized. The app shows an empty
// placeholder where the video belongs, and this script keeps the box lined
// up with it (or shrinks it away when no placeholder is on screen).
(function () {
  let apiReady = null;
  function loadApi() {
    if (!apiReady) {
      apiReady = new Promise((resolve, reject) => {
        if (window.YT && window.YT.Player) { resolve(); return; }
        const prev = window.onYouTubeIframeAPIReady;
        window.onYouTubeIframeAPIReady = () => { if (prev) prev(); resolve(); };
        const s = document.createElement('script');
        s.src = 'https://www.youtube.com/iframe_api';
        s.onerror = () => { apiReady = null; reject(new Error('Could not reach YouTube')); };
        document.head.appendChild(s);
      });
    }
    return apiReady;
  }

  const players = new Map(); // id -> {host, player, ready, onEvent, placeholder}

  function hide(host) {
    host.style.cssText = 'position:fixed;left:0;top:0;width:2px;height:2px;opacity:0;pointer-events:none;z-index:-1;overflow:hidden';
  }

  // Keep each player's box on top of its placeholder.
  function follow() {
    for (const p of players.values()) {
      const ph = p.placeholder;
      const r = ph && ph.isConnected ? ph.getBoundingClientRect() : null;
      if (r && r.width > 4 && r.height > 4) {
        const s = p.host.style;
        s.cssText = 'position:fixed;overflow:hidden;z-index:5;pointer-events:auto;opacity:1';
        s.left = r.left + 'px'; s.top = r.top + 'px';
        s.width = r.width + 'px'; s.height = r.height + 'px';
      } else if (p.host.style.opacity !== '0') {
        hide(p.host);
      }
    }
    requestAnimationFrame(follow);
  }
  requestAnimationFrame(follow);

  function create(id, videoId, onEvent) {
    const host = document.createElement('div');
    hide(host);
    const inner = document.createElement('div');
    inner.style.cssText = 'width:100%;height:100%';
    host.appendChild(inner);
    document.body.appendChild(host);
    const p = { host, player: null, ready: false, onEvent, placeholder: null, volume: 100 };
    players.set(id, p);
    loadApi().then(() => {
      if (!players.has(id)) return;
      p.player = new YT.Player(inner, {
        width: '100%', height: '100%', videoId,
        playerVars: { playsinline: 1, rel: 0, modestbranding: 1, autoplay: 1, controls: 1 },
        events: {
          onReady: () => {
            p.ready = true;
            const f = p.player.getIframe(); f.style.width = '100%'; f.style.height = '100%';
            p.player.setVolume(p.volume);
            onEvent(JSON.stringify({ type: 'ready', durationMs: Math.round(p.player.getDuration() * 1000) }));
            p.player.playVideo();
          },
          onStateChange: (e) => {
            onEvent(JSON.stringify({ type: 'state', state: e.data }));
          },
          onError: (e) => {
            const why = { 2: 'This video link is invalid', 5: 'This video can\'t play in a browser',
              100: 'This video was removed or is private', 101: 'The owner doesn\'t allow this video outside YouTube',
              150: 'The owner doesn\'t allow this video outside YouTube' }[e.data] || ('YouTube error ' + e.data);
            onEvent(JSON.stringify({ type: 'error', message: why }));
          },
        },
      });
    }, (err) => onEvent(JSON.stringify({ type: 'error', message: err.message })));
  }

  function withPlayer(id, fn) {
    const p = players.get(id);
    if (p && p.ready) { try { return fn(p.player, p); } catch (_) {} }
    return undefined;
  }

  window.ytBridge = {
    create,
    dispose(id) {
      const p = players.get(id);
      if (!p) return;
      players.delete(id);
      try { p.player && p.player.destroy(); } catch (_) {}
      p.host.remove();
    },
    play(id) { withPlayer(id, (pl) => pl.playVideo()); },
    pause(id) { withPlayer(id, (pl) => pl.pauseVideo()); },
    seek(id, ms) { withPlayer(id, (pl) => pl.seekTo(ms / 1000, true)); },
    setVolume(id, v) {
      const p = players.get(id); if (!p) return;
      p.volume = Math.round(v * 100);
      withPlayer(id, (pl) => { pl.setVolume(p.volume); if (p.volume > 0) pl.unMute(); });
    },
    setSpeed(id, s) { withPlayer(id, (pl) => pl.setPlaybackRate(s)); },
    positionMs(id) { return withPlayer(id, (pl) => Math.round(pl.getCurrentTime() * 1000)) || 0; },
    attach(id, placeholder) { const p = players.get(id); if (p) p.placeholder = placeholder; },
  };
})();
