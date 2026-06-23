// gen-placeholders.mjs — 몽글목장 캐릭터 스프라이트 12종 생성기 (절차적 SVG → PNG).
//
// 외부 API 없이 로컬에서 SVG 문자열을 sharp(librsvg)로 래스터라이즈한다.
// 출력: assets/characters/{id}.png — 512×512, 투명 배경.
// 디자인 언어(docs/GAME_DESIGN.md §4 아트 바이블): 점 눈 2 + 작은 입 +
// 분홍 볼터치 + 2~2.5등신 + 파스텔 단색 몸 + 부드러운 어두운 외곽선 +
// 캐릭터당 식별 소품 1개. 희귀도 연출은 런타임 오버레이 담당이므로 넣지
// 않는다 — 단 금붕(legendary)만 황금 그라데이션 + 미세 광택을 허용.
//
// 사용법:
//   node scripts/gen-placeholders.mjs            # 12장 전부
//   node scripts/gen-placeholders.mjs moka doto  # 일부만 재생성

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '..', 'assets', 'characters');

const INK = '#3B3129'; // 눈/입 공통 잉크색
const ROSE = '#CC8A8F'; // 볼터치 공통 더스티 로즈 (24종 일관)

// 볼터치/눈 radial 그라데이션 defs용 유일 id 카운터 (blush·blushGlow 공유).
let _blushSeq = 0;

// ── 공통 파츠 헬퍼 ──────────────────────────────────────────────────────────

// 눈: 점눈 + 일관된 2점 하이라이트(큰 주 반짝 + 반대쪽 작은 캐치라이트).
// 두 점 모두 또렷하게(opacity↑) — 24종 시선의 생기를 통일하는 결정타.
const eye = (x, y, r = 12) =>
  `<circle cx="${x}" cy="${y}" r="${r}" fill="${INK}"/>` +
  `<circle cx="${x + r * 0.34}" cy="${y - r * 0.34}" r="${(r * 0.32).toFixed(1)}" fill="#FFFFFF"/>` +
  `<circle cx="${x - r * 0.30}" cy="${y + r * 0.36}" r="${(r * 0.15).toFixed(1)}" fill="#FFFFFF" opacity="0.78"/>`;

// 졸린 점눈(부엉): 납작한 타원 + 윗눈꺼풀 선.
const sleepyEye = (x, y) =>
  `<ellipse cx="${x}" cy="${y}" rx="12" ry="7.5" fill="${INK}"/>` +
  `<path d="M ${x - 15} ${y - 9} Q ${x} ${y - 16} ${x + 15} ${y - 9}" fill="none" stroke="${INK}" stroke-width="5" stroke-linecap="round"/>` +
  `<circle cx="${x + 4}" cy="${y - 2}" r="2.6" fill="#FFFFFF" opacity="0.9"/>`;

const mouth = (cx, y, w = 18) =>
  `<path d="M ${cx - w / 2} ${y} Q ${cx} ${y + w * 0.55} ${cx + w / 2} ${y}" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round"/>`;

// 볼터치는 성인향으로 더스티하게 — 쨍한 분홍/높은 불투명이 '유아' 인상의 1번 트리거.
// 가장자리를 radial로 페이드(0.24→0)시켜 딱딱한 원 경계를 없앤다 — 신규 12종의
// blushGlow와 동일한 결을 기존 12종에도 부여(24종 볼터치 일관).
const blush = (x, y, r = 13) => {
  const gid = `blush_${_blushSeq++}`;
  return (
    `<defs><radialGradient id="${gid}" cx="0.5" cy="0.5" r="0.5">` +
    `<stop offset="0.4" stop-color="${ROSE}" stop-opacity="0.24"/>` +
    `<stop offset="1" stop-color="${ROSE}" stop-opacity="0"/></radialGradient></defs>` +
    `<circle cx="${x}" cy="${y}" r="${(r * 1.35).toFixed(1)}" fill="url(#${gid})"/>`
  );
};

const stub = (cx, cy, rx, ry, fill, ol, rot = 0) =>
  `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${fill}" stroke="${ol}" stroke-width="7" ` +
  `transform="rotate(${rot} ${cx} ${cy})"/>`;

// 4점 반짝이(별가루 장식 / 금붕 광택 보조).
const sparkle = (x, y, s, fill) =>
  `<path d="M ${x} ${y - s} Q ${x + s * 0.22} ${y - s * 0.22} ${x + s} ${y} ` +
  `Q ${x + s * 0.22} ${y + s * 0.22} ${x} ${y + s} ` +
  `Q ${x - s * 0.22} ${y + s * 0.22} ${x - s} ${y} ` +
  `Q ${x - s * 0.22} ${y - s * 0.22} ${x} ${y - s} Z" fill="${fill}"/>`;

// 구름형 뭉게 윤곽(솜솜): 타원 둘레 점들 사이를 바깥쪽 호로 연결.
function cloudBlob(cx, cy, rx, ry, bumps) {
  const pts = [];
  for (let i = 0; i < bumps; i++) {
    const t = (i / bumps) * Math.PI * 2 - Math.PI / 2;
    pts.push([cx + rx * Math.cos(t), cy + ry * Math.sin(t)]);
  }
  let d = `M ${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)} `;
  for (let i = 0; i < bumps; i++) {
    const [x2, y2] = pts[(i + 1) % bumps];
    const [x1, y1] = pts[i];
    const r = Math.hypot(x2 - x1, y2 - y1) * 0.62;
    d += `A ${r.toFixed(1)} ${r.toFixed(1)} 0 0 1 ${x2.toFixed(1)} ${y2.toFixed(1)} `;
  }
  return d + 'Z';
}

// 둥근 별 윤곽(별가루 = 별사탕): 외/내 반지름 교대 꼭짓점을 Q로 부드럽게.
function smoothStar(cx, cy, rOut, rIn, points) {
  const n = points * 2;
  const v = [];
  for (let i = 0; i < n; i++) {
    const t = (i / n) * Math.PI * 2 - Math.PI / 2;
    const r = i % 2 === 0 ? rOut : rIn;
    v.push([cx + r * Math.cos(t), cy + r * Math.sin(t)]);
  }
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  let m = mid(v[n - 1], v[0]);
  let d = `M ${m[0].toFixed(1)} ${m[1].toFixed(1)} `;
  for (let i = 0; i < n; i++) {
    m = mid(v[i], v[(i + 1) % n]);
    d += `Q ${v[i][0].toFixed(1)} ${v[i][1].toFixed(1)} ${m[0].toFixed(1)} ${m[1].toFixed(1)} `;
  }
  return d + 'Z';
}

// 공통 접지 섀도(24종 일괄): 실루엣을 따라 부드러운 드롭섀도를 깔아 바닥에
// 닿은 무게감 + 앰비언트 오클루전을 한 번에 준다. dy>blur 라 그림자가 발밑에
// 고이고(접지감), 잉크색 22% 라 어른향으로 차분하다. 모서리 alpha는 보존
// (librsvg feDropShadow는 투명 영역을 칠하지 않음 — 합성 테스트로 확인).
const GROUND_SHADOW =
  `<filter id="groundShadow" x="-25%" y="-25%" width="150%" height="150%">` +
  `<feDropShadow dx="0" dy="9" stdDeviation="8" flood-color="${INK}" flood-opacity="0.22"/></filter>`;

function svgDoc(inner, defs = '') {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">` +
    `<defs>${GROUND_SHADOW}${defs}</defs>` +
    `<g filter="url(#groundShadow)" stroke-linejoin="round" stroke-linecap="round">${inner}</g></svg>`
  );
}

