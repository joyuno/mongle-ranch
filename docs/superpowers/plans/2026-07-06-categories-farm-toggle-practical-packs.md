# Categories UI + Farm Toggle + Practical Packs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add category tab-bar + search/filter to both games' pack pickers, a default-OFF farm(목장) toggle in mongle-ranch, and pilot practical-reference quiz packs (6 domains).

**Architecture:** New non-breaking `meta.category` field drives a pure `PackFilter` helper (per repo) consumed by each game's picker; farm visibility is a `ProgressStore` boolean pref mirroring `quietMode`; new packs are authored by a per-domain research→author→verify subagent workflow, with Logpresso packs kept local-only (gitignored).

**Tech Stack:** Godot 4.6.2 GDScript; node (build-time data migration); Workflow tool + exa MCP (pack research). No C#, no runtime LLM/image calls.

## Global Constraints

- Godot 4.6.2 stable, GDScript only. No C#.
- `RichTextLabel.bbcode_enabled = false` always.
- No runtime image/LLM API calls (generation is build-time only, human-reviewed).
- No specific kawaii-IP or other IP names anywhere.
- Parity across both games: `study_game_v2` (mongle-ranch, `joyuno/mongle-ranch`) and `study_game_godot` (`joyuno/studyandgame-godot`).
- Domain code (`scripts/domain/`) = pure functions, no Node/Scene refs.
- `ProgressStore` writes = atomic (tmp→rename) + clamp on load.
- Logpresso packs + any `*.pdf` = LOCAL-ONLY, never committed (already gitignored).
- Commit trailers per CLAUDE.md §5; commits separated by concern; push only after user approval.
- Category keys/order (verbatim): `japanese`(일본어), `semiconductor`(반도체), `observability`(관측성), `clickhouse`(ClickHouse), `data-eng`(데이터 엔지니어), `ai-eng`(AI 엔지니어), `backend`(백엔드), `linux`(Linux), `logpresso`(Logpresso).

**Godot test command (each game):** `Godot --headless --path . --script res://tests/test_runner.gd`
Godot binary: `C:/Users/admin/Downloads/all_project/godot/Godot_v4.6.2-stable_win64.exe`

---

## File Structure

**mongle-ranch (study_game_v2):**
- Create `scripts/domain/pack_filter.gd` — pure category/search matching + category catalog.
- Modify `scripts/autoload/progress_store.gd` — `showFarm` pref (getter/setter/signal/default).
- Modify `scripts/ui/settings.gd` — "목장 표시" CheckButton.
- Modify `scripts/ui/ranch.gd` — OFF state (hide `_yard`, show "퀴즈 시작" CTA), live toggle.
- Modify `scripts/ui/quiz.gd` — chip bar + search + meta cache + filter in `_populate_pack_list`.
- Modify `tests/test_runner.gd` — PackFilter + showFarm cases.
- Data: `data/quizzes/*.json` — add `meta.category` (migration).

**studyandgame-godot (study_game_godot):**
- Create `scripts/domain/pack_filter.gd` — identical pure helper.
- Modify `scripts/ui/home.gd` — chip bar + search + filter.
- Modify `tests/test_runner.gd` — PackFilter cases.
- Data: `data/quizzes/*.json` + `*.yml` — add `meta.category`.

**Both (Part C, local build-time):**
- `scripts/*.mjs` or scratchpad migration/scan scripts (not shipped).
- New packs `data/quizzes/{ai-eng,data-eng,backend,linux}-*.json` (public) and `logpresso-*.json` (local-only, gitignored).

---

## PHASE B — Farm(목장) on/off toggle (mongle-ranch only)

### Task B1: `showFarm` preference in ProgressStore

**Files:**
- Modify: `scripts/autoload/progress_store.gd` (signal near :20; getter near :134; setter in Settings region :621-643; default in `_default_progress()` :773-798)
- Test: `tests/test_runner.gd`

**Interfaces:**
- Produces: `ProgressStore.is_farm_visible() -> bool` (default `false`), `ProgressStore.set_farm_visible(enabled: bool) -> void`, `signal farm_visible_changed(enabled: bool)`.

