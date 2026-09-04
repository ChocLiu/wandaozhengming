extends Node
## ⑥ 部位面：部位结构 / 部位状态机 / 失血结算 / 要害判定 / 代受映射 / 部位伤效
## 对应文档：《战斗系统》§2（含 v0.3 §2.5 部位伤效、§5.1 防御博弈）
## 红线：部位是状态机，不是「部位血条」；伤效是乘区+禁用，统一由本系统维护。

enum PartState { OK, LIGHT, HEAVY, DESTROYED }

const STATE_NAMES := ["完好", "轻伤", "重伤", "毁"]

## 境界阶梯（§5.1.3 战力差距阶梯）：差 1 阶=招架必破；差 2 阶+=护体虚设、伤害加深
const REALM_TIER := {"凡人": 0, "练气": 1, "筑基": 2, "金丹": 3, "元婴": 4}

## 境界 → 部位结构（v0.3：「手足」拆分为 左臂/右臂/双腿——各为独立状态机）。
## P0 只做 凡人/练气/金丹 三层（路线图 P0 范围），化神+ 后置。
const REALM_BODIES := {
	"凡人": {
		"头部": {"vital": true},
		"心脉": {"vital": true},
		"命脉": {"vital": true},
		"胸腹": {"vital": false},
		"左臂": {"vital": false},
		"右臂": {"vital": false},
		"双腿": {"vital": false},
	},
	"练气": {
		"头部": {"vital": true},
		"心脉": {"vital": true},
		"丹田气海": {"vital": true},   # 气海可破=修为尽废
		"经脉": {"vital": false},      # 经脉可截=运转受阻(机制后置)
		"胸腹": {"vital": false},
		"左臂": {"vital": false},
		"右臂": {"vital": false},
		"双腿": {"vital": false},
	},
	"金丹": {
		"头部": {"vital": true},
		"心脉": {"vital": true},
		"丹田": {"vital": true},       # 金丹所在——金丹碎=道基尽毁
		"眉心神识": {"vital": true},   # 识海
		"胸腹": {"vital": false},
		"左臂": {"vital": false},
		"右臂": {"vital": false},
		"双腿": {"vital": false},
	},
}

## 伤档修正表（§2.5）：部位状态 → 功能修正。
## atk/parry/agi 为乘区；prof_down 为熟练度临时降档数；腿的移动另见 leg_penalty。
const INJURY_MULT := {
	PartState.OK: {"atk": 1.0, "parry": 1.0, "agi": 1.0, "prof_down": 0},
	PartState.LIGHT: {"atk": 0.7, "parry": 0.7, "agi": 0.8, "prof_down": 1},
	PartState.HEAVY: {"atk": 0.4, "parry": 0.4, "agi": 0.5, "prof_down": 2},
	PartState.DESTROYED: {"atk": 0.0, "parry": 0.0, "agi": 0.3, "prof_down": 2},
}

## 功法手臂依赖（§2.5）：arm_usage → 主/副臂各影响哪些功能域
const ARM_USAGE := {
	"单臂持械": {"main": ["atk", "parry"], "off": []},
	"双臂持械": {"main": ["atk", "parry"], "off": ["atk", "parry"]},
	"双拳": {"main": ["atk"], "off": ["atk"]},
	"副手结印": {"main": ["atk", "parry"], "off": ["prof"]},
	"副手护身": {"main": ["atk"], "off": ["parry"]},
	"身法借力": {"main": ["atk", "parry"], "off": ["agi"]},
	"无": {"main": [], "off": []},
}

## 代受映射（§5.1.4）：要害 → 可用代受部位（非致命部位换命）
const SUBSTITUTES := {
	"头部": ["左臂", "右臂"],
	"心脉": ["左臂", "右臂"],
	"命脉": ["左臂", "右臂"],
	"眉心神识": ["左臂", "右臂"],
	"丹田": ["胸腹"],
	"丹田气海": ["胸腹"],
}

## 腿伤 → 移动惩罚：0=全 / 1=少一步 / 2=减半 / 3=无法移动
const LEG_MOVE := {
	PartState.OK: 0, PartState.LIGHT: 1, PartState.HEAVY: 2, PartState.DESTROYED: 3,
}


func make_body(realm: String) -> Dictionary:
	var src: Dictionary = REALM_BODIES.get(realm, REALM_BODIES["练气"])
	var body := {}
	for part in src:
		body[part] = {
			"state": PartState.OK,
			"vital": src[part].get("vital", false),
			"bleeding": false,  # 创伤未止血则持续流失气血
		}
	return body


## 伤害一个部位。severity: 1=轻伤一格, 2=重伤, 3=毁。
## v0.5：不再无条件置 bleeding——是否流血由调用方按武器利刃属性掷骰后经 set_bleeding 置位
## （《战斗系统》§2.3：纯刃必流/半刃中概率/钝器大概率不流——轻中重伤皆可流，只是概率不同）。
func hurt(unit, part: String, severity: int = 1) -> void:
	var b: Dictionary = unit.body.get(part, {})
	if b.is_empty():
		return
	var old_state: int = b.state
	b.state = mini(old_state + severity, PartState.DESTROYED)
	EventBus.part_hurt.emit(unit, part, old_state, b.state)
	if b.state == PartState.DESTROYED:
		EventBus.part_destroyed.emit(unit, part)
		if b.vital:
			EventBus.vital_hit.emit(unit, part)