// ── B 스펙 헬퍼 (신규 12종 전용 — 기존 12종 렌더는 변하지 않음) ───────────────
//
// DESIGN_SPEC §B: 한 "가문"의 응집을 강제한다. 몸색은 즉흥 hex가 아니라
// hsl(L 0.86 / C 0.11 파스텔 대역, hue만 색상환에서 선택)로 산출하고,
// 외곽선은 동계열 L−0.40, 몸엔 세로 그라데이션 + 셀 음영, 볼엔 글로우 림.

// HSL → hex. h:0~360, s:0~1, l:0~1. (CSS hsl 정의와 동일.)
function hslHex(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  let r = 0, g = 0, b = 0;
  if (hp < 1) [r, g, b] = [c, x, 0];
  else if (hp < 2) [r, g, b] = [x, c, 0];
  else if (hp < 3) [r, g, b] = [0, c, x];
  else if (hp < 4) [r, g, b] = [0, x, c];
  else if (hp < 5) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  const m = l - c / 2;
  const to = (v) => Math.round(Math.min(1, Math.max(0, v + m)) * 255)
    .toString(16).padStart(2, '0');
  return `#${to(r)}${to(g)}${to(b)}`;
}

// 몸색: 어른향 '더스티 파스텔'. 밝은 베이비 파스텔(L0.86)이 아니라 회색이
// 살짝 섞인 뮤트 톤(L0.76, S0.20)으로 — 장난감이 아닌 데스크 오브제 인상.
const hsl = (h) => hslHex(h, 0.20, 0.76);

// 외곽선색: 같은 hue, 채도를 낮춰 차분하게(까만 두꺼운 선의 아동 만화 느낌 회피).
const outlineOf = (h) => hslHex(h, 0.18, 0.40);

// 몸보다 살짝 밝은 톤 (그라데이션 상단 / 배·주둥이 패치용) — 대비를 줄여 매트하게.
const lightOf = (h) => hslHex(h, 0.16, 0.83);

// 기존 12종(인라인 hex)을 어른향 더스티 톤으로 끌어내리는 후처리: 채도 ×0.6,
// 명도 −6%. hue 보존 → 캐릭터 식별성 유지하되 '장난감 → 데스크 오브제'로.
function mute(hex) {
  const n = parseInt(hex.slice(1), 16);
  const r = ((n >> 16) & 255) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0; const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h /= 6;
  }
  return hslHex(h * 360, s * 0.6, Math.max(0, l - 0.06));
}

// 몸 세로 그라데이션 defs: 상단 +6% 밝기 → 하단 몸색. id는 캐릭터별 유일.
function bodyGrad(id, h) {
  return (
    `<linearGradient id="grad_${id}" x1="0" y1="0" x2="0" y2="1">` +
    `<stop offset="0" stop-color="${hslHex(h, 0.16, 0.82)}"/>` +
    `<stop offset="1" stop-color="${hsl(h)}"/></linearGradient>`
  );
}

// 셀 음영: 몸 하단 1/3에 어두운 동계열 반투명 호 (opacity 0.12) — 매끈함 제거.
function cellShade(cx, bottomY, rx, h) {
  const shade = hslHex(h, 0.26, 0.50);
  const top = bottomY - rx * 0.5;
  return (
    `<path d="M ${cx - rx} ${top} Q ${cx} ${bottomY + rx * 0.18} ${cx + rx} ${top} ` +
    `Q ${cx} ${bottomY} ${cx - rx} ${top} Z" fill="${shade}" opacity="0.12"/>`
  );
}

// 볼터치 + radial 글로우 림: 볼 원 + 0.42→0 페이드 림(디지털 글로우).
function blushGlow(x, y, r = 16) {
  const gid = `blush_${_blushSeq++}`;
  return (
    `<defs><radialGradient id="${gid}" cx="0.5" cy="0.5" r="0.5">` +
    `<stop offset="0.45" stop-color="${ROSE}" stop-opacity="0.26"/>` +
    `<stop offset="1" stop-color="${ROSE}" stop-opacity="0"/></radialGradient></defs>` +
    `<circle cx="${x}" cy="${y}" r="${(r * 1.3).toFixed(1)}" fill="url(#${gid})"/>` +
    `<circle cx="${x}" cy="${y}" r="${r}" fill="${ROSE}" opacity="0.22"/>`
  );
}

// 눈(신규): 기존 eye와 동일한 2점 하이라이트 규칙을 따른다 — 신구 24종의
// 시선을 하나의 손맛으로 통일. r 기본 13.
const eye2 = (x, y, r = 13) => eye(x, y, r);

// ── 캐릭터 12종 ─────────────────────────────────────────────────────────────

// moka — 크림색 두더지, 머리 위 새싹. 큼직한 분홍 앞발(땅파기).
function moka() {
  const body = mute('#F4E5C8'), light = mute('#FAF0DC'), ol = mute('#8A6F52');
  return svgDoc(
    // 몸 (크고 둥근 머리=몸 일체형)
    `<ellipse cx="256" cy="292" rx="148" ry="152" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 새싹 (식별 소품)
    `<path d="M 256 142 C 252 116 254 100 262 84" fill="none" stroke="#5F8F57" stroke-width="9"/>` +
    `<path d="M 260 92 C 236 92 222 78 222 58 C 246 58 260 72 260 92 Z" fill="#8CC98B" stroke="#5F8F57" stroke-width="6"/>` +
    `<path d="M 262 96 C 286 96 300 82 300 62 C 276 62 262 76 262 96 Z" fill="#A4D8A0" stroke="#5F8F57" stroke-width="6"/>` +
    // 두더지 앞발 (살짝 큼) + 발
    stub(130, 352, 32, 42, light, ol, 16) +
    stub(382, 352, 32, 42, light, ol, -16) +
    stub(202, 448, 30, 18, body, ol) +
    stub(310, 448, 30, 18, body, ol) +
    // 주둥이 + 분홍 코
    `<ellipse cx="256" cy="326" rx="54" ry="40" fill="${light}"/>` +
    `<ellipse cx="256" cy="308" rx="15" ry="11" fill="#EFA0A0"/>` +
    // 얼굴
    eye(198, 264) + eye(314, 264) + mouth(256, 332, 18) +
    blush(156, 304, 17) + blush(356, 304, 17)
  );
}

// somsom — 구름 같은 아기 양. 뭉게 윤곽 양털 + 베이지 얼굴 패치.
function somsom() {
  const wool = mute('#FBF5EA'), skin = mute('#F2DCC4'), ol = mute('#9A8470');
  return svgDoc(
    // 다리 (양털 뒤에서 빼꼼)
    `<rect x="184" y="376" width="36" height="80" rx="17" fill="${skin}" stroke="${ol}" stroke-width="7"/>` +
    `<rect x="292" y="376" width="36" height="80" rx="17" fill="${skin}" stroke="${ol}" stroke-width="7"/>` +
    // 뭉게 양털
    `<path d="${cloudBlob(256, 264, 158, 142, 11)}" fill="${wool}" stroke="${ol}" stroke-width="8"/>` +
    // 늘어진 귀
    stub(158, 268, 30, 18, skin, ol, 26) +
    stub(354, 268, 30, 18, skin, ol, -26) +
    // 얼굴 패치
    `<ellipse cx="256" cy="276" rx="84" ry="74" fill="${skin}" stroke="${ol}" stroke-width="7"/>` +
    // 이마 양털 한 줌
    `<path d="${cloudBlob(256, 198, 44, 26, 6)}" fill="${wool}" stroke="${ol}" stroke-width="6"/>` +
    // 얼굴
    eye(216, 268, 11) + eye(296, 268, 11) + mouth(256, 296, 15) +
    blush(192, 296, 13) + blush(320, 296, 13)
  );
}

// kongkong — 연두 완두콩, 꼬투리 모자(물결 가장자리 후드) + 꼭지 덩굴.
function kongkong() {
  const body = mute('#CDE6A4'), pod = mute('#8AC06E'), ol = mute('#5F6E45');
  return svgDoc(
    // 몸
    `<ellipse cx="256" cy="310" rx="128" ry="142" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 팔/발 스텁
    stub(140, 346, 22, 30, body, ol, 18) +
    stub(372, 346, 22, 30, body, ol, -18) +
    stub(206, 452, 28, 17, body, ol) +
    stub(306, 452, 28, 17, body, ol) +
    // 꼬투리 모자 (식별 소품): 물결 밑단 후드
    `<path d="M 130 234 Q 132 126 256 116 Q 380 126 382 234 Q 350 206 318 228 Q 287 204 256 228 Q 225 204 194 228 Q 162 206 130 234 Z" ` +
    `fill="${pod}" stroke="${ol}" stroke-width="8"/>` +
    // 꼭지 덩굴 + 잎
    `<path d="M 256 116 Q 250 94 268 82" fill="none" stroke="${ol}" stroke-width="8"/>` +
    `<path d="M 268 82 C 290 86 300 74 298 58 C 280 56 268 66 268 82 Z" fill="${pod}" stroke="${ol}" stroke-width="6"/>` +
    // 얼굴
    eye(206, 298) + eye(306, 298) + mouth(256, 326, 18) +
    blush(166, 332, 16) + blush(346, 332, 16)
  );
}

