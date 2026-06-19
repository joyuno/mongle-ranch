// gen-sfx.mjs — 몽글목장 효과음 절차 생성 (외부 에셋·다운로드·IP 없음).
//
// 순수 합성: 사인/삼각 톤 + ADSR 엔벨로프로 짧고 부드러운 코지 블립을 만든다.
// 출력: assets/sfx/{name}.wav (모노 22050Hz 16-bit PCM). 결과는 사람 검수 후 커밋.
//
//   node scripts/gen-sfx.mjs

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '..', 'assets', 'sfx');
const SR = 22050;

// note name → 주파수 (A4=440)
const NOTE = (n) => 440 * Math.pow(2, (n - 69) / 12);
const C5 = 72, E5 = 76, G5 = 79, C6 = 84, A4 = 69, E4 = 64, G4 = 67;

// 한 톤 합성: freq, dur(초), wave('sine'|'tri'), 엔벨로프(attack/decay/sustain/release 비율)
function tone(freq, dur, wave = 'sine', env = { a: 0.01, d: 0.08, s: 0.4, r: 0.2 }, vol = 0.5) {
  const n = Math.floor(SR * dur);
  const out = new Float32Array(n);
  const aN = env.a * n, dN = env.d * n, rN = env.r * n;
  const sStart = aN + dN, sEnd = n - rN;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    let s;
    const ph = (freq * t) % 1;
    if (wave === 'tri') s = 4 * Math.abs(ph - 0.5) - 1;
    else s = Math.sin(2 * Math.PI * freq * t);
    // ADSR
    let e;
    if (i < aN) e = i / aN;
    else if (i < sStart) e = 1 - (1 - env.s) * ((i - aN) / Math.max(1, dN));
    else if (i < sEnd) e = env.s;
    else e = env.s * (1 - (i - sEnd) / Math.max(1, rN));
    out[i] = s * e * vol;
  }
  return out;
}

// 여러 톤을 시간순으로 이어붙이거나(seq) 겹쳐서(mix) 합성
function seq(parts) {
  // parts: [{at(초), buf}]
  const end = Math.max(...parts.map((p) => p.at * SR + p.buf.length));
  const out = new Float32Array(Math.ceil(end));
  for (const { at, buf } of parts) {
    const off = Math.floor(at * SR);
    for (let i = 0; i < buf.length; i++) out[off + i] += buf[i];
  }
  // soft clip
  for (let i = 0; i < out.length; i++) out[i] = Math.tanh(out[i] * 1.1);
  return out;
}

// 짧은 화이트노이즈 + 감쇠 (swish/whoosh용)
function noise(dur, env = { a: 0.05, d: 0.1, s: 0.3, r: 0.5 }, vol = 0.3) {
  const n = Math.floor(SR * dur);
  const out = new Float32Array(n);
  let last = 0;
  for (let i = 0; i < n; i++) {
    // 1극 lowpass로 부드럽게
    last = last * 0.86 + (Math.random() * 2 - 1) * 0.14;
    const p = i / n;
    const e = p < env.a ? p / env.a : (1 - (p - env.a) / (1 - env.a));
    out[i] = last * Math.max(0, e) * vol;
  }
  return out;
}

function toWav(samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28);
  buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.round(v * 32000), 44 + i * 2);
  }
  return buf;
}

