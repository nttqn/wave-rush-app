// Synthesizes sfx_portal.wav (the speed/mini portal whoosh) from scratch.
// Every other sound in assets/audio/ is a file supplied by the project owner
// (music m_*.mp3, sfx_explosive/menu_confirm/menu_back.wav).
// Re-run with `node tool/gen_audio.js` after tweaking.
const fs = require('fs');
const path = require('path');

const SR = 22050;
const OUT = path.join(__dirname, '..', 'assets', 'audio');

function osc(type, phase) {
  const p = phase - Math.floor(phase);
  return type === 'sine' ? Math.sin(2 * Math.PI * p) : 1 - 4 * Math.abs(p - 0.5); // 'tri'
}

// Exponential pitch sweep with a linear release tail.
function sweep(buf, t, dur, freq, freqEnd, type, vol, release) {
  const start = Math.floor(t * SR);
  let phase = 0;
  for (let i = 0; i < Math.floor((dur + release) * SR) && start + i < buf.length; i++) {
    const tt = i / SR;
    phase += (freq * Math.pow(freqEnd / freq, Math.min(1, tt / dur))) / SR;
    const env = tt < 0.005 ? tt / 0.005 : tt < dur ? 1 : Math.max(0, 1 - (tt - dur) / release);
    buf[start + i] += osc(type, phase) * env * vol;
  }
}

function writeWav(name, buf, peak) {
  let max = 0;
  for (const v of buf) max = Math.max(max, Math.abs(v));
  const gain = max > 0 ? peak / max : 1;
  const data = Buffer.alloc(buf.length * 2);
  for (let i = 0; i < buf.length; i++) {
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i] * gain)) * 32767), i * 2);
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

const b = new Float32Array(Math.round(0.4 * SR));
sweep(b, 0, 0.3, 300, 1400, 'sine', 0.5, 0.08);
sweep(b, 0.02, 0.28, 600, 2400, 'tri', 0.25, 0.08);
writeWav('sfx_portal.wav', b, 0.6);
