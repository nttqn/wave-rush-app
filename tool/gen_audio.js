// Synthesizes every sound in assets/audio/ from scratch — no samples, no
// third-party audio. Re-run with `node tool/gen_audio.js` after tweaking.
//
// Music: three seamless electronic loops (kick/clap/hats/bass/arp/lead),
// each at a different tempo and key. SFX: crash, portal, win, click.
const fs = require('fs');
const path = require('path');

const SR = 22050;
const OUT = path.join(__dirname, '..', 'assets', 'audio');
fs.mkdirSync(OUT, { recursive: true });

function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);

function osc(type, phase) {
  const p = phase - Math.floor(phase);
  switch (type) {
    case 'sine': return Math.sin(2 * Math.PI * p);
    case 'square': return p < 0.5 ? 1 : -1;
    case 'saw': return 2 * p - 1;
    case 'tri': return 1 - 4 * Math.abs(p - 0.5);
  }
  return 0;
}

// Adds a note into buf (wrapping past the end so loops are seamless).
function note(buf, t, dur, freq, { type = 'square', vol = 0.2, attack = 0.005, release = 0.05, freqEnd = null, wrap = true } = {}) {
  const n = Math.floor((dur + release) * SR);
  const start = Math.floor(t * SR);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const tt = i / SR;
    const f = freqEnd == null ? freq : freq * Math.pow(freqEnd / freq, Math.min(1, tt / dur));
    phase += f / SR;
    let env = tt < attack ? tt / attack : tt < dur ? 1 : Math.max(0, 1 - (tt - dur) / release);
    let idx = start + i;
    if (idx >= buf.length) {
      if (!wrap) break;
      idx %= buf.length;
    }
    buf[idx] += osc(type, phase) * env * vol;
  }
}

function noise(buf, t, dur, { vol = 0.2, decay = 20, hp = 0, rand = Math.random, wrap = true } = {}) {
  const n = Math.floor(dur * SR);
  const start = Math.floor(t * SR);
  let prev = 0, prevOut = 0;
  for (let i = 0; i < n; i++) {
    const x = rand() * 2 - 1;
    // one-pole high-pass for hats/claps
    const y = hp > 0 ? hp * (prevOut + x - prev) : x;
    prev = x;
    prevOut = y;
    let idx = start + i;
    if (idx >= buf.length) {
      if (!wrap) break;
      idx %= buf.length;
    }
    buf[idx] += y * vol * Math.exp((-i / SR) * decay);
  }
}

function kick(buf, t) {
  note(buf, t, 0.12, 150, { type: 'sine', vol: 0.9, attack: 0.001, release: 0.08, freqEnd: 42 });
}

function writeWav(name, buf, peak = 0.89) {
  let max = 0;
  for (const v of buf) max = Math.max(max, Math.abs(v));
  const gain = max > 0 ? peak / max : 1;
  const data = Buffer.alloc(buf.length * 2);
  for (let i = 0; i < buf.length; i++) {
    const s = Math.max(-1, Math.min(1, Math.tanh(buf[i] * gain * 1.1)));
    data.writeInt16LE(Math.round(s * 32767), i * 2);
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0);
  h.writeUInt32LE(36 + data.length, 4);
  h.write('WAVE', 8);
  h.write('fmt ', 12);
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(SR, 24);
  h.writeUInt32LE(SR * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([h, data]));
  console.log(name, (data.length / 1024).toFixed(0) + 'KB');
}