- [ ] **Step 1: Write the failing test** — add to `tests/test_runner.gd` in a new `[Settings]` block:

```gdscript
# --- Farm visibility pref ---
ProgressStore.set_farm_visible(false)
_check("목장 기본 OFF", ProgressStore.is_farm_visible() == false)
ProgressStore.set_farm_visible(true)
_check("목장 setter ON", ProgressStore.is_farm_visible() == true)
ProgressStore.set_farm_visible(false)  # restore
```
(Use the file's existing assertion helper — match the name already used, e.g. `_check`/`_expect`/`_assert`. Grep the file first.)

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot --headless --path . --script res://tests/test_runner.gd`
Expected: FAIL — `is_farm_visible`/`set_farm_visible` not found (parse or runtime error).

- [ ] **Step 3: Implement the pref** (mirror `quietMode`)

Signal (near existing `signal quiet_mode_changed`):
```gdscript
signal farm_visible_changed(enabled: bool)
```
Getter (near `is_quiet_mode`):
```gdscript
func is_farm_visible() -> bool:
	return bool(progress.get("showFarm", false))
```
Setter (in the Settings region near `set_quiet_mode`):
```gdscript
func set_farm_visible(enabled: bool) -> void:
	progress["showFarm"] = enabled
	_persist()
	farm_visible_changed.emit(enabled)
```
Default (in `_default_progress()` dict):
```gdscript
	"showFarm": false,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot --headless --path . --script res://tests/test_runner.gd`
Expected: PASS — all prior cases still pass + 3 new.

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/progress_store.gd tests/test_runner.gd
git commit -m "feat(ranch): add showFarm pref (default off) in ProgressStore"
```

### Task B2: "목장 표시" toggle in Settings

**Files:**
- Modify: `scripts/ui/settings.gd` (퀴즈 환경 section, near the quiet-mode CheckButton :132-136)

**Interfaces:**
- Consumes: `ProgressStore.is_farm_visible()`, `set_farm_visible()`.

- [ ] **Step 1: Add the CheckButton** (copy the quiet-mode toggle pattern in the same section)

```gdscript
var farm_toggle := CheckButton.new()
farm_toggle.text = "목장 표시 (끄면 회사에서 쓰기 좋은 차분한 화면)"
farm_toggle.set_pressed_no_signal(ProgressStore.is_farm_visible())
farm_toggle.toggled.connect(func(on: bool) -> void: ProgressStore.set_farm_visible(on))
# add to the same container the quiet-mode CheckButton is added to (match that line)
```

- [ ] **Step 2: Verify boot + no parse error**

Run: `Godot --headless --path . --script res://tests/test_runner.gd`
Expected: PASS (settings.gd compiles project-wide).

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/settings.gd
git commit -m "feat(settings): 목장 표시 toggle (default off)"
```

### Task B3: Ranch OFF state — hide `_yard`, show "퀴즈 시작" CTA, live toggle

**Files:**
- Modify: `scripts/ui/ranch.gd` (`_build_layout` :69-135; guards at `_ready` deferred :58-63, `_on_collection_changed` :478, `_apply_daylight` :339)

**Interfaces:**
- Consumes: `ProgressStore.is_farm_visible()`, `farm_visible_changed`.

- [ ] **Step 1: Build a CTA panel helper** — add to ranch.gd:

```gdscript
# 목장 OFF일 때 _yard 대신 보여줄 최소 화면: 단색 배경 + "퀴즈 시작" 버튼 하나.
func _build_quiz_cta() -> Control:
	var panel := Panel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var btn := Button.new()
	btn.text = "퀴즈 시작"
	btn.custom_minimum_size = Vector2(240, 72)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/Quiz.tscn"))
	center.add_child(btn)
	return panel
```
(Confirm the quiz scene path from the existing nav "퀴즈" handler at ranch.gd:15 — use whatever that handler navigates to; do not hardcode a wrong path.)

- [ ] **Step 2: Branch `_build_layout` on visibility**

In `_build_layout`, where `_yard` is created/added (:101-109), gate it:
```gdscript
if ProgressStore.is_farm_visible():
	# ... existing _yard construction + add to VBox ...
	_yard_active = true
else:
	var cta := _build_quiz_cta()
	main_vbox.add_child(cta)   # same VBox _yard was added to
	_cta_node = cta
	_yard_active = false
```
Add members: `var _yard_active := false`, `var _cta_node: Control = null`.

- [ ] **Step 3: Guard farm-only work** — wrap the `_ready` deferred block (:58-63 calling `_place_decor()`/`_rebuild_sprites()`), `_on_collection_changed` (:478), and `_apply_daylight` (:339) bodies in `if ProgressStore.is_farm_visible(): ...` (early-return if off) so pets/decor/daylight aren't computed when hidden.

- [ ] **Step 4: Live toggle without reload** — in `_ready`, connect:

```gdscript
ProgressStore.farm_visible_changed.connect(_on_farm_visible_changed)
```
Handler:
```gdscript
func _on_farm_visible_changed(_enabled: bool) -> void:
	# rebuild the middle region: teardown current, re-run layout branch
	for c in main_vbox.get_children():
		if c == _yard or c == _cta_node:
			c.queue_free()
	_yard = null
	_cta_node = null
	# re-add whichever branch applies (extract the Step-2 branch into a helper _mount_center())
```
Refactor the Step-2 branch into `_mount_center()` and call it from both `_build_layout` and the handler (DRY).

- [ ] **Step 5: Verify boot both states**

Run tests (must stay green): `Godot --headless --path . --script res://tests/test_runner.gd`
Then a headless boot smoke check for ranch.gd parse/compile:
```bash
Godot --headless --path . --check-only --script res://scripts/ui/ranch.gd 2>&1 | grep -iE "error|parse" || echo "clean"
```
Expected: no ranch.gd-specific parse errors (autoload "not found" lines from isolated load are OK; a real syntax error in the new code is not).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/ranch.gd
git commit -m "feat(ranch): OFF state shows clean bg + 퀴즈 시작 CTA; live farm toggle"
```

---

## PHASE A-data — `meta.category` migration (both games)

### Task A1: Add `category` to every bundled pack

**Files:**
- Create (scratchpad, not shipped): a node migration script.
- Modify: mongle-ranch `data/quizzes/*.json` (68) ; studyandgame-godot `data/quizzes/*.json` (29) + `*.yml` (30).

**Interfaces:**
- Produces: every bundled pack's `meta.category` ∈ the 9 category keys.

- [ ] **Step 1: Write the migration mapping** (node, in scratchpad). Rules (apply to each pack's `meta`, only if `category` absent):

```js
function categoryFor(file, meta){
  const tags = (meta.tags||[]).map(t=>String(t).toLowerCase());
  const name = file.toLowerCase();
  if (tags.includes('jlpt') || name.startsWith('jlpt-')) return 'japanese';
  if (tags.includes('semiconductor') || /^(semiconductor|memory|physical-electronics|reliability-fa|spc-yield)/.test(name)) return 'semiconductor';
  if (tags.includes('observability') || /^(apm|otel|rum)/.test(name)) return 'observability';
  if (tags.includes('clickhouse') || name.startsWith('clickhouse')) return 'clickhouse';
  return null; // leave unset; flag for manual
}
```

- [ ] **Step 2: Apply to mongle-ranch `.json`** — for each file, parse, set `meta.category` if mapping non-null, else print WARN. Rebuild from the parsed object preserving all other fields (mirror the JLPT-enrichment normalize approach: `JSON.stringify(obj,null,2)+"\n"`). Print a table of file→category; assert 0 WARN (every bundled pack must map). Fix any WARN by hand.

- [ ] **Step 3: Verify mongle-ranch — only `meta.category` added vs HEAD**

```bash
git --no-pager diff -U0 data/quizzes/ | grep -E '^[+-]' | grep -vE '^[+-]{3}' | grep -vcE '"category"'
```
Expected: `0` (no non-category lines changed).
Then headless full-parse (reuse the Phase-earlier parse check): all packs parse, 0 failures.

- [ ] **Step 4: Apply to studyandgame-godot** — `.json` via the same node script; `.yml` via a YAML-safe insert: add `  category: <key>` under each pack's top-level `meta:` mapping (2-space indent, as a plain scalar). Verify via `YAMLPackParser`/`PackParser` headless that all `.yml` still parse AND `meta.category` reads back correctly. Confirm diff touches only category lines.

- [ ] **Step 5: Commit (each repo)**

```bash
# mongle-ranch
git add data/quizzes && git commit -m "data: add meta.category to all bundled packs (migration)"
# studyandgame-godot
git add data/quizzes && git commit -m "data: add meta.category to all bundled packs (.json+.yml)"
```

---

## PHASE A-ui — Category chip bar + search + filter (both games)

### Task A2: `PackFilter` pure helper + tests (both repos)

**Files:**
- Create: `scripts/domain/pack_filter.gd` (each repo, identical)
- Test: `tests/test_runner.gd` (each repo)

**Interfaces:**
- Produces: `PackFilter.CATEGORIES: Array` (ordered `{key,name}`), `PackFilter.category_of(meta: Dictionary) -> String`, `PackFilter.matches(meta: Dictionary, category: String, query: String) -> bool`.

- [ ] **Step 1: Write failing tests** in `tests/test_runner.gd` (`[PackFilter]` block):

```gdscript
var m_jp := {"title":"JLPT N2 문법","tags":["jlpt","n2"],"category":"japanese"}
var m_semi := {"title":"반도체공정 1","tags":["engineering","semiconductor"]}  # no category → fallback
_check("category_of explicit", PackFilter.category_of(m_jp) == "japanese")
_check("category_of fallback", PackFilter.category_of(m_semi) == "semiconductor")
_check("matches all cat", PackFilter.matches(m_jp, "", "") == true)
_check("matches cat hit", PackFilter.matches(m_jp, "japanese", "") == true)
_check("matches cat miss", PackFilter.matches(m_jp, "backend", "") == false)
_check("matches query hit", PackFilter.matches(m_jp, "", "문법") == true)
_check("matches query miss", PackFilter.matches(m_jp, "", "clickhouse") == false)
_check("matches query case-insensitive", PackFilter.matches({"title":"ClickHouse Basics","tags":["clickhouse"]}, "", "click") == true)
```

- [ ] **Step 2: Run — verify fail**

Run: `Godot --headless --path . --script res://tests/test_runner.gd`
Expected: FAIL — `PackFilter` not found.

- [ ] **Step 3: Implement `scripts/domain/pack_filter.gd`**

```gdscript
# 퀴즈 팩 카테고리 분류 + 검색 매칭. 순수 함수 (Node/Scene 참조 없음).
class_name PackFilter
extends RefCounted

# 표시 순서 고정. 신규 카테고리는 여기에 추가.
const CATEGORIES: Array = [
	{"key": "japanese", "name": "일본어"},
	{"key": "semiconductor", "name": "반도체"},
	{"key": "observability", "name": "관측성"},
	{"key": "clickhouse", "name": "ClickHouse"},
	{"key": "data-eng", "name": "데이터 엔지니어"},
	{"key": "ai-eng", "name": "AI 엔지니어"},
	{"key": "backend", "name": "백엔드"},
	{"key": "linux", "name": "Linux"},
	{"key": "logpresso", "name": "Logpresso"},
]

static func _hay(meta: Dictionary) -> String:
	var s := String(meta.get("title", ""))
	for t in meta.get("tags", []):
		s += " " + String(t)
	return s.to_lower()

# meta.category가 있으면 그것을, 없으면 키워드 버킷(유저 임포트 폴백). "" = 미분류.
static func category_of(meta: Dictionary) -> String:
	var c := String(meta.get("category", "")).strip_edges()
	if not c.is_empty():
		return c
	var h := _hay(meta)
	if h.contains("jlpt") or h.contains("일본어") or h.contains("japanese"): return "japanese"
	if h.contains("semiconductor") or h.contains("반도체"): return "semiconductor"
	if h.contains("observability") or h.contains("otel") or h.contains("opentelemetry") or h.contains("apm") or h.contains("rum"): return "observability"
	if h.contains("clickhouse"): return "clickhouse"
	if h.contains("logpresso"): return "logpresso"
	if h.contains("linux"): return "linux"
	return ""

# category "" = 전체, query "" = 아무거나. 둘은 AND.
static func matches(meta: Dictionary, category: String, query: String) -> bool:
	if not category.is_empty() and category_of(meta) != category:
		return false
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return true
	return _hay(meta).contains(q)
```

- [ ] **Step 4: Run — verify pass** (both repos)

Run: `Godot --headless --path . --script res://tests/test_runner.gd`
Expected: PASS.

- [ ] **Step 5: Commit (each repo)**

```bash
git add scripts/domain/pack_filter.gd tests/test_runner.gd
git commit -m "feat(domain): PackFilter — category classification + search matching"
```

### Task A3: mongle-ranch picker — cache metas, chip bar, filter

**Files:**
- Modify: `scripts/ui/quiz.gd` (`_build_pack_select` :131-182 to insert filter bar; `_populate_pack_list` :185-212 to cache+filter)

**Interfaces:**
- Consumes: `PackFilter.CATEGORIES`, `PackFilter.matches`, existing `_make_pack_card`, `_make_create_entry`.

- [ ] **Step 1: Add member state + cache struct**

```gdscript
var _pack_cache: Array = []          # [{path, file, meta, count, is_user}]
var _active_category: String = ""
var _search_query: String = ""
var _chip_row: HBoxContainer
var _search_edit: LineEdit
```

- [ ] **Step 2: Build cache once** — refactor `_populate_pack_list` so parsing populates `_pack_cache` (only when empty or after a user-import invalidation); factor the current per-file parse loop (:196-211) into `_rebuild_pack_cache()` that appends `{path,file,meta,count,is_user}` for each valid pack (user packs first, then bundled — preserve current order). Add `_invalidate_pack_cache()` (clears cache) and call it wherever user packs can change (e.g. return from CreatePack).

- [ ] **Step 3: Insert filter bar UI** — between the `hint` label (:161) and `ScrollContainer` (:169) add:

```gdscript
_search_edit = LineEdit.new()
_search_edit.placeholder_text = "검색: 제목·태그…"
_search_edit.clear_button_enabled = true
_search_edit.text_changed.connect(func(t: String) -> void: _search_query = t; _apply_filter())
pack_root.add_child(_search_edit)   # match the actual VBox var name in _build_pack_select

var chip_scroll := ScrollContainer.new()
chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
chip_scroll.custom_minimum_size.y = 44
_chip_row = HBoxContainer.new()
chip_scroll.add_child(_chip_row)
pack_root.add_child(chip_scroll)
```

- [ ] **Step 4: Build chips from non-empty categories + counts**

```gdscript
func _rebuild_chips() -> void:
	for c in _chip_row.get_children():
		c.queue_free()
	var counts := {}
	for e in _pack_cache:
		var k := PackFilter.category_of(e.meta)
		counts[k] = int(counts.get(k, 0)) + 1
	_add_chip("전체", "", _pack_cache.size())
	for cat in PackFilter.CATEGORIES:
		var n := int(counts.get(cat.key, 0))
		if n > 0:
			_add_chip(cat.name, cat.key, n)

func _add_chip(label: String, key: String, n: int) -> void:
	var b := Button.new()
	b.text = "%s %d" % [label, n]
	b.toggle_mode = true
	b.button_pressed = (_active_category == key)
	b.pressed.connect(func() -> void: _active_category = key; _apply_filter(); _sync_chip_pressed())
	_chip_row.add_child(b)
```
(`_sync_chip_pressed()` sets each chip's `button_pressed` to `_active_category == its key` so only the active one shows selected.)

- [ ] **Step 5: Apply filter (rebuild list from cache)**

```gdscript
func _apply_filter() -> void:
	_clear_children(pack_list_box)
	pack_list_box.add_child(_make_create_entry())   # keep the top "내 문제집 만들기" entry
	var shown := 0
	for e in _pack_cache:
		if PackFilter.matches(e.meta, _active_category, _search_query):
			pack_list_box.add_child(_make_pack_card(e))  # adapt _make_pack_card to take the cache entry, or its existing args
			shown += 1
	pack_status_label.text = "%d개 팩" % shown if shown > 0 else "일치하는 팩이 없어요"
```
Replace the tail of `_populate_pack_list` (currently loops+adds cards) with: `_rebuild_pack_cache()` (if needed) → `_rebuild_chips()` → `_apply_filter()`.

- [ ] **Step 6: Verify** — tests green; headless boot; and a headless assertion that filtering a known category yields the expected count (add a small `[Picker]` test only if `_make_pack_card` is decoupled enough; otherwise rely on PackFilter unit tests + manual). Run:

```bash
Godot --headless --path . --script res://tests/test_runner.gd
Godot --headless --path . --check-only --script res://scripts/ui/quiz.gd 2>&1 | grep -iE "parse error" || echo "clean"
```

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/quiz.gd
git commit -m "feat(quiz): category chip bar + search filter + parsed-meta cache"
```

### Task A4: studyandgame-godot picker — chip bar + search + filter

**Files:**
- Modify: `scripts/ui/home.gd` (pack scan :213-235; `.yml`-wins dedup preserved)

**Interfaces:**
- Consumes: `PackFilter` (Task A2 copy in this repo).

- [ ] **Step 1: Cache scanned pack metas** — the scan (:213-235) already builds `[{title,path,file}]`; extend each entry with the parsed `meta` (parse once here) so filtering doesn't re-scan. Preserve the `.yml`-over-`.json` dedup.
- [ ] **Step 2: Add the same filter bar** (search LineEdit + chip ScrollContainer/HBox) above the pack list container in `home.gd`'s layout builder. Reuse the Task-A3 chip/apply logic, adapted to home.gd's list container + row-builder function names.
- [ ] **Step 3: Filter** using `PackFilter.matches(entry.meta, _active_category, _search_query)`; rebuild the list rows from the cached entries.
- [ ] **Step 4: Verify** — `Godot --headless --path . --script res://tests/test_runner.gd` green; boot check clean.
- [ ] **Step 5: Commit**

```bash
git add scripts/ui/home.gd
git commit -m "feat(home): category chip bar + search filter in pack picker"
```

---

## PHASE C — Practical-reference pack pilot (research → author → verify)

This phase is executed by a **subagent workflow**, not TDD steps. Deliverable: 6 validated packs.

### Task C1: Per-domain research → author → verify workflow

**Domains (6):** `ai-eng`, `data-eng`, `backend`, `linux` (public) ; `logpresso-sql`, `logpresso-install` (LOCAL-ONLY).

Per-domain pipeline (Workflow tool, fan-out):
- **Researcher:** exa `web_search_exa` + `web_fetch_exa` on official docs/reputable sources → grounded reference brief (concepts, real-world pitfalls, best practices) with source URLs. For `logpresso-install`: source = the extracted PDF text in scratchpad (`logpresso_install.txt`), NOT the web. For `logpresso-sql`: official Logpresso query-language docs.
- **Author:** write a ~30-question (`linux` ~35-40) pack, schema-exact:
  `{meta:{title,version,default_time,tags,category}, questions:[{type,q,choices,answer,glossary,explanation,tags}]}`.
  Hard requirements: EVERY question has a non-empty `glossary` (term｜읽기/원어｜뜻 cards) AND an `explanation` that says why the answer is right AND why each distractor is wrong (quote choices in 「」, never bare ordinals). Practical/실무 중급~고급 framing.
- **Verifier:** adversarially fact-check each claim against the researcher's sources; then validate the file via `PackParser.parse_file` headless. Reject/fix unsupported claims.

- [ ] **Step 1:** Launch the workflow (author packs to `data/quizzes/<domain>.json` in mongle-ranch working dir).
- [ ] **Step 2:** For each pack, headless-validate via PackParser (0 failures) and confirm glossary+explanation present on every question.

### Task C2: Logpresso sanitization gate (BLOCKING for logpresso packs)

- [ ] **Step 1:** Scan both logpresso packs for confidential leakage — must be **0 matches**:

```bash
node -e 'const d=require("./data/quizzes/logpresso-install.json");const s=JSON.stringify(d);
const bad=[/예금보험공사/,/mariadb1!/,/logpresso1!/,/araqne(?![a-z])/i,/192\.168\.\d+\.\d+/,/곽영효/,/테라시스/,/㊙/];
const hits=bad.filter(re=>re.test(s)); console.log(hits.length? "LEAK: "+hits: "clean");'
```
(Repeat for `logpresso-sql.json`.) If any hit → Author removes it (teach the concept, not the secret), re-verify.

- [ ] **Step 2:** Confirm no Logpresso-specific commands leaked into the PUBLIC `linux` pack:

```bash
node -e 'const s=JSON.stringify(require("./data/quizzes/linux.json"));console.log(/sonar\.|araqne|logpresso\./i.test(s)?"LEAK":"clean");'
```

### Task C3: Placement + gitignore (public vs local-only)

- [ ] **Step 1:** Add local-only rule to `.gitignore` (both repos):
```
# Local-only practical packs (internal source) — never publish.
data/quizzes/logpresso-*.json
```
- [ ] **Step 2:** Verify `git check-ignore data/quizzes/logpresso-install.json` → ignored.
- [ ] **Step 3:** Copy the 4 public packs + set `category`; copy logpresso packs (gitignored) into both games' `data/quizzes/` (studyandgame-godot: `.json` only — `.yml`-wins rule means no dup).
- [ ] **Step 4:** Full headless pack-parse both games (0 failures). Confirm new categories' chips now appear.
- [ ] **Step 5: Commit public packs only**

```bash
git add data/quizzes/ai-eng.json data/quizzes/data-eng.json data/quizzes/backend.json data/quizzes/linux.json .gitignore
git commit -m "feat(packs): pilot practical-reference packs — AI/data/backend/linux"
git status --porcelain data/quizzes/logpresso-*.json   # expect empty (ignored)
```

### Task C4: Quality gate (before expansion)

- [ ] Present the 6 packs' summary + sample questions to the user for accuracy review. Expansion (multiple packs per domain) is a SEPARATE cycle after approval.

---

## FINAL — exe rebuild + push (after user approval)

- [ ] Rebuild both exes (mongle-ranch single-file; studyandgame-godot exe+pck) — logpresso packs are gitignored but still export into the LOCAL exe via include_filter.
- [ ] Confirm logpresso packs are IN the local exe (user can play) but NOT in git (`git ls-files | grep logpresso` → empty).
- [ ] Push all repos (mongle-ranch, studyandgame-godot) — **user approval required** (§4). Never push logpresso data.

---

## Self-Review

**Spec coverage:** Part A (taxonomy §0 → A1; UI §A → A2/A3/A4) ✓; Part B (§B → B1/B2/B3) ✓; Part C (§C → C1/C2/C3/C4, incl. Linux pack + confidentiality gate) ✓; both-games parity ✓; local-only logpresso ✓.
**Placeholder scan:** code shown for all pure units (PackFilter, ProgressStore, migration, sanitize scan); UI tasks reference exact files/lines + give key snippets (large existing methods are edited, not reproduced — implementer has the file). No "TBD"/"handle edge cases".
**Type consistency:** `is_farm_visible`/`set_farm_visible`/`farm_visible_changed` consistent across B1-B3; `PackFilter.category_of`/`matches`/`CATEGORIES` consistent across A2-A4; cache entry shape `{path,file,meta,count,is_user}` consistent A3.
**Known judgment calls to confirm during execution:** exact VBox/list-container var names in `quiz.gd`/`home.gd` (grep before editing); the assertion helper name in each `test_runner.gd`; the quiz-scene path for the CTA button.
