extends Node
## ⑦ 音效管理（P0 占位版）——事件 → 音效映射集中于此，调用点分散在战斗结算与 HUD。
## 占位音 = 程序合成（正弦/噪声 + 包络，见 RECIPES）；正式音频素材到位后（《多媒体资产清单》§1.2）：
## 把 sfx() 改为播放 preload 的 OGG 即可——事件键名与全部调用点零改动。
## 池化 8 路：同帧多事件（连击多段、多单位）不互相截断。
## 素材规范见《多媒体资产清单》§1.3：源 WAV 48k/24bit、成品 OGG q5、峰值 ≤ -6dBFS、参考响度 -14 LUFS。

const SAMPLE_RATE := 22050
const POOL_SIZE := 8

## 事件 → 占位音配方：
##   kind: "tone"（正弦）/ "sweep"（扫频）/ "chime"（泛音金属感）/ "noise"（低通白噪 + 低频底）
##   freqs: [f0, f1]（sweep 起止频率；其余只用 f0）、dur 秒、vol 0~1、decay 指数衰减系数、partials 泛音倍率
const RECIPES := {
	"剑击": {"kind": "noise", "freqs": [220.0], "dur": 0.07, "vol": 0.35, "decay": 7.0},
	"招架": {"kind": "chime", "freqs": [950.0], "dur": 0.13, "vol": 0.28, "decay": 8.0, "partials": [1.0, 1.5]},
	"破格挡": {"kind": "sweep", "freqs": [700.0, 260.0], "dur": 0.2, "vol": 0.3, "decay": 5.0},
	"脱手": {"kind": "chime", "freqs": [1300.0], "dur": 0.25, "vol": 0.25, "decay": 6.0, "partials": [1.0, 1.32]},
	"钝击": {"kind": "tone", "freqs": [120.0], "dur": 0.08, "vol": 0.35, "decay": 6.0},
	"代受": {"kind": "tone", "freqs": [160.0], "dur": 0.09, "vol": 0.3, "decay": 6.0},
	"磨防": {"kind": "noise", "freqs": [180.0], "dur": 0.12, "vol": 0.2, "decay": 6.0},
	"无伤": {"kind": "tone", "freqs": [90.0], "dur": 0.09, "vol": 0.3, "decay": 5.0},
	"火浪": {"kind": "noise", "freqs": [90.0], "dur": 0.28, "vol": 0.3, "decay": 3.5},
	"灼烧": {"kind": "noise", "freqs": [120.0], "dur": 0.06, "vol": 0.18, "decay": 8.0},
	"闪避": {"kind": "noise", "freqs": [400.0], "dur": 0.1, "vol": 0.16, "decay": 4.0},
	"失血": {"kind": "tone", "freqs": [800.0], "dur": 0.08, "vol": 0.14, "decay": 9.0},
	"死亡": {"kind": "sweep", "freqs": [220.0, 55.0], "dur": 0.55, "vol": 0.34, "decay": 3.0},
	"服药": {"kind": "sweep", "freqs": [480.0, 720.0], "dur": 0.12, "vol": 0.2, "decay": 6.0},
	"守势": {"kind": "tone", "freqs": [550.0], "dur": 0.1, "vol": 0.2, "decay": 5.0},
	"切换": {"kind": "sweep", "freqs": [380.0, 760.0], "dur": 0.09, "vol": 0.2, "decay": 6.0},
	"移动": {"kind": "tone", "freqs": [300.0], "dur": 0.04, "vol": 0.12, "decay": 6.0},
	"回合": {"kind": "chime", "freqs": [660.0], "dur": 0.22, "vol": 0.26, "decay": 5.0, "partials": [1.0, 2.0]},
	"按钮": {"kind": "tone", "freqs": [440.0], "dur": 0.03, "vol": 0.14, "decay": 8.0},
	"错误": {"kind": "chime", "freqs": [200.0], "dur": 0.12, "vol": 0.2, "decay": 5.0, "partials": [1.0, 1.5]},
	"胜利": {"kind": "chime", "freqs": [523.0], "dur": 0.45, "vol": 0.28, "decay": 3.0, "partials": [1.0, 1.26, 1.5]},
	"失败": {"kind": "sweep", "freqs": [392.0, 180.0], "dur": 0.5, "vol": 0.28, "decay": 3.0},
	# —— 剑意机制（《功法系统》§3）——
	"剑意": {"kind": "chime", "freqs": [880.0], "dur": 0.25, "vol": 0.26, "decay": 4.0, "partials": [1.0, 1.26, 2.0]},
	"溃散": {"kind": "sweep", "freqs": [700.0, 200.0], "dur": 0.35, "vol": 0.24, "decay": 4.0},
	"大招": {"kind": "noise", "freqs": [220.0], "dur": 0.4, "vol": 0.34, "decay": 4.0},
}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}  # 事件 → 合成好的 AudioStreamWAV（长跑不重复合成）


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## 播放事件音效（映射见 RECIPES——正式素材替换时只改这里）
func sfx(key: String) -> void:
	if not RECIPES.has(key):
		push_warning("AudioManager: 未知音效事件「%s」" % key)
		return
	var wav: AudioStreamWAV = _cache.get(key)
	if wav == null:
		wav = _synth(RECIPES[key])
		_cache[key] = wav
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = wav
	p.play()


## 程序合成占位音（16bit / 22050Hz 单声道）：
## 包络 = 3ms 起音 + 指数衰减；noise = 单极低通白噪 + f0 低频底（剑击/火浪的「体感」）
func _synth(r: Dictionary) -> AudioStreamWAV:
	var dur: float = r.dur
	var n := int(dur * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var kind: String = r.get("kind", "tone")
	var f0: float = r.freqs[0]
	var f1: float = r.freqs[min(r.freqs.size() - 1, 1)]
	var vol: float = r.get("vol", 0.2)
	var decay: float = r.get("decay", 5.0)
	var partials: Array = r.get("partials", [1.0])
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var prog := t / dur
		var env := exp(-prog * decay) * (1.0 - exp(-t / 0.003))
		var s := 0.0
		match kind:
			"noise":
				lp += 0.25 * ((randf() * 2.0 - 1.0) - lp)
				s = lp * 1.6 + sin(TAU * f0 * t) * 0.45
			"chime":
				for k in partials:
					s += sin(TAU * f0 * k * t) / k
				s /= partials.size()
			"sweep":
				s = sin(TAU * (f0 + (f1 - f0) * prog) * t)
			_:
				s = sin(TAU * f0 * t)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
