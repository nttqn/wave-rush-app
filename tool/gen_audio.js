// Synthesizes Wave Rush's own music loops and sound effects from scratch:
// no samples, no third-party audio, nothing shared with other apps.
// Re-run with `node tool/gen_audio.js` after tweaking.
//
// Output (assets/audio/):
//   music_1..4.wav   seamless 16-bar in-game loops, each a different tempo,
//                    key, chord loop, drum groove and lead motif
//   sfx_crash.wav    crash   sfx_click.wav  button
//   sfx_back.wav     back    sfx_win.wav    level-clear jingle
//   sfx_portal.wav   portal whoosh
// (m_title.mp3, the menu loop, is the owner's file and unique to this app.)
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
    case 'pulse': return p < 0.25 ? 1 : -1;
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
    const env = tt < attack ? tt / attack : tt < dur ? 1 : Math.max(0, 1 - (tt - dur) / release);
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
    const y = hp > 0 ? hp * (prevOut + x - prev) : x; // one-pole high-pass
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

const kick = (buf, t, vol = 0.9) => note(buf, t, 0.12, 150, { type: 'sine', vol, attack: 0.001, release: 0.08, freqEnd: 42 });

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
  h.write('WAVEfmt ', 8);
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); // PCM
  h.writeUInt16LE(1, 22); // mono
  h.writeUInt32LE(SR, 24);
  h.writeUInt32LE(SR * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write('data', 36);
  h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([h, data]));
  console.log(name, (data.length / 1024).toFixed(0) + 'KB');
}

// Drum grooves: which 16th steps get kick / clap / hat in one bar.
const GROOVES = {
  four: { kick: [0, 4, 8, 12], clap: [4, 12], hat: [2, 6, 10, 14] },
  broken: { kick: [0, 6, 10], clap: [4, 12], hat: [2, 3, 6, 7, 10, 11, 14, 15] },
  drive: { kick: [0, 3, 8, 11], clap: [4, 12], hat: [0, 2, 4, 6, 8, 10, 12, 14] },
  half: { kick: [0, 10], clap: [8], hat: [2, 6, 10, 14] },
};

// chords are [semitone offset from key, 'm' | 'M']
function track(name, { bpm, key, chords, seed, groove, arp, bars = 16 }) {
  const r = rng(seed);
  const step = 60 / bpm / 4; // one 16th
  const barLen = step * 16;
  const buf = new Float32Array(Math.round(bars * barLen * SR));
  const scale = [0, 2, 3, 5, 7, 8, 10];
  const g = GROOVES[groove];

  // Two-bar lead motif (8th-note steps; -1 = rest), varied every 4 bars.
  const motif = [];
  for (let i = 0; i < 16; i++) motif.push(r() < 0.3 ? -1 : Math.floor(r() * 7));

  for (let bar = 0; bar < bars; bar++) {
    const t0 = bar * barLen;
    const [off, qual] = chords[bar % chords.length];
    const root = key + off;
    const third = qual === 'm' ? 3 : 4;
    const tones = [0, third, 7, 12];
    const intro = bar < 2;
    const fill = bar % 4 === 3;

    for (let s = 0; s < 16; s++) {
      const t = t0 + s * step;
      if (g.kick.includes(s)) kick(buf, t);
      if (!intro && g.clap.includes(s)) noise(buf, t, 0.18, { vol: 0.33, decay: 18, hp: 0.6, rand: r });
      if (g.hat.includes(s)) noise(buf, t, 0.05, { vol: intro ? 0.08 : 0.12, decay: 55, hp: 0.92, rand: r });
      // snare roll into each 4th bar
      if (!intro && fill && s >= 12) noise(buf, t + step / 2, 0.06, { vol: 0.18, decay: 40, hp: 0.7, rand: r });
      // bass on the off-16ths
      if (s % 4 === 2 || (groove === 'drive' && s % 2 === 1)) {
        note(buf, t, step * 0.8, midi(root - 24 + (s === 14 ? 12 : 0)), { type: 'saw', vol: 0.2, release: 0.03 });
      }
      // arpeggio
      const tone = tones[arp[s % arp.length]];
      note(buf, t, step * 0.6, midi(root + 12 + tone), { type: 'pulse', vol: intro ? 0.03 : 0.045, release: 0.04 });
    }

    if (bar >= 4) {
      for (let s = 0; s < 8; s++) {
        const m = motif[(bar % 2) * 8 + s];
        if (m < 0) continue;
        const deg = scale[(m + (bar % 8 >= 4 ? 2 : 0)) % 7];
        note(buf, t0 + s * step * 2, step * 1.6, midi(key + 24 + deg), { type: 'tri', vol: 0.15, release: 0.08 });
      }
    }
    for (const tone of [0, third, 7]) {
      note(buf, t0, barLen * 0.95, midi(root + tone), { type: 'saw', vol: 0.028, attack: 0.25, release: 0.2 });
    }
  }
  writeWav(name, buf);
}

track('music_1.wav', { bpm: 128, key: 57, chords: [[0, 'm'], [-4, 'M'], [3, 'M'], [-2, 'M']], seed: 101, groove: 'four', arp: [0, 1, 2, 3, 2, 1, 2, 3] });
track('music_2.wav', { bpm: 140, key: 52, chords: [[0, 'm'], [5, 'm'], [-4, 'M'], [-5, 'M']], seed: 202, groove: 'broken', arp: [0, 2, 1, 3, 0, 2, 3, 2] });
track('music_3.wav', { bpm: 150, key: 49, chords: [[0, 'm'], [-2, 'M'], [-4, 'M'], [-2, 'M']], seed: 303, groove: 'drive', arp: [3, 2, 1, 0, 1, 2, 3, 2] });
track('music_4.wav', { bpm: 118, key: 55, chords: [[0, 'm'], [3, 'M'], [8, 'M'], [7, 'M']], seed: 404, groove: 'half', arp: [0, 1, 2, 1, 3, 2, 1, 2] });

// ---- SFX (one-shots, no wrap)
{
  const b = new Float32Array(Math.round(0.7 * SR));
  noise(b, 0, 0.6, { vol: 0.8, decay: 7, wrap: false });
  note(b, 0, 0.35, 180, { type: 'square', vol: 0.4, freqEnd: 40, release: 0.2, wrap: false });
  writeWav('sfx_crash.wav', b);
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
{
  const b = new Float32Array(Math.round(0.12 * SR));
  note(b, 0, 0.05, 990, { type: 'square', vol: 0.3, freqEnd: 520, release: 0.04, wrap: false });
  writeWav('sfx_back.wav', b, 0.5);
}
