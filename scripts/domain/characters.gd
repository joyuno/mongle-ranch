# Character roster — the 12 launch friends of 몽글목장.
# Pure data + lookup helpers. No Node references (headless-testable).
#
# Design source: docs/GAME_DESIGN.md §4. Weights follow the GitAnimals-style
# per-mille pool (weight × 1000 entries, uniform draw). Personality fields
# drive the ranch wander state machine — they are *presentation* hints, not
# stats; characters have no combat or ability numbers by design.

class_name Characters
extends RefCounted

const RARITY_ORDER: Array[String] = ["common", "rare", "epic", "legendary"]

const RARITY_LABEL_KO: Dictionary = {
	"common": "일반",
	"rare": "레어",
	"epic": "에픽",
	"legendary": "레전더리",
}

# Personality field reference:
#   move_speed   px/sec while walking
#   idle_min/max seconds between actions
#   sleep_chance probability an action roll becomes a nap
#   night_owl    true → active at night, sleepy at day (별가루/부엉)
#   follower     true → walks toward the nearest other character (삐약)
#   corner_lover true → wander targets biased to screen corners (지지)
#   homebody     true → barely moves, wobbles in place (푸딩)
#   hop          true → hop-style movement arcs (콩콩)
#   emotes       pool of emote strings for the speech bubble
const ROSTER: Array[Dictionary] = [
	{
		"id": "moka", "name": "모카", "motif": "머리에 새싹이 난 크림색 두더지",
		"rarity": "common", "weight": 1.0,
		"personality": { "move_speed": 60.0, "idle_min": 1.0, "idle_max": 3.0, "sleep_chance": 0.10,
			"emotes": ["🌱", "❓", "✨", "👀"] },
	},
	{
		"id": "somsom", "name": "솜솜", "motif": "구름 같은 아기 양",
		"rarity": "common", "weight": 0.9,
		"personality": { "move_speed": 30.0, "idle_min": 3.0, "idle_max": 6.0, "sleep_chance": 0.45,
			"emotes": ["💤", "☁️", "🫧"] },
	},
	{
		"id": "kongkong", "name": "콩콩", "motif": "꼬투리 모자를 쓴 연두 완두콩",
		"rarity": "common", "weight": 0.8,
		"personality": { "move_speed": 90.0, "idle_min": 0.5, "idle_max": 1.5, "sleep_chance": 0.05, "hop": true,
			"emotes": ["❗", "🎵", "💚"] },
	},
	{
		"id": "ppiyak", "name": "삐약", "motif": "알껍질 바지를 입은 노란 병아리",
		"rarity": "common", "weight": 0.8,
		"personality": { "move_speed": 70.0, "idle_min": 1.0, "idle_max": 2.5, "sleep_chance": 0.15, "follower": true,
			"emotes": ["💦", "🐣", "❤️"] },
	},
	{
		"id": "doto", "name": "도토", "motif": "도토리 모자를 쓴 갈색 다람쥐",
		"rarity": "common", "weight": 0.7,
		"personality": { "move_speed": 110.0, "idle_min": 0.8, "idle_max": 2.0, "sleep_chance": 0.08,
			"emotes": ["🌰", "💪", "🍂"] },
	},
	{
		"id": "pudding", "name": "푸딩", "motif": "카라멜 머리의 커스터드 푸딩",
		"rarity": "rare", "weight": 0.3,
		"personality": { "move_speed": 20.0, "idle_min": 4.0, "idle_max": 8.0, "sleep_chance": 0.30, "homebody": true,
			"emotes": ["🍮", "😪", "🫠"] },
	},
	{
		"id": "jiji", "name": "지지", "motif": "분홍-하늘 투톤 지우개",
		"rarity": "rare", "weight": 0.25,
		"personality": { "move_speed": 50.0, "idle_min": 2.0, "idle_max": 5.0, "sleep_chance": 0.12, "corner_lover": true,
			"emotes": ["😳", "💗", "…"] },
	},
	{
		"id": "mongdang", "name": "몽당", "motif": "연필심 머리의 몽당연필",
		"rarity": "rare", "weight": 0.25,
		"personality": { "move_speed": 55.0, "idle_min": 1.5, "idle_max": 3.5, "sleep_chance": 0.10,
			"emotes": ["✏️", "📖", "💡"] },
	},
	{
		"id": "latte", "name": "라떼", "motif": "등에 라떼아트 무늬가 있는 수달",
		"rarity": "rare", "weight": 0.2,
		"personality": { "move_speed": 65.0, "idle_min": 1.0, "idle_max": 3.0, "sleep_chance": 0.12, "follower": true,
			"emotes": ["☕", "👋", "🤎"] },
	},
	{
		"id": "byeolgaru", "name": "별가루", "motif": "파스텔 별사탕 요정",
		"rarity": "epic", "weight": 0.05,
		"personality": { "move_speed": 45.0, "idle_min": 2.0, "idle_max": 4.0, "sleep_chance": 0.20, "night_owl": true,
			"emotes": ["⭐", "🌙", "✨"] },
	},
	{
		"id": "buong", "name": "부엉", "motif": "졸린 점눈의 보라 아기 부엉이",
		"rarity": "epic", "weight": 0.04,
		"personality": { "move_speed": 40.0, "idle_min": 2.5, "idle_max": 5.0, "sleep_chance": 0.25, "night_owl": true,
			"emotes": ["🦉", "📚", "💤"] },
	},
	{
		"id": "geumbung", "name": "금붕", "motif": "황금 붕어빵",
		"rarity": "legendary", "weight": 0.005,
		"personality": { "move_speed": 35.0, "idle_min": 2.0, "idle_max": 4.0, "sleep_chance": 0.10,
			"emotes": ["🥇", "🐟", "🌟"] },
	},
	# ── 확장 12종 (2026-06-18) ────────────────────────────────────────────────
	{
		"id": "dorong", "name": "도롱", "motif": "머리 위 깃아가미가 난 분홍 아홀로틀",
		"rarity": "common", "weight": 0.7,
		"personality": { "move_speed": 50.0, "idle_min": 1.5, "idle_max": 3.5, "sleep_chance": 0.18,
			"emotes": ["🫧", "💧", "👀"] },
	},
	{
		"id": "gosum", "name": "고슴", "motif": "등에 둥근 가시가 난 베이지 고슴도치",
		"rarity": "common", "weight": 0.7,
		"personality": { "move_speed": 75.0, "idle_min": 1.0, "idle_max": 2.5, "sleep_chance": 0.10, "corner_lover": true,
			"emotes": ["🌰", "❗", "🍃"] },
	},
	{
		"id": "gaegul", "name": "개굴", "motif": "머리 위 돌출 눈을 가진 민트 개구리",
		"rarity": "common", "weight": 0.65,
		"personality": { "move_speed": 95.0, "idle_min": 0.6, "idle_max": 1.8, "sleep_chance": 0.06, "hop": true,
			"emotes": ["🎵", "💚", "❗"] },
	},
	{
		"id": "ddalbang", "name": "딸방", "motif": "딸기 꼭다리가 달린 딸기우유 방울",
		"rarity": "common", "weight": 0.6,
		"personality": { "move_speed": 45.0, "idle_min": 2.0, "idle_max": 4.0, "sleep_chance": 0.20,
			"emotes": ["🍓", "🥛", "💗"] },
	},
	{
		"id": "sikppang", "name": "식빵", "motif": "크러스트 테두리의 식빵 고양이 한 조각",
		"rarity": "common", "weight": 0.6,
		"personality": { "move_speed": 25.0, "idle_min": 3.5, "idle_max": 7.0, "sleep_chance": 0.40, "homebody": true,
			"emotes": ["🍞", "😺", "😴"] },
	},
	{
		"id": "mongsong", "name": "몽송", "motif": "짧은 지느러미와 수염을 가진 회색 물범",
		"rarity": "rare", "weight": 0.2,
		"personality": { "move_speed": 30.0, "idle_min": 3.0, "idle_max": 6.0, "sleep_chance": 0.35, "homebody": true,
			"emotes": ["🌊", "🐾", "💤"] },
	},
	{
		"id": "dalbo", "name": "달보", "motif": "머리 위 홀씨 갓을 쓴 민들레 홀씨 요정",
		"rarity": "rare", "weight": 0.18,
		"personality": { "move_speed": 40.0, "idle_min": 2.0, "idle_max": 4.5, "sleep_chance": 0.20, "night_owl": true,
			"emotes": ["🌬️", "✨", "🍃"] },
	},
	{
		"id": "beoseot", "name": "버섯", "motif": "둥근 점박이 갓을 머리에 쓴 빨강 버섯",
		"rarity": "rare", "weight": 0.18,
		"personality": { "move_speed": 35.0, "idle_min": 2.5, "idle_max": 5.0, "sleep_chance": 0.22, "homebody": true,
			"emotes": ["🍄", "🌧️", "💡"] },
	},
	{
		"id": "jogyak", "name": "조약", "motif": "이끼 한 줌이 난 강가 조약돌 정령",
		"rarity": "rare", "weight": 0.18,
		"personality": { "move_speed": 30.0, "idle_min": 3.0, "idle_max": 6.0, "sleep_chance": 0.25, "corner_lover": true,
			"emotes": ["🪨", "🌿", "…"] },
	},
	{
		"id": "haedal", "name": "해달", "motif": "말린 꼬리와 등지느러미의 자수정 해마",
		"rarity": "epic", "weight": 0.045,
		"personality": { "move_speed": 45.0, "idle_min": 2.0, "idle_max": 4.0, "sleep_chance": 0.18, "follower": true,
			"emotes": ["🌊", "💜", "🐚"] },
	},
	{
		"id": "gureum", "name": "구름", "motif": "머리 위 미니 무지개를 띄운 솜사탕 구름 정령",
		"rarity": "epic", "weight": 0.035,
		"personality": { "move_speed": 40.0, "idle_min": 2.5, "idle_max": 5.0, "sleep_chance": 0.20,
			"emotes": ["☁️", "🌈", "✨"] },
	},
	{
		"id": "byeolttong", "name": "별똥", "motif": "빛꼬리를 끄는 유성 꼬리 별",
		"rarity": "legendary", "weight": 0.004,
		"personality": { "move_speed": 35.0, "idle_min": 2.0, "idle_max": 4.0, "sleep_chance": 0.12, "night_owl": true,
			"emotes": ["💫", "⭐", "🌠"] },
	},
]


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in ROSTER:
		ids.append(String(c["id"]))
	return ids


static func get_def(id: String) -> Dictionary:
	for c in ROSTER:
		if String(c["id"]) == id:
			return c
	return {}


static func rarity_of(id: String) -> String:
	var def := get_def(id)
	return String(def.get("rarity", "common"))


static func rarity_label(rarity: String) -> String:
	return String(RARITY_LABEL_KO.get(rarity, rarity))


static func rarity_rank(rarity: String) -> int:
	return RARITY_ORDER.find(rarity)


static func ids_of_rarity(rarity: String) -> Array[String]:
	var ids: Array[String] = []
	for c in ROSTER:
		if String(c["rarity"]) == rarity:
			ids.append(String(c["id"]))
	return ids


static func sprite_path(id: String) -> String:
	return "res://assets/characters/%s.png" % id