// chords are [root semitone offset from key, 'm' | 'M']
function track(name, { bpm, key, chords, seed, bars = 16 }) {
  const r = rng(seed);
  const beat = 60 / bpm;
  const barLen = beat * 4;
  const buf = new Float32Array(Math.round(bars * barLen * SR));
  const scale = [0, 2, 3, 5, 7, 8, 10];

  // A 2-bar lead motif (8th-note steps; -1 = rest), repeated with variation.
  const motif = [];
  for (let i = 0; i < 16; i++) motif.push(r() < 0.3 ? -1 : Math.floor(r() * 7));

  for (let bar = 0; bar < bars; bar++) {
    const t0 = bar * barLen;
    const [off, qual] = chords[bar % chords.length];
    const root = key + off;
    const third = qual === 'm' ? 3 : 4;
    const tones = [0, third, 7, 12];
    const intro = bar < 2;

    for (let b = 0; b < 4; b++) {
      const tb = t0 + b * beat;
      kick(buf, tb);
      if (!intro && (b === 1 || b === 3)) noise(buf, tb, 0.18, { vol: 0.35, decay: 18, hp: 0.6, rand: r });
      // offbeat open hat + 16th closed hats
      noise(buf, tb + beat / 2, 0.08, { vol: 0.16, decay: 35, hp: 0.9, rand: r });
      if (!intro) {
        noise(buf, tb + beat / 4, 0.03, { vol: 0.07, decay: 90, hp: 0.95, rand: r });
        noise(buf, tb + (3 * beat) / 4, 0.03, { vol: 0.07, decay: 90, hp: 0.95, rand: r });
      }
      // rolling offbeat bass
      for (const s of [0.5, 0.75]) {
        note(buf, tb + s * beat, beat * 0.2, midi(root - 24 + (s === 0.75 && b === 3 ? 12 : 0)), { type: 'saw', vol: 0.22, release: 0.03 });
      }
    }

    // 16th-note arpeggio
    for (let s = 0; s < 16; s++) {
      const tone = tones[[0, 1, 2, 3, 2, 1, 2, 3][s % 8]];
      note(buf, t0 + (s * beat) / 4, beat / 4 * 0.6, midi(root + 12 + tone), { type: 'square', vol: intro ? 0.035 : 0.05, release: 0.04 });
    }

    // lead (from bar 4 on), plus a soft pad under everything
    if (bar >= 4) {
      for (let s = 0; s < 8; s++) {
        const step = motif[(bar % 2) * 8 + s];
        if (step < 0) continue;
        const deg = scale[(step + (bar % 8 >= 4 ? 2 : 0)) % 7];
        note(buf, t0 + (s * beat) / 2, beat / 2 * 0.8, midi(key + 24 + deg), { type: 'tri', vol: 0.16, release: 0.08 });
      }
    }
    for (const tone of [0, third, 7]) {
      note(buf, t0, barLen * 0.95, midi(root + tone), { type: 'saw', vol: 0.03, attack: 0.2, release: 0.2 });
    }
  }
  writeWav(name, buf);
}

// A minor 128, E minor 140, C# minor 150 — all loops are exactly 16 bars.
track('music_0.wav', { bpm: 128, key: 57, chords: [[0, 'm'], [-4, 'M'], [3, 'M'], [-2, 'M']], seed: 11 });
track('music_1.wav', { bpm: 140, key: 52, chords: [[0, 'm'], [5, 'm'], [-4, 'M'], [-5, 'M']], seed: 22 });
track('music_2.wav', { bpm: 150, key: 49, chords: [[0, 'm'], [-2, 'M'], [-4, 'M'], [-2, 'M']], seed: 33 });

// ---- SFX (no wrap: one-shots)
{
  const b = new Float32Array(Math.round(0.7 * SR));
  noise(b, 0, 0.6, { vol: 0.8, decay: 7, wrap: false });
  note(b, 0, 0.35, 180, { type: 'square', vol: 0.4, freqEnd: 40, release: 0.2, wrap: false });
  writeWav('sfx_death.wav', b);
}
{
  const b = new Float32Array(Math.round(0.4 * SR));
  note(b, 0, 0.3, 300, { type: 'sine', vol: 0.5, freqEnd: 1400, release: 0.08, wrap: false });
  note(b, 0.02, 0.28, 600, { type: 'tri', vol: 0.25, freqEnd: 2400, release: 0.08, wrap: false });
  writeWav('sfx_portal.wav', b, 0.6);
}
{
  const b = new Float32Array(Math.round(1.2 * SR));
  [72, 76, 79, 84].forEach((m, i) => note(b, i * 0.11, 0.18, midi(m), { type: 'square', vol: 0.25, release: 0.1, wrap: false }));
  [84, 88, 91].forEach((m) => note(b, 0.46, 0.5, midi(m), { type: 'tri', vol: 0.25, release: 0.25, wrap: false }));
  writeWav('sfx_win.wav', b, 0.7);
}
{
  const b = new Float32Array(Math.round(0.1 * SR));
  note(b, 0, 0.04, 880, { type: 'square', vol: 0.3, freqEnd: 1320, release: 0.03, wrap: false });
  writeWav('sfx_click.wav', b, 0.5);
}