// ppiyak — 노란 병아리, 알껍질 바지(지그재그 깨진 단). 다이아 부리.
function ppiyak() {
  const body = mute('#FBE284'), wing = mute('#F6D468'), shell = mute('#FDFAF1'), ol = mute('#A4884E');
  return svgDoc(
    // 몸
    `<ellipse cx="256" cy="290" rx="142" ry="148" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 머리 깃털 한 가닥
    `<path d="M 250 148 Q 254 116 278 118" fill="none" stroke="${ol}" stroke-width="7"/>` +
    // 알껍질 바지 (식별 소품): 지그재그 윗단 + 몸 하부 윤곽
    `<path d="M 122 338 L 156 310 L 190 338 L 223 310 L 256 338 L 289 310 L 322 338 L 356 310 L 390 338 ` +
    `A 142 148 0 0 1 122 338 Z" fill="${shell}" stroke="${ol}" stroke-width="8"/>` +
    // 날개 스텁
    stub(126, 322, 24, 38, wing, ol, 14) +
    stub(386, 322, 24, 38, wing, ol, -14) +
    // 부리
    `<path d="M 238 280 L 256 268 L 274 280 L 256 296 Z" fill="#F2A158" stroke="${ol}" stroke-width="6"/>` +
    // 얼굴
    eye(202, 256) + eye(310, 256) +
    blush(164, 292, 16) + blush(348, 292, 16)
  );
}

