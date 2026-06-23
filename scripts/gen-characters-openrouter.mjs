// gen-characters-openrouter.mjs — 몽글목장 캐릭터 12종 AI 아트 빌드타임 파이프라인.
//
// ⚠ 빌드타임 전용. 런타임 게임 코드에서 절대 호출하지 않는다 (docs/RISKS.md
//   security §"AI 이미지 생성 런타임 호출" 참조). 생성물은 반드시 사람 검수
//   (기존 IP 주요 캐릭터와 나란히 놓고 유사성 육안 대조 — docs/ASSETS.md
//   체크리스트) 후에만 커밋한다.
//
// 현재 출하 에셋은 scripts/gen-placeholders.mjs 의 절차적 SVG다. 이 스크립트는
// 향후 AI 아트로 교체할 때를 위한 준비물이며, 의도적으로 어떤 자동 빌드에도
// 연결되어 있지 않다. 수동으로만 실행한다.
//
// 패턴 출처: study_game_godot/scripts/gen-swords-openrouter.mjs (OpenRouter
// chat/completions + image modality + 마젠타 크로마키 후처리).
// 마젠타 크로마키인 이유: 캐릭터 몸이 파스텔(크림/흰색 포함)이라 흰배경
// flood-fill은 몸 내부의 밝은 픽셀을 같이 날린다(docs/RISKS.md feasibility).
// 실측상 이미지 모델은 "투명 배경" 요구를 무시하고 단색을 깔기 때문에,
// 팔레트에 없는 채도 최대 마젠타(#FF00FF)를 지정해 정확히 그 색만 벗긴다.
//
// 비용: 약 $0.04/장 × 12 = 풀 재생성 1회당 ~$0.5 (2026-05 OpenRouter 기준).
//
// 사용법:
//   node scripts/gen-characters-openrouter.mjs            # 12종 전부
//   node scripts/gen-characters-openrouter.mjs moka doto  # 일부만
//
// 요구사항: ../.env 에 OPENROUTER_API_KEY (자동 로드, dotenv 불필요).
// .env는 절대 커밋하지 않는다 (.gitignore 선행 확인 — docs/RISKS.md).

