// gen-decor.mjs — 몽글목장 배경 장식 소품 생성기 (절차적 SVG → PNG).
//
// gen-placeholders.mjs와 동일 파이프라인(sharp/librsvg, 외부 API·IP 없음).
// 출력: assets/decor/{id}.png — 투명 배경. 목장 배경 5레이어(docs/DESIGN_SPEC §C)의
// 소품·언덕 레이어를 채운다. 캐릭터 팔레트와 같은 파스텔로 통일.
//
//   node scripts/gen-decor.mjs            # 전부
//   node scripts/gen-decor.mjs tree pond  # 일부

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '..', 'assets', 'decor');
const INK = '#3B3129';

function svg(w, h, inner, defs = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">` +
    `<defs>${defs}</defs><g stroke-linejoin="round" stroke-linecap="round">${inner}</g></svg>`;
}

// 둥근 언덕 실루엣 (가로로 긴 캡슐형). 대기원근: far는 밝고 저채도.
function hill(fill, ol) {
  const w = 1280, h = 320;
  return svg(w, h,
    `<path d="M 0 ${h} L 0 200 Q ${w * 0.25} 60 ${w * 0.5} 150 Q ${w * 0.75} 240 ${w} 120 L ${w} ${h} Z" ` +
    `fill="${fill}" stroke="${ol}" stroke-width="0"/>`);
}
const hill_far = () => hill('#C7DCAF', '#C7DCAF');
const hill_near = () => hill('#8DB56C', '#7AA259');

// 소품 발밑 반투명 타원 그림자 — 접지감(scale illusion) 부여.
const groundShadow = (cx, cy, rx, ry = 0) =>
  `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry || rx * 0.26}" fill="#3B3129" opacity="0.13"/>`;

// 둥근 캐노피 나무
function tree() {
  return svg(220, 280,
    groundShadow(110, 268, 58, 13) +
    `<rect x="98" y="180" width="24" height="86" rx="10" fill="#B68A5E" stroke="${INK}" stroke-width="6"/>` +
    `<ellipse cx="110" cy="118" rx="98" ry="86" fill="#9FD08C" stroke="${INK}" stroke-width="7"/>` +
    `<ellipse cx="74" cy="150" rx="50" ry="44" fill="#AED99A" stroke="${INK}" stroke-width="6"/>` +
    `<ellipse cx="150" cy="146" rx="54" ry="48" fill="#92C57E" stroke="${INK}" stroke-width="6"/>` +
    // 하이라이트 잎 점
    `<circle cx="86" cy="92" r="9" fill="#C8E6B0" opacity="0.8"/>` +
    `<circle cx="138" cy="104" r="7" fill="#C8E6B0" opacity="0.7"/>`);
}

// 울타리 한 칸 (가로바 2 + 기둥 2)
function fence() {
  const post = '#D8B98C', ol = '#9A7B54';
  return svg(240, 140,
    groundShadow(120, 130, 96, 9) +
    `<rect x="28" y="36" width="20" height="92" rx="8" fill="${post}" stroke="${ol}" stroke-width="6"/>` +
    `<rect x="192" y="36" width="20" height="92" rx="8" fill="${post}" stroke="${ol}" stroke-width="6"/>` +
    `<rect x="16" y="54" width="208" height="18" rx="8" fill="${post}" stroke="${ol}" stroke-width="6"/>` +
    `<rect x="16" y="92" width="208" height="18" rx="8" fill="${post}" stroke="${ol}" stroke-width="6"/>` +
    `<path d="M 28 36 L 38 22 L 48 36 Z" fill="${post}" stroke="${ol}" stroke-width="5"/>` +
    `<path d="M 192 36 L 202 22 L 212 36 Z" fill="${post}" stroke="${ol}" stroke-width="5"/>`);
}

// 연못 (타원 + 밝은 림 + 물결 하이라이트)
function pond() {
  return svg(280, 180,
    `<ellipse cx="140" cy="100" rx="128" ry="74" fill="#AEC6CF" stroke="#7FA8B8" stroke-width="7"/>` +
    `<ellipse cx="140" cy="92" rx="110" ry="58" fill="#C3DCE6"/>` +
    `<path d="M 74 86 Q 96 76 120 86" fill="none" stroke="#FFFFFF" stroke-width="5" opacity="0.7"/>` +
    `<path d="M 150 110 Q 176 100 202 110" fill="none" stroke="#FFFFFF" stroke-width="5" opacity="0.6"/>`);
}

// 5장 꽃잎 꽃 (파스텔 3색 변형)
function flower(petal, center) {
  const ol = '#B97E8C';
  let p = '';
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 - Math.PI / 2;
    const cx = 48 + Math.cos(a) * 26, cy = 48 + Math.sin(a) * 26;
    p += `<ellipse cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" rx="17" ry="22" fill="${petal}" stroke="${ol}" stroke-width="4" transform="rotate(${(a * 180 / Math.PI + 90).toFixed(1)} ${cx.toFixed(1)} ${cy.toFixed(1)})"/>`;
  }
  return svg(96, 96, p + `<circle cx="48" cy="48" r="15" fill="${center}" stroke="${ol}" stroke-width="4"/>`);
}
const flower_pink = () => flower('#F6BCCB', '#FBE7A2');
const flower_purple = () => flower('#DCC8F2', '#FBE7A2');
const flower_blue = () => flower('#BBD9F0', '#FBE7A2');