// doto — 갈색 다람쥐, 도토리 깍정이 모자 + 큰 꼬리.
function doto() {
  const body = mute('#DDB68E'), belly = mute('#EFD9BC'), tail = mute('#C79A6B'), cap = mute('#97683F'), ol = mute('#7B5A3C');
  return svgDoc(
    // 꼬리 (몸 뒤)
    `<path d="M 340 392 C 458 376 478 218 414 156 C 388 132 346 148 362 192 C 408 238 402 330 322 366 Z" ` +
    `fill="${tail}" stroke="${ol}" stroke-width="8"/>` +
    // 귀
    `<circle cx="158" cy="186" r="24" fill="${body}" stroke="${ol}" stroke-width="7"/>` +
    `<circle cx="342" cy="186" r="24" fill="${body}" stroke="${ol}" stroke-width="7"/>` +
    // 몸
    `<ellipse cx="250" cy="306" rx="134" ry="146" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    `<ellipse cx="250" cy="354" rx="72" ry="64" fill="${belly}"/>` +
    // 도토리 깍정이 모자 (식별 소품)
    `<path d="M 124 220 Q 126 98 250 94 Q 374 98 376 220 Q 312 200 250 208 Q 188 200 124 220 Z" ` +
    `fill="${cap}" stroke="${ol}" stroke-width="8"/>` +
    `<path d="M 150 196 Q 250 162 350 196" fill="none" stroke="#7E5532" stroke-width="5" opacity="0.65"/>` +
    `<rect x="240" y="58" width="20" height="34" rx="9" fill="#6E4F33" stroke="${ol}" stroke-width="6"/>` +
    // 팔/발 스텁
    stub(136, 350, 22, 32, body, ol, 16) +
    stub(360, 354, 22, 32, body, ol, -16) +
    stub(216, 446, 28, 17, body, ol) +
    stub(296, 446, 28, 17, body, ol) +
    // 코 + 얼굴
    `<ellipse cx="250" cy="296" rx="10" ry="8" fill="#8A5C3C"/>` +
    eye(198, 274) + eye(302, 274) + mouth(250, 314, 16) +
    blush(162, 310, 16) + blush(338, 310, 16)
  );
}

// pudding — 커스터드 푸딩 실루엣 + 카라멜 드립 층.
function pudding() {
  const custard = mute('#F8DD8E'), caramel = mute('#C9854D'), ol = mute('#8F6234');
  return svgDoc(
    // 푸딩 몸 (윗면 둥근 사다리꼴)
    `<path d="M 120 396 Q 116 430 158 432 L 354 432 Q 396 430 392 396 Q 380 310 368 250 Q 356 164 256 162 Q 156 164 144 250 Q 132 310 120 396 Z" ` +
    `fill="${custard}" stroke="${ol}" stroke-width="8"/>` +
    // 카라멜 층 (식별 소품): 드립 밑단
    `<path d="M 147 246 Q 160 168 256 166 Q 352 168 365 246 Q 342 260 322 254 Q 318 284 300 282 Q 294 258 272 262 Q 258 292 240 262 Q 216 258 210 280 Q 192 284 188 256 Q 166 262 147 246 Z" ` +
    `fill="${caramel}" stroke="${ol}" stroke-width="7"/>` +
    // 팔/발 스텁
    stub(128, 360, 20, 28, custard, ol, 20) +
    stub(384, 360, 20, 28, custard, ol, -20) +
    stub(206, 438, 26, 14, custard, ol) +
    stub(306, 438, 26, 14, custard, ol) +
    // 얼굴 (나른한 표정)
    eye(206, 330) + eye(306, 330) + mouth(256, 358, 14) +
    blush(168, 358, 15) + blush(344, 358, 15)
  );
}

// jiji — 분홍-하늘 투톤 지우개 (둥근 사각, 아랫단 하늘색).
function jiji() {
  const pink = mute('#F6BCCB'), sky = mute('#ABD7EE'), ol = mute('#7D6B6E');
  const bodyRect = `x="140" y="132" width="232" height="290" rx="62"`;
  return svgDoc(
    // 발 스텁 (하늘색)
    stub(202, 432, 26, 17, sky, ol) +
    stub(310, 432, 26, 17, sky, ol) +
    // 몸: 분홍 베이스 + 클리핑된 하늘색 아랫단 (식별 소품: 투톤)
    `<rect ${bodyRect} fill="${pink}"/>` +
    `<g clip-path="url(#jijiClip)"><rect x="140" y="316" width="232" height="106" fill="${sky}"/>` +
    `<line x1="140" y1="316" x2="372" y2="316" stroke="${ol}" stroke-width="6" opacity="0.8"/></g>` +
    `<rect ${bodyRect} fill="none" stroke="${ol}" stroke-width="8"/>` +
    // 팔 스텁 (수줍게 몸에 붙임)
    stub(140, 330, 18, 26, pink, ol, 14) +
    stub(372, 330, 18, 26, pink, ol, -14) +
    // 얼굴 (수줍은 작은 입)
    eye(212, 238) + eye(300, 238) + mouth(256, 266, 11) +
    blush(180, 268, 15) + blush(332, 268, 15),
    `<clipPath id="jijiClip"><rect ${bodyRect}/></clipPath>`
  );
}

// mongdang — 몽당연필. 깎인 나무 단면 + 연필심 머리.
function mongdang() {
  const barrel = mute('#F9D979'), wood = mute('#EBD5AE'), lead = mute('#56504A'), ol = mute('#806A45');
  return svgDoc(
    // 연필 몸통 (밑면 둥근 기둥)
    `<path d="M 162 204 L 350 204 L 350 386 Q 350 434 302 436 L 210 436 Q 162 434 162 386 Z" ` +
    `fill="${barrel}" stroke="${ol}" stroke-width="8"/>` +
    // 육각 면 분할선
    `<line x1="212" y1="210" x2="212" y2="430" stroke="#E3B95C" stroke-width="5" opacity="0.85"/>` +
    `<line x1="300" y1="210" x2="300" y2="430" stroke="#E3B95C" stroke-width="5" opacity="0.85"/>` +
    // 깎인 나무 원뿔 (물결 단)
    `<path d="M 256 66 L 344 208 Q 322 194 300 210 Q 278 196 256 212 Q 234 196 212 210 Q 190 194 168 208 Z" ` +
    `fill="${wood}" stroke="${ol}" stroke-width="8"/>` +
    // 연필심 (식별 소품)
    `<path d="M 256 66 L 228 114 Q 256 128 284 114 Z" fill="${lead}" stroke="${ol}" stroke-width="6"/>` +
    // 팔/발 스텁
    stub(162, 326, 18, 26, barrel, ol, 16) +
    stub(350, 326, 18, 26, barrel, ol, -16) +
    stub(214, 444, 25, 15, barrel, ol) +
    stub(298, 444, 25, 15, barrel, ol) +
    // 얼굴
    eye(216, 286) + eye(296, 286) + mouth(256, 314, 15) +
    blush(186, 314, 14) + blush(326, 314, 14)
  );
}

// latte — 갈색 수달, 배의 크림 패치에 라떼아트 로제타 (식별 소품).
function latte() {
  const body = mute('#C49B73'), cream = mute('#F0E2CB'), art = mute('#B5825A'), ol = mute('#765539');
  return svgDoc(
    // 꼬리 (몸 뒤, 끝이 가늘어지는 수달 꼬리)
    `<path d="M 350 402 Q 446 390 470 438 Q 476 458 452 460 Q 398 462 350 438 Z" ` +
    `fill="#B58B62" stroke="${ol}" stroke-width="8"/>` +
    // 귀
    `<circle cx="166" cy="158" r="21" fill="${body}" stroke="${ol}" stroke-width="7"/>` +
    `<circle cx="346" cy="158" r="21" fill="${body}" stroke="${ol}" stroke-width="7"/>` +
    `<circle cx="168" cy="160" r="9" fill="#8F6B49"/>` +
    `<circle cx="344" cy="160" r="9" fill="#8F6B49"/>` +
    // 몸
    `<ellipse cx="256" cy="298" rx="134" ry="156" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 주둥이 + 코
    `<ellipse cx="256" cy="266" rx="50" ry="36" fill="${cream}"/>` +
    `<ellipse cx="256" cy="252" rx="12" ry="9" fill="#6F4E36"/>` +
    // 배의 라떼 패치 + 로제타(잎 + 하트 마무리)
    `<ellipse cx="256" cy="372" rx="76" ry="70" fill="${cream}"/>` +
    `<path d="M 256 322 Q 252 360 256 396" fill="none" stroke="${art}" stroke-width="7"/>` +
    `<path d="M 254 340 Q 216 332 210 358 M 258 340 Q 296 332 302 358" fill="none" stroke="${art}" stroke-width="7"/>` +
    `<path d="M 254 364 Q 224 358 220 380 M 258 364 Q 288 358 292 380" fill="none" stroke="${art}" stroke-width="7"/>` +
    `<path d="M 256 424 C 236 404 244 386 256 396 C 268 386 276 404 256 424 Z" fill="${art}"/>` +
    // 수염
    `<path d="M 204 256 q -20 -4 -34 2 M 204 266 q -18 4 -30 12" fill="none" stroke="#8F6B49" stroke-width="4"/>` +
    `<path d="M 308 256 q 20 -4 34 2 M 308 266 q 18 4 30 12" fill="none" stroke="#8F6B49" stroke-width="4"/>` +
    // 팔/발 스텁
    stub(132, 330, 22, 32, body, ol, 16) +
    stub(380, 330, 22, 32, body, ol, -16) +
    stub(210, 450, 28, 16, body, ol) +
    stub(302, 450, 28, 16, body, ol) +
    // 얼굴
    eye(204, 238) + eye(308, 238) + mouth(256, 268, 14) +
    blush(162, 280, 16) + blush(350, 280, 16)
  );
}

// byeolgaru — 파스텔 별사탕 요정. 둥근 8뿔 별 몸 + 떠다니는 반짝이.
function byeolgaru() {
  const body = mute('#DCC8F2'), ol = mute('#7C6B96');
  return svgDoc(
    `<path d="${smoothStar(256, 264, 174, 100, 8)}" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 반짝이 (요정 연출 — 희귀도 이펙트가 아닌 모티프 일부)
    sparkle(92, 120, 18, '#FBE7A2') +
    sparkle(428, 168, 14, '#FBE7A2') +
    sparkle(118, 416, 13, '#F7D9EC') +
    sparkle(404, 396, 17, '#F7D9EC') +
    // 얼굴
    eye(212, 254) + eye(300, 254) + mouth(256, 282, 15) +
    blush(180, 282, 14) + blush(332, 282, 14)
  );
}

// buong — 보라 아기 부엉이. 귀깃 + 졸린 점눈 + 배 깃털 스캘럽.
function buong() {
  const body = mute('#C2ABE2'), wing = mute('#A98FD3'), belly = mute('#E8DFF6'), ol = mute('#6A5887');
  return svgDoc(
    // 귀깃 (식별 소품): 바깥쪽으로 비스듬한 짧은 뿔깃 — 토끼귀로 읽히지 않게 낮고 뾰족하게
    `<path d="M 156 184 Q 110 152 112 102 Q 168 118 200 170 Z" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    `<path d="M 356 184 Q 402 152 400 102 Q 344 118 312 170 Z" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 몸
    `<ellipse cx="256" cy="298" rx="142" ry="158" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 날개 스텁
    stub(128, 326, 28, 58, wing, ol, 12) +
    stub(384, 326, 28, 58, wing, ol, -12) +
    // 배 + 깃털 스캘럽
    `<ellipse cx="256" cy="356" rx="84" ry="84" fill="${belly}"/>` +
    `<path d="M 196 346 Q 216 366 236 346 Q 256 366 276 346 Q 296 366 316 346" fill="none" stroke="#C9B6E8" stroke-width="5"/>` +
    `<path d="M 206 384 Q 226 404 246 384 Q 266 404 286 384 Q 306 404 306 384" fill="none" stroke="#C9B6E8" stroke-width="5"/>` +
    // 부리
    `<path d="M 242 266 L 256 256 L 270 266 L 256 284 Z" fill="#F0AC5C" stroke="${ol}" stroke-width="6"/>` +
    // 발 (주황)
    stub(208, 452, 26, 15, '#F0AC5C', ol) +
    stub(304, 452, 26, 15, '#F0AC5C', ol) +
    // 졸린 얼굴
    sleepyEye(200, 250) + sleepyEye(312, 250) +
    blush(158, 284, 16) + blush(354, 284, 16)
  );
}

