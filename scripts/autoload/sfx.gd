# Sfx — 효과음 autoload (docs/DESIGN_SPEC.md §E).
# AudioStreamPlayer 풀 + 피치 랜덤화. 사운드 파일(res://assets/sfx/{name}.wav)이
# 없으면 조용히 무시한다(에셋 누락에도 게임은 완전 동작). 헤드리스/오디오
# 디바이스 없음에서도 크래시하지 않는다.
#
# 사운드는 빌드타임 절차 생성(scripts/gen-sfx.mjs) — 외부 다운로드·IP 없음.

extends Node

const SFX_DIR := "res://assets/sfx"
const POOL_SIZE := 6

# 의미 이름 → 파일명(확장자 제외). 여러 의미가 한 파일을 공유할 수 있다.
const MAP := {
	"click": "click",
	"correct": "ding",
	"wrong": "boop",
	"coin": "coin",
	"ticket": "coin",
	"snack": "pop",
	"sell": "coin",
	"levelup": "chime",
	"gacha_spin": "whoosh",
	"gacha_common": "pop",
	"gacha_rare": "ding",
	"gacha_epic": "chime",
	"gacha_legendary": "fanfare",
	"transition": "swish",
	"streak": "chime",
}

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}   # 파일명 -> AudioStream
var _next := 0
var _enabled := true


func _ready() -> void:
	# 헤드리스에서는 오디오를 만들지 않는다(불필요 + 일부 환경 경고 회피).
	if DisplayServer.get_name() == "headless":
		_enabled = false
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func set_enabled(on: bool) -> void:
	_enabled = on and DisplayServer.get_name() != "headless"


func is_enabled() -> bool:
	return _enabled


# 의미 이름으로 재생. 파일이 없으면 무시. 피치는 약간 랜덤(반복 단조로움 제거).
func play(name: String, pitch_jitter: float = 0.06) -> void:
	if not _enabled or _players.is_empty():
		return
	var file := String(MAP.get(name, name))
	var stream: AudioStream = _load(file)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _load(file: String) -> AudioStream:
	if _cache.has(file):
		return _cache[file]
	var path := "%s/%s.wav" % [SFX_DIR, file]
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[file] = stream
	return stream