// 둥근 자갈
function rock() {
  return svg(120, 90,
    groundShadow(60, 82, 50, 8) +
    `<path d="M 12 70 Q 6 36 44 28 Q 92 18 108 50 Q 116 76 84 80 Q 40 86 12 70 Z" ` +
    `fill="#CFC6BC" stroke="#9A8E80" stroke-width="6"/>` +
    `<ellipse cx="50" cy="44" rx="22" ry="10" fill="#E2DBD2" opacity="0.7"/>`);
}

// 그루터기 (향후 꾸미기 상품 자리)
function stump() {
  return svg(140, 120,
    groundShadow(70, 110, 56, 10) +
    `<ellipse cx="70" cy="96" rx="56" ry="20" fill="#B68A5E" stroke="${INK}" stroke-width="6"/>` +
    `<rect x="20" y="48" width="100" height="52" fill="#C49A6C" stroke="${INK}" stroke-width="6"/>` +
    `<ellipse cx="70" cy="48" rx="50" ry="18" fill="#D8B98C" stroke="${INK}" stroke-width="6"/>` +
    `<ellipse cx="70" cy="48" rx="30" ry="10" fill="none" stroke="#9A7B54" stroke-width="4"/>` +
    `<ellipse cx="70" cy="48" rx="14" ry="5" fill="none" stroke="#9A7B54" stroke-width="3"/>`);
}

// 작은 풀숲 (전경 띠 단위)
function grasstuft() {
  return svg(120, 80,
    `<path d="M 16 78 Q 12 36 24 20 Q 30 40 34 78 Z" fill="#8FBF72" stroke="#6FA055" stroke-width="5"/>` +
    `<path d="M 44 78 Q 40 28 56 12 Q 60 40 62 78 Z" fill="#9FD08C" stroke="#6FA055" stroke-width="5"/>` +
    `<path d="M 78 78 Q 76 36 92 22 Q 96 44 98 78 Z" fill="#8FBF72" stroke="#6FA055" stroke-width="5"/>`);
}

// 가챠 캡슐머신 (가챠 화면 빈 무대용). 둥근 유리돔 + 파스텔 캡슐 + 다이얼.
function gachaMachine() {
  const ol = '#7A6A58', body = '#EBD9C0', glass = '#E8F0F4';
  const caps = [
    ['#E6A9AE', 150, 150], ['#A7CBB6', 210, 130], ['#C9B6E4', 270, 158],
    ['#EBC98C', 175, 205], ['#9DBFD8', 245, 200], ['#E6A9AE', 300, 205],
  ];
  let capsvg = '';
  for (const [c, x, y] of caps) {
    capsvg += `<circle cx="${x}" cy="${y}" r="26" fill="${c}" stroke="${ol}" stroke-width="3" opacity="0.92"/>` +
      `<path d="M ${x - 26} ${y} a 26 26 0 0 1 52 0 Z" fill="#FFFFFF" opacity="0.18"/>`;
  }
  return svg(440, 480,
    groundShadow(220, 452, 150, 22) +
    // 받침/몸체
    `<rect x="96" y="250" width="248" height="180" rx="34" fill="${body}" stroke="${ol}" stroke-width="9"/>` +
    // 배출구
    `<rect x="170" y="356" width="100" height="50" rx="14" fill="#D8C3A6" stroke="${ol}" stroke-width="7"/>` +
    // 다이얼
    `<circle cx="300" cy="318" r="22" fill="#D8C3A6" stroke="${ol}" stroke-width="7"/>` +
    `<rect x="296" y="300" width="8" height="36" rx="4" fill="${ol}"/>` +
    // 유리돔
    `<circle cx="220" cy="180" r="135" fill="${glass}" stroke="${ol}" stroke-width="9"/>` +
    capsvg +
    // 돔 하이라이트
    `<path d="M 130 120 q 40 -70 150 -60" fill="none" stroke="#FFFFFF" stroke-width="14" stroke-linecap="round" opacity="0.5"/>`);
}

// CheckButton 토글 스위치 (코지 pill). on=코랄+노브 우측, off=탄색+노브 좌측.
function toggle(on) {
  const pill = on ? '#F2A0A8' : '#D8CBB2';
  const ol = on ? '#D98088' : '#B7A88C';
  const knobX = on ? 78 : 30;
  return svg(108, 56,
    `<rect x="4" y="8" width="100" height="40" rx="20" fill="${pill}" stroke="${ol}" stroke-width="3"/>` +
    `<circle cx="${knobX}" cy="28" r="15" fill="#FFFDF7" stroke="${ol}" stroke-width="3"/>`);
}
const toggle_on = () => toggle(true);
const toggle_off = () => toggle(false);

const DECOR = {
  hill_far, hill_near, tree, fence, pond, rock, stump, grasstuft,
  flower_pink, flower_purple, flower_blue, gacha_machine: gachaMachine,
  toggle_on, toggle_off,
};

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  const only = new Set(process.argv.slice(2));
  const ids = Object.keys(DECOR).filter((id) => !only.size || only.has(id));
  let bad = 0;
  for (const id of ids) {
    const buf = await sharp(Buffer.from(DECOR[id]())).png({ compressionLevel: 9 }).toBuffer();
    await writeFile(join(OUT_DIR, `${id}.png`), buf);
    const ok = buf.length >= 256;
    if (!ok) bad++;
    console.log(`${ok ? '✓' : '✗'} ${id}.png  ${(buf.length / 1024).toFixed(1)} KB`);
  }
  console.log(`\nDone: ${ids.length} decor, ${bad} failed.`);
  if (bad) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