// geumbung — 황금 붕어빵 (legendary 한정: 금 그라데이션 + 미세 광택 허용).
// 물고기형 빵 + 갈래 꼬리 + 와플 격자 결.
function geumbung() {
  const ol = '#8A5C16';
  const fish =
    'M 64 286 Q 70 220 140 194 Q 228 158 312 194 Q 358 212 376 250 ' +
    'Q 402 236 450 196 Q 444 252 416 286 Q 444 320 450 376 Q 402 336 376 322 ' +
    'Q 358 360 312 378 Q 228 414 140 378 Q 70 352 64 286 Z';
  // 격자 결: 대각선 양방향
  let grid = '';
  for (let i = -4; i <= 14; i++) {
    grid += `<line x1="${i * 40 - 80}" y1="100" x2="${i * 40 + 240}" y2="420" stroke="#C08A2A" stroke-width="4" opacity="0.45"/>`;
    grid += `<line x1="${i * 40 + 240}" y1="100" x2="${i * 40 - 80}" y2="420" stroke="#C08A2A" stroke-width="4" opacity="0.45"/>`;
  }
  return svgDoc(
    // 등지느러미 빵 혹 (몸 뒤, 둥근 지느러미)
    `<ellipse cx="262" cy="160" rx="46" ry="28" fill="#EFBF45" stroke="${ol}" stroke-width="7" transform="rotate(-22 262 160)"/>` +
    // 몸
    `<path d="${fish}" fill="url(#goldGrad)" stroke="${ol}" stroke-width="8"/>` +
    `<g clip-path="url(#fishClip)">${grid}</g>` +
    // 꼬리 경계의 결
    `<path d="M 352 240 Q 376 286 352 334" fill="none" stroke="#C08A2A" stroke-width="5" opacity="0.7"/>` +
    // 미세 광택 (legendary 허용 연출)
    `<ellipse cx="216" cy="226" rx="92" ry="32" fill="#FFFFFF" opacity="0.20" transform="rotate(-10 216 226)"/>` +
    sparkle(140, 168, 12, '#FFF3C4') + sparkle(330, 348, 10, '#FFF3C4') +
    // 얼굴 (머리 쪽에 정면형 얼굴)
    eye(148, 262) + eye(238, 254) + mouth(192, 296, 16) +
    blush(116, 298, 15) + blush(272, 292, 15),
    `<linearGradient id="goldGrad" x1="0" y1="0" x2="0" y2="1">` +
    `<stop offset="0" stop-color="#F8D060"/><stop offset="1" stop-color="#DC9F28"/></linearGradient>` +
    `<clipPath id="fishClip"><path d="${fish}"/></clipPath>`
  );
}

// ── 신규 캐릭터 12종 (B 스펙 헬퍼 적용) ──────────────────────────────────────