const SOUNDS = {
  // UI 클릭 — 짧고 또렷한 삼각파 톡
  click: () => tone(NOTE(C6), 0.07, 'tri', { a: 0.005, d: 0.04, s: 0.2, r: 0.4 }, 0.35),
  // 정답 — 밝은 두 음 상승
  ding: () => seq([
    { at: 0, buf: tone(NOTE(E5), 0.12, 'sine', { a: 0.01, d: 0.1, s: 0.5, r: 0.3 }, 0.4) },
    { at: 0.08, buf: tone(NOTE(G5), 0.16, 'sine', { a: 0.01, d: 0.1, s: 0.5, r: 0.4 }, 0.4) },
  ]),
  // 오답 — 부드러운 저음(처벌 톤 금지)
  boop: () => seq([
    { at: 0, buf: tone(NOTE(E4), 0.12, 'sine', { a: 0.01, d: 0.1, s: 0.5, r: 0.4 }, 0.35) },
    { at: 0.09, buf: tone(NOTE(E4 - 2), 0.16, 'sine', { a: 0.01, d: 0.1, s: 0.4, r: 0.5 }, 0.3) },
  ]),
  // 코인 — 두 번 반짝 (cha-ching)
  coin: () => seq([
    { at: 0, buf: tone(NOTE(C6), 0.06, 'tri', { a: 0.005, d: 0.05, s: 0.3, r: 0.4 }, 0.3) },
    { at: 0.05, buf: tone(NOTE(C6 + 4), 0.12, 'tri', { a: 0.005, d: 0.05, s: 0.4, r: 0.5 }, 0.32) },
  ]),
  // 간식/등장 — 빠른 상승 팝
  pop: () => seq([
    { at: 0, buf: tone(NOTE(G5), 0.05, 'sine', { a: 0.005, d: 0.03, s: 0.3, r: 0.5 }, 0.34) },
    { at: 0.03, buf: tone(NOTE(C6), 0.1, 'sine', { a: 0.005, d: 0.04, s: 0.3, r: 0.6 }, 0.34) },
  ]),
  // 레벨업/스트릭 — 4음 차임
  chime: () => seq([
    { at: 0.0, buf: tone(NOTE(C5), 0.14, 'sine', {}, 0.34) },
    { at: 0.09, buf: tone(NOTE(E5), 0.14, 'sine', {}, 0.34) },
    { at: 0.18, buf: tone(NOTE(G5), 0.18, 'sine', {}, 0.34) },
    { at: 0.27, buf: tone(NOTE(C6), 0.22, 'sine', { a: 0.01, d: 0.1, s: 0.5, r: 0.5 }, 0.36) },
  ]),
  // 가챠 스핀 — 상승 휘파람
  whoosh: () => noise(0.5, { a: 0.4, d: 0.1, s: 0.3, r: 0.6 }, 0.22),
  // 화면 전환 — 짧은 스위시
  swish: () => noise(0.22, { a: 0.3, d: 0.1, s: 0.2, r: 0.7 }, 0.16),
  // 레전더리 — 풍성한 팡파르(겹친 화음 + 상승)
  fanfare: () => seq([
    { at: 0.0, buf: tone(NOTE(C5), 0.5, 'sine', { a: 0.01, d: 0.2, s: 0.5, r: 0.4 }, 0.26) },
    { at: 0.0, buf: tone(NOTE(E5), 0.5, 'sine', { a: 0.01, d: 0.2, s: 0.5, r: 0.4 }, 0.24) },
    { at: 0.0, buf: tone(NOTE(G5), 0.5, 'sine', { a: 0.01, d: 0.2, s: 0.5, r: 0.4 }, 0.22) },
    { at: 0.2, buf: tone(NOTE(C6), 0.45, 'sine', { a: 0.01, d: 0.15, s: 0.6, r: 0.5 }, 0.3) },
    { at: 0.3, buf: tone(NOTE(E5 + 12), 0.4, 'tri', { a: 0.01, d: 0.15, s: 0.5, r: 0.6 }, 0.2) },
  ]),
};

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  for (const [name, gen] of Object.entries(SOUNDS)) {
    const wav = toWav(gen());
    const file = join(OUT_DIR, `${name}.wav`);
    await writeFile(file, wav);
    console.log(`✓ ${name}.wav  ${(wav.length / 1024).toFixed(1)} KB`);
  }
  console.log(`\nDone: ${Object.keys(SOUNDS).length} sfx.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
