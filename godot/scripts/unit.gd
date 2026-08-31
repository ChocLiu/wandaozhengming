class_name Unit
extends RefCounted
## 战斗单位（纯数据）。部位结构由 BodySystem 生成，四池由 ResourceSystem 管理。

var id: String = ""
var display_name: String = ""
var team: int = 0
var realm: String = "练气"            # 境界——决定部位结构（要害）
var body: Dictionary = {}             # 部位结构+状态（BodySystem.make_body）
var pools: Dictionary = {}            # 战斗四池（ResourceSystem.init_pools）
var statuses: Dictionary = {}         # 状态面（StatusSystem 管理）
var speed: float = 60.0               # 移速（读条速度）
var agility: float = 40.0             # 敏捷
var move_speed: float = 55.0          # 移动能力——步数额度 = ceil(move_speed/20)
var move_left: int = 0                # 本回合剩余步数（行动窗口内重置）
var atb_progress: float = 0.0         # 行动条进度
var alive: bool = true
var is_defending: bool = false        # 本回合招架侧重
var technique: Technique = null       # 主修功法（数据声明）
var attack_power: float = 20.0        # 破防模型：攻击力
var armor: float = 15.0               # 破防模型：防御（装备+玄气+肉身，按部位细化后置）
var rules: Dictionary = {}            # 规则领悟值：{"空间": 60.0}——称号/粗分阶见 CultivationGrades
var technique_proficiency: Dictionary = {}  # 功法修为值：{功法id: 值}——出招命中+5，驱动机制解锁(后置)
var dao_proficiency: Dictionary = {}  # 道领悟值（P0 仅显示）
var items: Dictionary = {"止血丹": 3}
var pos: Vector2i = Vector2i(5, 5)    # 场上位置


func _init(def: Dictionary) -> void:
	for key in def:
		set(key, def[key])
