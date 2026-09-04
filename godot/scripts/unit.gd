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
# —— 有效面板（= 基础 + 挂载 + 武器，再乘部位伤效修正——由 battle._recalc_stats 维护）——
var speed: float = 60.0               # 移速（读条速度）
var agility: float = 40.0             # 敏捷（身法——伤效乘区）
var move_speed: float = 55.0
var attack_power: float = 20.0        # 破防模型：攻击力（伤效乘区）
var armor: float = 15.0               # 破防模型：防御（守势集中按部位修正）
var parry: float = 10.0               # 武器招架值（§5.1.3——伤效乘区）
# —— 护体玄气（v0.5 新增：破防模型外层的可回复缓冲带，《战斗系统》§5）——
var shield_cur: float = 0.0           # 护体玄气当前值（破防先扣罩、见底才见肉）
var shield_max: float = 0.0           # 上限 = 境界基数 + 挂载 bonus_shield + 修为档×2（battle._recalc_shield）
var shield_broken_noted: bool = false # 罩首次归零只解说一次
var shield_strategy: String = "守常"  # 护体策略档（守常/周天/凝罡/守一——回合末按档结算补罩，持久沿用）
# —— 挂载 ——
var main_technique: Technique = null          # 主修槽（玄术/心法）——战斗中不可切换
var move_techniques: Array[Technique] = []    # 招式槽功法——战斗中可切换
var active_technique: Technique = null        # 当前出招来源（普攻/招式面板的来源）
var weapon: String = "空手"                   # 当前武器（随激活功法自动换装）
var cooldowns: Dictionary = {}                # 招式id -> 剩余冷却回合
# —— 其他 ——
var atb_progress: float = 0.0
var alive: bool = true
var move_left: int = 0                # 本回合剩余步数（腿伤修正后）
# —— 部位伤效 / 守势（v0.3）——
var main_arm: String = "右臂"         # 主用臂（惯用手）——§2.5 伤效与换手
var offhand: bool = false             # 已换手（副手生疏：攻击/招架 ×0.8）
var guard_parts: Array[String] = []   # 守势重点保护部位（§5.1.2——保持到主动更改）
var stance: String = ""               # 守势架势：招架/闪避/铁壁/""（无守势）
var weapon_durability: float = 10.0   # 武器耐久（破格挡 -1；归零武器损坏）
var weapon_disarmed: bool = false     # 武器脱手（下次行动时自动拾回）
var rules: Dictionary = {}            # 规则领悟值：{"空间": 60.0}——称号/粗分阶见 CultivationGrades
var technique_proficiency: Dictionary = {}  # 功法修为值：{功法id: 值}
var dao_proficiency: Dictionary = {}  # 道领悟值（P0 仅显示）
var items: Dictionary = {"止血丹": 3}
var items_used_this_turn: Dictionary = {}  # {药名: 本回合已用次数}——每回合每种丹药限用一次（回合开始清零）
var pos: Vector2i = Vector2i(5, 5)    # 场上位置
# —— 剑意机制（《功法系统》§3，v0.4）——
var sword_intent: int = 0             # 剑意层 = 连续按谱命中数（0~3）；被打断（闪避/招架）清空；挂在单位上、切换功法不清空
# —— 朝向（v0.5，《战斗系统》§1.2：视觉与几何两个概念）——
var vis_facing: float = 1.0           # 贴图朝向（±1 水平镜像——美术统一朝向、引擎翻转；行动时面朝对手，同列保持）
var geo_facing: Vector2i = Vector2i.ZERO  # 几何背向 = 最近一次移动的最后一步方向；(0,0)=未移动=无背（龟缩不可绕）
# —— 表现层（战斗内插值——移动平滑与死亡淡出）——
var render_pos: Vector2 = Vector2.ZERO   # 实际绘制位置（battle._process 中向逻辑格插值）
var render_alpha: float = 1.0            # 绘制透明度（死亡特效淡出）


func _init(def: Dictionary) -> void:
	for key in def:
		set(key, def[key])