import { writeFile, mkdir, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');
const ENV_PATH = join(PROJECT_ROOT, '.env');
const OUT_DIR = join(PROJECT_ROOT, 'assets', 'characters');

const MODEL = 'google/gemini-2.5-flash-image';
const ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions';

// 공통 스타일 블록 — docs/GAME_DESIGN.md §4 아트 바이블의 프롬프트 고정 상수.
// 일반 기술어만 사용한다. 작품명·작가명·캐릭터명은 어떤 경우에도 넣지 않는다
// (의거성 추정 — docs/RISKS.md copyright). 배경은 크로마키용 단색 마젠타.
const STYLE = [
  'kawaii minimal mascot, round chibi body, two dot eyes, tiny mouth,',
  'pink blush, soft pastel flat colors, thick clean dark outline,',
  'full body, centered, two heads tall proportions, short stubby limbs,',
  'gentle slightly wistful expression, no gradients except where described,',
  'solid #FF00FF magenta background — the entire background must be one flat',
  'fully saturated neon magenta (RGB 255,0,255), no pastel pink background,',
  'no gradient, no shadow on the ground, no text, no watermark, no border.',
  'Do not use magenta or pink tones on the character body itself.',
].join(' ');

// 캐릭터별 모티프 (영어, 일반 기술어만). seed 고정 → 재현 가능한 재생성.
const CHARACTERS = [
  { id: 'moka',      seed: 101, desc: 'a cream-colored mole with a tiny green sprout growing from the top of its head, big soft digging paws, light oval muzzle with a small pink nose' },
  { id: 'somsom',    seed: 102, desc: 'a baby sheep whose ivory wool forms a fluffy cloud-like scalloped outline, beige face patch, droopy little ears, short beige legs' },
  { id: 'kongkong',  seed: 103, desc: 'a light yellow-green pea wearing a green pea-pod hood as a hat with a wavy brim and a small curly stem on top, round bean body' },
  { id: 'ppiyak',    seed: 104, desc: 'a pale yellow baby chick wearing the lower half of a cracked white eggshell like pants, zigzag shell rim across its belly, tiny diamond orange beak, small wing stubs' },
  { id: 'doto',      seed: 105, desc: 'a light brown squirrel wearing an acorn cap as a beret with a short stem, big curled fluffy tail behind, lighter belly' },
  { id: 'pudding',   seed: 106, desc: 'a custard pudding creature shaped like a flan with a rounded top, glossy caramel layer dripping over its head like hair, sleepy relaxed face on the custard body' },
  { id: 'jiji',      seed: 107, desc: 'a rounded rectangular eraser creature, two-tone body with a soft pink upper half and a sky blue lower half separated by a clean seam line, shy tiny mouth' },
  { id: 'mongdang',  seed: 108, desc: 'a short stubby pencil creature, pastel yellow hexagonal barrel body, sharpened wooden cone top with a dark graphite tip as a pointy hat, rounded bottom' },
  { id: 'latte',     seed: 109, desc: 'a warm brown otter with a cream latte-foam belly patch decorated with a caramel latte-art rosetta leaf and heart pattern, small round ears, fine whiskers, tapered tail' },
  { id: 'byeolgaru', seed: 110, desc: 'a pastel lavender star-candy fairy, plump eight-pointed star-shaped sugar body with rounded bumpy points, a few tiny pale-yellow sparkles floating around it' },
  { id: 'buong',     seed: 111, desc: 'a pastel purple baby owl with short horn-like ear tufts angled outward, sleepy half-closed dot eyes, lighter belly with soft scalloped feather rows, tiny orange beak and feet' },
  { id: 'geumbung',  seed: 112, desc: 'a golden fish-shaped pastry, plump fish silhouette bread with a crisp waffle grid texture, forked tail fin and a small rounded dorsal fin, subtle golden sheen highlight' },
  // ── 확장 12종 (seeds 113–124) ────────────────────────────────────────────
  { id: 'dorong',    seed: 113, desc: 'a soft dusty-pink axolotl, three feathery frilly external gill branches fanning out from each side of its head, wide flat smiling muzzle, lighter belly, short stubby legs and a small rounded tail' },
  { id: 'gosum',     seed: 114, desc: 'a small beige hedgehog whose back is covered in rows of short rounded blunt quills like soft bumps, paler round face and tummy, tiny dark nose, little paws' },
  { id: 'gaegul',    seed: 115, desc: 'a dusty mint-green frog with two big round bulging eyes perched on top of its head, wide flat smiling mouth, paler creamy belly, short bent legs ready to hop' },
  { id: 'ddalbang',  seed: 116, desc: 'a rounded strawberry-milk droplet creature, soft pale pink teardrop body with a small green strawberry calyx and stem on top, faint scatter of tiny seed dots on its cheeks' },
  { id: 'sikppang',  seed: 117, desc: 'a single thick slice of white bread shaped like a cat, golden-tan crust running around its squared outline, two little crust-colored triangle ears on top, drowsy soft face' },
  { id: 'mongsong',  seed: 118, desc: 'a plump dove-grey baby seal, smooth rounded body with two short flat front flippers, fine whisker dots on a paler muzzle, big calm dark eyes, tiny stubby tail' },
  { id: 'dalbo',     seed: 119, desc: 'a tiny dandelion-seed sprite, pale cream fluffy round seed-head puff worn like a cap on top, slender beige stem body, a few loose wispy white seed tufts drifting beside it' },
  { id: 'beoseot',   seed: 120, desc: 'a small dusty-red toadstool, rounded domed cap dotted with soft cream spots worn over its head like a hat, short pale stout stalk body, little rounded base' },
  { id: 'jogyak',    seed: 121, desc: 'a smooth grey riverstone spirit, rounded pebble body with a small tuft of soft green moss growing on its crown, faint paler speckles, calm quiet face' },
  { id: 'haedal',    seed: 122, desc: 'a pastel amethyst-purple seahorse, curled spiral tail, small ridged dorsal fin along its back, gently arched snout, tiny bumpy crest ridge on its head' },
  { id: 'gureum',    seed: 123, desc: 'a fluffy cotton-candy cloud sprite, soft off-white scalloped puffy cloud body, a small pastel rainbow arc floating just above its head, gentle dreamy face' },
  { id: 'byeolttong', seed: 124, desc: 'a pastel falling-star creature, plump rounded five-pointed star body trailing a tapered soft glowing comet tail behind it, a couple of tiny sparkle dots in its wake' },
];

async function loadEnv() {
  let body;
  try { body = await readFile(ENV_PATH, 'utf8'); }
  catch { throw new Error(`Missing .env at ${ENV_PATH}`); }
  for (const line of body.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
  if (!process.env.OPENROUTER_API_KEY) {
    throw new Error('OPENROUTER_API_KEY not found in .env');
  }
}

function dataUrlToBuffer(url) {
  const m = url.match(/^data:image\/\w+;base64,(.+)$/);
  if (!m) throw new Error(`Not a base64 image data URL: ${url.slice(0, 80)}…`);
  return Buffer.from(m[1], 'base64');
}

// 마젠타 크로마키: 마젠타/핑크 계열 픽셀 → alpha 0.
// 모델은 #FF00FF 요구를 파스텔 핑크(r≈255, g 80-160, b 100-200)로 누그러뜨리는
// 경향이 있어 그 범위까지 잡되, 캐릭터의 분홍 볼터치(저채도, r-g 작음)는
// 살아남도록 r-g 점수 램프로 처리한다. 경계의 AA 프린지는 중간 램프가 죽인다.
async function chromaKeyMagenta(pngBuf) {
  const { data, info } = await sharp(pngBuf).ensureAlpha().raw()
    .toBuffer({ resolveWithObject: true });
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i + 1], b = data[i + 2];
    // 마젠타 계열 판정: R 높음, G가 R보다 확실히 낮음, B가 어느 정도 있음.
    // (금색/노랑은 g≈r라 제외, 주황은 b 낮아 제외, 순파랑은 r 낮아 제외)
    const valid = r >= 200 && g <= r - 40 && b >= 60 && b <= r + 20;
    if (!valid) continue;
    const score = r - g; // ~40(연분홍) → 255(순마젠타)
    if (score >= 140) {
      data[i + 3] = 0;
    } else {
      const t = (score - 40) / (140 - 40);
      data[i + 3] = Math.round(data[i + 3] * (1 - Math.max(0, t)));
    }
  }
  return sharp(data, {
    raw: { width: info.width, height: info.height, channels: 4 },
  }).resize(512, 512).png({ compressionLevel: 9 }).toBuffer();
}

