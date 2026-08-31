class_name Unit
extends RefCounted
## 战斗单位（纯数据）。
## 挂载体系：主修槽（玄术/心法，战斗中不可切换）+ 招式槽（兵器/拳脚/身法/神魂……战斗中可切换）。
## 有效面板 = 基础面板 + 挂载加成 + 武器；由 battle._recalc_stats/_recalc_pools 维护。

var id: String = ""
var display_name: String = ""
var team: int = 0
var realm: String = "练气"            # 境界——决定部位结构（要害）
var body: Dictionary = {}             # 部位结构+状态（BodySystem.make_body）
var pools: Dictionary = {}            # 战斗四池（有效值，上限=基础+挂载加成）
var statuses: Dictionary = {}         # 状态面（StatusSystem 管理）
# —— 基础面板 ——
var base_speed: float = 60.0          # 基础移速
var base_agility: float = 40.0
var base_move_speed: float = 55.0     # 基础移动能力（步数额度）
var base_attack_power: float = 20.0
var base_armor: float = 15.0
var base_pool_max: Dictionary = {}    # {"气血": 100.0, ...}——挂载前快照
# —— 有效面板（= 基础 + 挂载 + 武器）——
var speed: float = 60.0               # 移速（读条速度）
var agility: float = 40.0             # 敏捷
var move_speed: float = 55.0
var attack_power: float = 20.0        # 破防模型：攻击力
var armor: float = 15.0               # 破防模型：防御
# —— 挂载 ——
var main_technique: Technique = null          # 主修槽（玄术/心法）——战斗中不可切换
var move_techniques: Array[Technique] = []    # 招式槽功法——战斗中可切换
var active_technique: Technique = null        # 当前出招来源（普攻/招式面板的来源）
var weapon: String = "空手"                   # 当前武器（随激活功法自动换装）
var cooldowns: Dictionary = {}                # 招式id -> 剩余冷却回合
# —— 其他 ——
var atb_progress: float = 0.0
var alive: bool = true
var is_defending: bool = false        # 本回合招架侧重
var move_left: int = 0                # 本回合剩余步数
var rules: Dictionary = {}            # 规则领悟值：{"空间": 60.0}——称号/粗分阶见 CultivationGrades
var technique_proficiency: Dictionary = {}  # 功法修为值：{功法id: 值}
var dao_proficiency: Dictionary = {}  # 道领悟值（P0 仅显示）
var items: Dictionary = {"止血丹": 3}
var items_used_this_turn: Dictionary = {}  # {药名: 本回合已用次数}——每回合每种丹药限用一次（回合开始清零）
var pos: Vector2i = Vector2i(5, 5)    # 场上位置


func _init(def: Dictionary) -> void:
	for key in def:
		set(key, def[key])