## 按掷骰结果设置某部位是否流血（v0.5：失血概率化后由战斗层调用）
func set_bleeding(unit, part: String, on: bool) -> void:
	var b: Dictionary = unit.body.get(part, {})
	if b.is_empty() or b.state < PartState.LIGHT:
		return
	b.bleeding = on


## 当前失血速率（每处流血创伤 BLEED_RATE/秒，由调用方乘 delta）
func bleed_amount(unit) -> float:
	var amount := 0.0
	for part in unit.body.values():
		if part.bleeding and part.state >= PartState.LIGHT:
			amount += 1.0
	return amount


## 止血（丹药/功法/包扎）：止住全部创伤的失血——部位状态不变
func seal_wounds(unit) -> void:
	for part in unit.body.values():
		part.bleeding = false


func has_destroyed_vital(unit) -> bool:
	for part in unit.body:
		var b: Dictionary = unit.body[part]
		if b.vital and b.state == PartState.DESTROYED:
			return true
	return false


# ---------- 部位伤效（§2.5） ----------

## 部位伤效总表：返回 {atk, parry, agi, prof_down} 乘区/降档（按当前激活功法 arm_usage 计算）
func injury_multipliers(unit) -> Dictionary:
	var result := {"atk": 1.0, "parry": 1.0, "agi": 1.0, "prof_down": 0}
	var usage := "无"
	if unit.active_technique != null:
		usage = unit.active_technique.arm_usage
	var u: Dictionary = ARM_USAGE.get(usage, ARM_USAGE["无"])
	var off_arm := other_arm(unit.main_arm)
	var main_state: int = int(unit.body.get(unit.main_arm, {}).get("state", PartState.OK))
	var off_state: int = int(unit.body.get(off_arm, {}).get("state", PartState.OK))
	var main_m: Dictionary = INJURY_MULT[main_state]
	var off_m: Dictionary = INJURY_MULT[off_state]
	for d in u.get("main", []):
		_apply_domain(result, main_m, d)
	for d in u.get("off", []):
		_apply_domain(result, off_m, d)
	# 双拳：双臂各占一半（各臂折算后平均）
	if usage == "双拳":
		result.atk = 0.5 * main_m.atk + 0.5 * off_m.atk
	# 双腿 → 身法
	var leg_state: int = int(unit.body.get("双腿", {}).get("state", PartState.OK))
	result.agi = minf(result.agi, INJURY_MULT[leg_state].agi)
	# 换手惩罚（副手生疏：攻击/招架额外 ×0.8）
	if unit.offhand:
		result.atk = minf(result.atk, 0.8)
		result.parry = minf(result.parry, 0.8)
	return result


func _apply_domain(result: Dictionary, m: Dictionary, domain: String) -> void:
	if domain == "prof":
		result.prof_down = maxi(result.prof_down, int(m.prof_down))
	else:
		result[domain] = minf(result[domain], m[domain])


## 腿伤 → 移动惩罚档（0 全 / 1 少一步 / 2 减半 / 3 无法移动）
func leg_penalty(unit) -> int:
	return LEG_MOVE.get(int(unit.body.get("双腿", {}).get("state", PartState.OK)), 0)


## 招式手臂可用性（§2.5）：主臂毁 → 需臂招式禁用（换手后主臂指向完好臂）；
## 需双臂（arms_required=2）任一臂毁即禁用；0=心念发动不受臂伤影响
func can_use_move(unit, move) -> bool:
	if move.arms_required <= 0:
		return true
	if not arm_intact(unit, unit.main_arm):
		return false
	if move.arms_required >= 2:
		return arm_intact(unit, other_arm(unit.main_arm))
	return true


func arm_intact(unit, arm: String) -> bool:
	return int(unit.body.get(arm, {}).get("state", PartState.OK)) != PartState.DESTROYED


func other_arm(arm: String) -> String:
	return "左臂" if arm == "右臂" else "右臂"


## 换手（§2.5）：主用臂被毁 → 副臂转主用并标记副手生疏；双臂皆毁则失败
func switch_main_arm(unit) -> bool:
	var other := other_arm(unit.main_arm)
	if not unit.body.has(other) or not arm_intact(unit, other):
		return false
	unit.main_arm = other
	unit.offhand = true
	return true


## 代受部位（§5.1.4）：返回该要害可用的第一个未毁代受部位；无则 ""
func substitute_for(unit, part: String) -> String:
	for s in SUBSTITUTES.get(part, []):
		if unit.body.has(s) and arm_intact(unit, s):
			return s
	return ""


## 境界差（战力差距阶梯 §5.1.3）：攻方 - 守方；≥1 招架必破，≥2 护体虚设+伤害加深
func realm_diff(attacker, target) -> int:
	return REALM_TIER.get(attacker.realm, 1) - REALM_TIER.get(target.realm, 1)