// dorong — 분홍 아홀로틀. 식별 소품: 머리 위 외측 깃아가미 3쌍. (common)
function dorong() {
  const h = 350, body = `url(#grad_dorong)`, ol = outlineOf(h);
  // 깃아가미: 양쪽에서 바깥으로 뻗는 가지 + 끝 깃털 술
  const gill = (sx, sy, dir) => {
    let s = `<path d="M ${sx} ${sy} q ${dir * 40} -26 ${dir * 78} -30" fill="none" stroke="${ol}" stroke-width="9"/>`;
    for (let i = 1; i <= 3; i++) {
      const px = sx + dir * (24 + i * 18), py = sy - 12 - i * 6;
      s += `<ellipse cx="${px}" cy="${py}" rx="16" ry="11" fill="${hsl(h)}" stroke="${ol}" stroke-width="6" transform="rotate(${dir * -28} ${px} ${py})"/>`;
    }
    return s;
  };
  return svgDoc(
    gill(168, 196, -1) + gill(344, 196, 1) +
    gill(176, 230, -1) + gill(336, 230, 1) +
    `<ellipse cx="256" cy="300" rx="150" ry="150" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 422, 130, h) +
    // 짧은 앞발 스텁
    stub(132, 348, 26, 34, hsl(h), ol, 16) +
    stub(380, 348, 26, 34, hsl(h), ol, -16) +
    stub(212, 446, 30, 18, hsl(h), ol) +
    stub(300, 446, 30, 18, hsl(h), ol) +
    eye2(204, 286) + eye2(308, 286) + mouth(256, 320, 22) +
    blushGlow(160, 318, 17) + blushGlow(352, 318, 17),
    bodyGrad('dorong', h)
  );
}

// gosum — 베이지 고슴도치. 식별 소품: 등의 둥근 가시 능선. (common)
function gosum() {
  const h = 35, body = `url(#grad_gosum)`, ol = outlineOf(h);
  const quillCol = hslHex(h, 0.20, 0.66);
  // 등 가시: 위쪽 반원 둘레로 둥근 가시 능선
  let quills = '';
  for (let i = 0; i <= 9; i++) {
    const t = Math.PI * (0.08 + 0.84 * (i / 9));
    const bx = 256 - 150 * Math.cos(t), by = 286 - 150 * Math.sin(t);
    const tx = 256 - 196 * Math.cos(t), ty = 286 - 196 * Math.sin(t);
    quills += `<path d="M ${(bx - 14).toFixed(1)} ${by.toFixed(1)} Q ${tx.toFixed(1)} ${ty.toFixed(1)} ${(bx + 14).toFixed(1)} ${by.toFixed(1)} Z" fill="${quillCol}" stroke="${ol}" stroke-width="5"/>`;
  }
  return svgDoc(
    quills +
    `<ellipse cx="256" cy="300" rx="150" ry="138" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 420, 130, h) +
    // 뾰족 주둥이
    `<path d="M 196 312 Q 156 336 196 360 Q 236 348 230 330 Z" fill="${lightOf(h)}" stroke="${ol}" stroke-width="7"/>` +
    `<circle cx="178" cy="336" r="9" fill="${INK}"/>` +
    stub(214, 444, 28, 17, hsl(h), ol) +
    stub(300, 444, 28, 17, hsl(h), ol) +
    eye2(246, 296) + eye2(330, 296) + mouth(256, 332, 16) +
    blushGlow(214, 330, 15) + blushGlow(358, 330, 15),
    bodyGrad('gosum', h)
  );
}

// gaegul — 민트 개구리. 식별 소품: 머리 위 돌출 눈 2개. 3등신 다리노출. (common)
function gaegul() {
  const h = 150, body = `url(#grad_gaegul)`, ol = outlineOf(h);
  return svgDoc(
    // 뒷다리 (넓게 벌린 개구리 다리)
    `<path d="M 150 392 Q 96 408 110 452 Q 150 462 176 430 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="7"/>` +
    `<path d="M 362 392 Q 416 408 402 452 Q 362 462 336 430 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="7"/>` +
    // 넓은 타원 몸
    `<ellipse cx="256" cy="320" rx="156" ry="128" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 432, 138, h) +
    `<ellipse cx="256" cy="356" rx="92" ry="64" fill="${lightOf(h)}"/>` +
    // 돌출 눈 (머리 위 두 둥근 돔)
    `<circle cx="200" cy="208" r="46" fill="${hsl(h)}" stroke="${ol}" stroke-width="8"/>` +
    `<circle cx="312" cy="208" r="46" fill="${hsl(h)}" stroke="${ol}" stroke-width="8"/>` +
    `<circle cx="200" cy="208" r="20" fill="${INK}"/>` +
    `<circle cx="312" cy="208" r="20" fill="${INK}"/>` +
    `<circle cx="207" cy="201" r="7" fill="#FFFFFF" opacity="0.92"/>` +
    `<circle cx="319" cy="201" r="7" fill="#FFFFFF" opacity="0.92"/>` +
    mouth(256, 320, 60) +
    blushGlow(176, 312, 17) + blushGlow(336, 312, 17),
    bodyGrad('gaegul', h)
  );
}

// ddalbang — 딸기우유 방울. 식별 소품: 꼭지 딸기 꼭다리 + 점박이 씨. (common)
function ddalbang() {
  const h = 345, body = `url(#grad_ddalbang)`, ol = outlineOf(h);
  // 방울형 몸 (위 좁고 아래 둥근 물방울)
  const drop = 'M 256 120 Q 360 232 380 320 Q 388 446 256 446 Q 124 446 132 320 Q 152 232 256 120 Z';
  // 점박이 씨
  let seeds = '';
  const sp = [[200, 300], [256, 282], [312, 300], [228, 348], [284, 348], [256, 392]];
  for (const [sx, sy] of sp) seeds += `<ellipse cx="${sx}" cy="${sy}" rx="5" ry="8" fill="${hslHex(h, 0.30, 0.5)}"/>`;
  return svgDoc(
    `<path d="${drop}" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 432, 120, h) +
    seeds +
    // 딸기 꼭다리 (식별 소품): 초록 별잎 + 줄기
    `<path d="M 256 120 Q 250 92 270 80" fill="none" stroke="#5F8F57" stroke-width="8"/>` +
    `<path d="M 256 132 L 228 104 L 250 110 L 256 84 L 262 110 L 284 104 Z" fill="#8CC98B" stroke="#5F8F57" stroke-width="6"/>` +
    stub(150, 360, 20, 28, hsl(h), ol, 18) +
    stub(362, 360, 20, 28, hsl(h), ol, -18) +
    eye2(216, 318) + eye2(296, 318) + mouth(256, 348, 16) +
    blushGlow(182, 348, 15) + blushGlow(330, 348, 15),
    bodyGrad('ddalbang', h)
  );
}

// sikppang — 식빵 고양이 한 조각. 식별 소품: 사각 빵 + 가장자리 크러스트. (common)
function sikppang() {
  const h = 48, body = `url(#grad_sikppang)`, ol = outlineOf(h);
  const crust = hslHex(h, 0.34, 0.6);
  // 둥근 사각 식빵: 위가 봉긋한 빵 윤곽
  const slice = 'M 132 250 Q 132 150 256 150 Q 380 150 380 250 L 380 392 Q 380 432 340 432 L 172 432 Q 132 432 132 392 Z';
  return svgDoc(
    // 크러스트 테두리 (식별: 바깥 두꺼운 갈색 띠)
    `<path d="${slice}" fill="${crust}" stroke="${ol}" stroke-width="8"/>` +
    // 속살 (안쪽 밝은 빵)
    `<path d="M 156 254 Q 156 178 256 178 Q 356 178 356 254 L 356 388 Q 356 408 336 408 L 176 408 Q 156 408 156 388 Z" fill="${body}"/>` +
    cellShade(256, 398, 110, h) +
    // 고양이 귀 대신 — 빵 모서리 둥근 봉우리(세모귀 회피), 작은 발
    stub(206, 432, 26, 14, crust, ol) +
    stub(306, 432, 26, 14, crust, ol) +
    eye2(214, 286) + eye2(298, 286) +
    // 작은 ω 입
    `<path d="M 256 318 q -10 12 -20 0 M 256 318 q 10 12 20 0" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round"/>` +
    `<path d="M 248 308 L 256 316 L 264 308 Z" fill="#F2A158"/>` +
    blushGlow(184, 318, 16) + blushGlow(328, 318, 16),
    bodyGrad('sikppang', h)
  );
}

// mongsong — 회색 물범. 식별 소품: 짧은 지느러미 + 수염. 3등신 통통. (rare)
function mongsong() {
  const h = 215, body = `url(#grad_mongsong)`, ol = outlineOf(h);
  return svgDoc(
    // 긴 타원 몸 (가로로 둥근 물범)
    `<ellipse cx="256" cy="306" rx="166" ry="142" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 430, 148, h) +
    `<ellipse cx="256" cy="346" rx="96" ry="78" fill="${lightOf(h)}"/>` +
    // 옆 지느러미 (짧은 패들)
    `<path d="M 108 330 Q 64 350 96 392 Q 132 384 142 350 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="7"/>` +
    `<path d="M 404 330 Q 448 350 416 392 Q 380 384 370 350 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="7"/>` +
    // 꼬리 지느러미
    `<path d="M 222 444 Q 256 470 290 444 Q 272 456 256 452 Q 240 456 222 444 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="6"/>` +
    // 코
    `<ellipse cx="256" cy="300" rx="14" ry="10" fill="${INK}"/>` +
    // 수염 (식별 소품)
    `<path d="M 214 308 q -34 -2 -56 6 M 214 318 q -32 6 -50 16" fill="none" stroke="${outlineOf(h)}" stroke-width="4"/>` +
    `<path d="M 298 308 q 34 -2 56 6 M 298 318 q 32 6 50 16" fill="none" stroke="${outlineOf(h)}" stroke-width="4"/>` +
    eye2(206, 270) + eye2(306, 270) + mouth(256, 326, 18) +
    blushGlow(168, 304, 17) + blushGlow(344, 304, 17),
    bodyGrad('mongsong', h)
  );
}

// dalbo — 민들레 홀씨 요정. 식별 소품: 머리 위 홀씨 갓 + 떠다니는 솜털. (rare)
function dalbo() {
  const h = 90, body = `url(#grad_dalbo)`, ol = outlineOf(h);
  const fluff = hslHex(h, 0.10, 0.95);
  // 홀씨 갓: 중심에서 방사하는 솜대 + 끝 솜털
  let pappus = '';
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2;
    const ex = 256 + 96 * Math.cos(a), ey = 150 + 96 * Math.sin(a);
    pappus += `<line x1="256" y1="150" x2="${ex.toFixed(1)}" y2="${ey.toFixed(1)}" stroke="${ol}" stroke-width="3" opacity="0.7"/>`;
    pappus += `<circle cx="${ex.toFixed(1)}" cy="${ey.toFixed(1)}" r="9" fill="${fluff}" stroke="${ol}" stroke-width="2"/>`;
  }
  return svgDoc(
    pappus +
    `<circle cx="256" cy="150" r="26" fill="${hsl(h)}" stroke="${ol}" stroke-width="6"/>` +
    // 줄기
    `<path d="M 256 176 L 256 244" stroke="#7FA86A" stroke-width="9"/>` +
    // 원형 몸
    `<circle cx="256" cy="324" r="118" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 430, 104, h) +
    // 떠다니는 솜털 2개
    `<circle cx="116" cy="250" r="11" fill="${fluff}" stroke="${ol}" stroke-width="2"/>` +
    `<circle cx="404" cy="298" r="9" fill="${fluff}" stroke="${ol}" stroke-width="2"/>` +
    stub(150, 350, 18, 26, hsl(h), ol, 18) +
    stub(362, 350, 18, 26, hsl(h), ol, -18) +
    stub(218, 436, 26, 15, hsl(h), ol) +
    stub(294, 436, 26, 15, hsl(h), ol) +
    eye2(218, 318) + eye2(294, 318) + mouth(256, 346, 16) +
    blushGlow(186, 344, 15) + blushGlow(326, 344, 15),
    bodyGrad('dalbo', h)
  );
}

// beoseot — 빨강 물방울 버섯. 식별 소품: 둥근 점박이 갓(머리). 기둥형 몸. (rare)
function beoseot() {
  const h = 5, ol = outlineOf(h);
  const stemH = 80;
  // 둥근 점박이 갓
  const cap = 'M 110 232 Q 116 116 256 110 Q 396 116 402 232 Q 330 252 256 248 Q 182 252 110 232 Z';
  const dot = (x, y, r) => `<ellipse cx="${x}" cy="${y}" rx="${r}" ry="${r * 0.82}" fill="${hslHex(h, 0.06, 0.96)}"/>`;
  return svgDoc(
    // 기둥형 몸 (밝은 크림 줄기)
    `<path d="M 176 232 L 336 232 L 336 392 Q 336 446 256 446 Q 176 446 176 392 Z" fill="url(#grad_beoseotStem)" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 436, 84, stemH) +
    // 갓 (식별 소품): 빨강 + 흰 점박이
    `<path d="${cap}" fill="url(#grad_beoseot)" stroke="${ol}" stroke-width="8"/>` +
    dot(180, 178, 18) + dot(256, 158, 22) + dot(332, 178, 18) +
    dot(216, 210, 13) + dot(296, 210, 13) +
    // 짧은 팔
    stub(168, 332, 18, 26, hslHex(stemH, 0.11, 0.86), ol, 18) +
    stub(344, 332, 18, 26, hslHex(stemH, 0.11, 0.86), ol, -18) +
    // 얼굴 (줄기에)
    eye2(218, 322) + eye2(294, 322) + mouth(256, 350, 16) +
    blushGlow(188, 348, 15) + blushGlow(324, 348, 15),
    bodyGrad('beoseot', h) + bodyGrad('beoseotStem', stemH)
  );
}

// jogyak — 강가 조약돌 정령. 식별 소품: 이끼 한 줌 + 물결 점. 둥근 사각. (rare)
function jogyak() {
  const h = 210, body = `url(#grad_jogyak)`, ol = outlineOf(h);
  const moss = '#8FBF7A', mossOl = '#5F8F57';
  // 둥근 사각 돌 (매끈한 자갈)
  const stone = 'M 134 270 Q 130 168 256 156 Q 388 166 384 282 Q 388 408 256 420 Q 124 410 134 270 Z';
  return svgDoc(
    `<path d="${stone}" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 408, 124, h) +
    // 물결 점 (식별: 돌 표면 결)
    `<path d="M 168 300 q 26 -14 52 0 M 292 300 q 26 -14 52 0" fill="none" stroke="${outlineOf(h)}" stroke-width="4" opacity="0.5"/>` +
    `<circle cx="318" cy="246" r="6" fill="${outlineOf(h)}" opacity="0.4"/>` +
    // 이끼 한 줌 (식별 소품): 머리 위 둥근 이끼 클러스터
    `<path d="${cloudBlob(232, 168, 64, 30, 6)}" fill="${moss}" stroke="${mossOl}" stroke-width="6"/>` +
    `<circle cx="206" cy="158" r="5" fill="#B7E0A0"/>` +
    `<circle cx="248" cy="150" r="6" fill="#B7E0A0"/>` +
    `<circle cx="276" cy="162" r="4" fill="#B7E0A0"/>` +
    stub(214, 426, 28, 16, hsl(h), ol) +
    stub(300, 426, 28, 16, hsl(h), ol) +
    eye2(214, 296) + eye2(298, 296) + mouth(256, 326, 16) +
    blushGlow(184, 322, 15) + blushGlow(330, 322, 15),
    bodyGrad('jogyak', h)
  );
}

// haedal — 자수정 해마. 식별 소품: 말린 꼬리 + 등지느러미. S곡선 3등신. (epic)
function haedal() {
  const h = 280, body = `url(#grad_haedal)`, ol = outlineOf(h);
  // S곡선 몸통 (배 쪽 볼록 + 말린 꼬리)
  const seahorse =
    'M 256 156 Q 196 168 192 240 Q 188 304 236 332 Q 286 356 280 408 ' +
    'Q 276 452 232 458 Q 196 462 196 430 Q 196 410 222 410 Q 242 410 240 392 ' +
    'Q 236 360 196 344 Q 132 318 140 232 Q 148 152 256 144 Z';
  return svgDoc(
    `<path d="${seahorse}" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    // 등지느러미 (식별: 등쪽 물결 지느러미)
    `<path d="M 256 150 Q 318 146 332 200 Q 296 188 286 214 Q 264 196 256 220 Z" fill="${lightOf(h)}" stroke="${ol}" stroke-width="6"/>` +
    // 주둥이 (긴 관 입)
    `<path d="M 178 222 Q 130 224 116 244 Q 138 252 178 244 Z" fill="${hsl(h)}" stroke="${ol}" stroke-width="6"/>` +
    cellShade(220, 320, 70, h) +
    // 말린 꼬리 끝 하이라이트
    `<circle cx="218" cy="432" r="8" fill="${lightOf(h)}"/>` +
    eye2(208, 198, 12) + eye2(258, 198, 12) + mouth(232, 232, 12) +
    blushGlow(182, 214, 13) + blushGlow(282, 214, 13),
    bodyGrad('haedal', h)
  );
}

// gureum — 솜사탕 구름 정령. 식별 소품: 머리 위 미니 무지개. cloudBlob 몸. (epic)
function gureum() {
  const h = 205, body = `url(#grad_gureum)`, ol = outlineOf(h);
  // 미니 무지개 (식별 소품)
  const arc = (r, col) =>
    `<path d="M ${256 - r} 188 A ${r} ${r} 0 0 1 ${256 + r} 188" fill="none" stroke="${col}" stroke-width="11"/>`;
  return svgDoc(
    arc(96, '#F2A0A8') + arc(82, '#F5C97A') + arc(68, '#A8D8C0') +
    // 무지개 끝 작은 구름
    `<path d="${cloudBlob(160, 192, 34, 22, 6)}" fill="#FFFFFF" stroke="${ol}" stroke-width="5"/>` +
    `<path d="${cloudBlob(352, 192, 34, 22, 6)}" fill="#FFFFFF" stroke="${ol}" stroke-width="5"/>` +
    // 뭉게 구름 몸
    `<path d="${cloudBlob(256, 332, 162, 116, 11)}" fill="${body}" stroke="${ol}" stroke-width="8"/>` +
    cellShade(256, 430, 138, h) +
    eye2(212, 322) + eye2(300, 322) + mouth(256, 352, 18) +
    blushGlow(180, 350, 17) + blushGlow(332, 350, 17),
    bodyGrad('gureum', h)
  );
}

// byeolttong — 유성 꼬리 별. 식별 소품: 뒤로 흐르는 빛꼬리 + 반짝. smoothStar. (legendary)
function byeolttong() {
  const h = 50, ol = outlineOf(h);
  return svgDoc(
    // 빛꼬리 (식별 소품): 별 뒤로 흐르는 그라데이션 띠
    `<path d="M 196 286 Q 60 360 36 470 Q 120 430 176 348 Z" fill="url(#tailGrad)" stroke="${ol}" stroke-width="6" opacity="0.92"/>` +
    `<path d="M 230 268 Q 120 320 92 414 Q 168 380 248 320 Z" fill="url(#tailGrad)" opacity="0.55"/>` +
    // 둥근 5뿔 별 몸
    `<path d="${smoothStar(286, 244, 158, 86, 5)}" fill="url(#grad_byeolttong)" stroke="${ol}" stroke-width="8"/>` +
    cellShade(286, 350, 110, h) +
    // 반짝
    sparkle(120, 150, 16, '#FFF3C4') + sparkle(420, 196, 13, '#FFF3C4') +
    sparkle(390, 380, 14, '#FFE9F2') +
    // 광택
    `<ellipse cx="246" cy="200" rx="56" ry="22" fill="#FFFFFF" opacity="0.22" transform="rotate(-14 246 200)"/>` +
    eye2(252, 246) + eye2(326, 246) + mouth(289, 278, 18) +
    blushGlow(220, 274, 15) + blushGlow(356, 274, 15),
    bodyGrad('byeolttong', h) +
    `<linearGradient id="tailGrad" x1="1" y1="0" x2="0" y2="1">` +
    `<stop offset="0" stop-color="${hslHex(h, 0.22, 0.86)}"/>` +
    `<stop offset="1" stop-color="${hslHex(h, 0.10, 0.97)}" stop-opacity="0"/></linearGradient>`
  );
}

const CHARACTERS = {
  moka, somsom, kongkong, ppiyak, doto, pudding,
  jiji, mongdang, latte, byeolgaru, buong, geumbung,
  // 신규 12종
  dorong, gosum, gaegul, ddalbang, sikppang,
  mongsong, dalbo, beoseot, jogyak,
  haedal, gureum, byeolttong,
};

// 모티프/id 금지어 검증용 메타 (DESIGN_SPEC §A 표 — 검증 로직이 참조).
const CHAR_MOTIFS = {
  moka: '머리에 새싹이 난 크림색 두더지',
  somsom: '구름 같은 아기 양',
  kongkong: '꼬투리 모자를 쓴 연두 완두콩',
  ppiyak: '알껍질 바지를 입은 노란 병아리',
  doto: '도토리 모자를 쓴 갈색 다람쥐',
  pudding: '카라멜 머리의 커스터드 푸딩',
  jiji: '분홍-하늘 투톤 지우개',
  mongdang: '연필심 머리의 몽당연필',
  latte: '등에 라떼아트 무늬가 있는 수달',
  byeolgaru: '파스텔 별사탕 요정',
  buong: '졸린 점눈의 보라 아기 부엉이',
  geumbung: '황금 붕어빵',
  dorong: '분홍 아홀로틀',
  gosum: '베이지 고슴도치',
  gaegul: '민트 개구리',
  ddalbang: '딸기우유 방울',
  sikppang: '식빵 고양이 한 조각',
  mongsong: '회색 물범',
  dalbo: '민들레 홀씨 요정',
  beoseot: '빨강 물방울 버섯',
  jogyak: '강가 조약돌 정령',
  haedal: '자수정 해마',
  gureum: '솜사탕 구름 정령',
  byeolttong: '유성 꼬리 별',
};

// IP·작가명 등 금지어 (docs/RISKS.md §8.1, CLAUDE.md §1). id·모티프와 대조.
const BANNED = [
  'chiikawa', 'ちいかわ', '치이카와', '농담곰', 'rilakkuma', '리락쿠마',
  'sanrio', '산리오', 'sumikko', '스밍코', 'molang', '몰랑',
  'pokemon', '포켓몬', 'pikachu', '피카츄', 'hello kitty', '헬로키티',
  'nagano', '나가노', 'kanahei', '카나헤이', 'gudetama', '구데타마',
  'cinnamoroll', '시나모롤', 'pompompurin', 'kuromi', '쿠로미',
];


// ── 생성 + 검증 ─────────────────────────────────────────────────────────────

// (a) 금지어 게이트: 모든 id·모티프 문자열을 BANNED 셋과 대조. 매칭 시 즉시 종료.
function assertNoBannedTerms() {
  const hits = [];
  for (const id of Object.keys(CHARACTERS)) {
    const hay = `${id} ${CHAR_MOTIFS[id] || ''}`.toLowerCase();
    for (const term of BANNED) {
      if (hay.includes(term.toLowerCase())) hits.push(`${id}: "${term}"`);
    }
  }
  if (hits.length) {
    console.error(`✗ 금지어 검출 — IP/작가명 사용 불가:\n  ${hits.join('\n  ')}`);
    process.exit(1);
  }
  console.log(`✓ 금지어 0 (id·모티프 ${Object.keys(CHARACTERS).length}종 × ${BANNED.length}어 대조)`);
}

// (b) 컨택트시트: 24종 PNG를 6×4 그리드 한 장으로 합성 (육안 중복 확인용).
async function buildContactSheet() {
  const ids = Object.keys(CHARACTERS);
  const cols = 6, rows = Math.ceil(ids.length / cols), cell = 256, pad = 8;
  const W = cols * cell, H = rows * cell;
  const composites = [];
  for (let i = 0; i < ids.length; i++) {
    const svg = CHARACTERS[ids[i]]();
    const thumb = await sharp(Buffer.from(svg))
      .resize(cell - pad * 2, cell - pad * 2, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png().toBuffer();
    composites.push({
      input: thumb,
      left: (i % cols) * cell + pad,
      top: Math.floor(i / cols) * cell + pad,
    });
  }
  const out = join(OUT_DIR, '_contactsheet.png');
  await sharp({ create: { width: W, height: H, channels: 4, background: { r: 250, g: 244, b: 232, alpha: 1 } } })
    .composite(composites).png().toFile(out);
  console.log(`✓ contact sheet → ${out}  (${cols}×${rows}, ${ids.length}종)`);
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  // 어떤 모드든 먼저 금지어 게이트를 통과해야 한다.
  assertNoBannedTerms();

  if (process.argv.includes('--sheet')) {
    await buildContactSheet();
    return;
  }

  const only = new Set(process.argv.slice(2).filter((a) => !a.startsWith('--')));
  const ids = Object.keys(CHARACTERS).filter((id) => !only.size || only.has(id));
  if (!ids.length) {
    console.error(`No match. Known ids: ${Object.keys(CHARACTERS).join(', ')}`);
    process.exit(1);
  }

  let bad = 0;
  for (const id of ids) {
    const svg = CHARACTERS[id]();
    const buf = await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
    const file = join(OUT_DIR, `${id}.png`);
    await writeFile(file, buf);

    // 검증: 크기 512², 1KB 이상, 네 모서리 투명.
    const { data, info } = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const a = (x, y) => data[(y * info.width + x) * 4 + 3];
    const corners = [a(2, 2), a(509, 2), a(2, 509), a(509, 509)];
    const okSize = info.width === 512 && info.height === 512;
    const okBytes = buf.length >= 1024;
    const okAlpha = corners.every((v) => v === 0);
    const ok = okSize && okBytes && okAlpha;
    if (!ok) bad++;
    console.log(
      `${ok ? '✓' : '✗'} ${id}.png  ${(buf.length / 1024).toFixed(1)} KB  ` +
      `${info.width}×${info.height}  corners-alpha=[${corners.join(',')}]`
    );
  }
  console.log(`\nDone: ${ids.length} sprite(s), ${bad} failed check(s).`);
  if (bad) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