async function generate({ desc, seed }) {
  const prompt = `${desc}. ${STYLE}`;
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
      'X-Title': 'mongle-ranch character sprites',
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [{ role: 'user', content: prompt }],
      modalities: ['image', 'text'],
      image_config: { aspect_ratio: '1:1' },
      seed,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`HTTP ${res.status}: ${text.slice(0, 400)}`);
  }
  const json = await res.json();
  const image = json?.choices?.[0]?.message?.images?.[0]?.image_url?.url;
  if (!image) {
    throw new Error(`No image in response. Body: ${JSON.stringify(json).slice(0, 500)}`);
  }
  return dataUrlToBuffer(image);
}

async function main() {
  await loadEnv();
  await mkdir(OUT_DIR, { recursive: true });

  const only = new Set(process.argv.slice(2));
  const targets = only.size ? CHARACTERS.filter((c) => only.has(c.id)) : CHARACTERS;
  if (!targets.length) {
    console.error(`No match. Known ids: ${CHARACTERS.map((c) => c.id).join(', ')}`);
    process.exit(1);
  }

  console.log(`Generating ${targets.length} character(s) via ${MODEL} [magenta chroma-key]`);
  console.log(`Output dir: ${OUT_DIR}`);
  console.log('생성 후 docs/ASSETS.md 검수 체크리스트를 통과해야 커밋 가능.\n');

  let ok = 0, fail = 0;
  for (const c of targets) {
    process.stdout.write(`→ ${c.id} (seed ${c.seed}) … `);
    try {
      let buf = await generate(c);
      buf = await chromaKeyMagenta(buf);
      await writeFile(join(OUT_DIR, `${c.id}.png`), buf);
      console.log(`✓ ${(buf.length / 1024).toFixed(1)} KB`);
      ok++;
    } catch (e) {
      console.log(`✗ ${e.message}`);
      fail++;
    }
    await new Promise((r) => setTimeout(r, 500)); // 공급자 측 부하 배려
  }
  console.log(`\nDone. ok=${ok} fail=${fail}.`);
  if (fail > 0) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
