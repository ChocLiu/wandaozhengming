extends Node
## ⑥ 部位面：部位结构 / 部位状态机 / 失血结算 / 要害判定
## 对应文档：《战斗系统》§2、《修炼体系》§2.1
## 红线：部位是状态机，不是「部位血条」。

enum PartState { OK, LIGHT, HEAVY, DESTROYED }

const STATE_NAMES := ["完好", "轻伤", "重伤", "毁"]

## 境界 → 部位结构。P0 只做 凡人/练气/金丹 三层（路线图 P0 范围），化神+ 后置。
const REALM_BODIES := {
	"凡人": {
		"大脑": {"vital": true},
		"心脏": {"vital": true},
		"大动脉": {"vital": true},
		"躯干": {"vital": false},
		"四肢": {"vital": false},
	},
	"练气": {
		"大脑": {"vital": true},
		"心脏": {"vital": true},
		"丹田气海": {"vital": true},   # 气海可破=修为尽废
		"经脉": {"vital": false},      # 经脉可截=运转受阻(机制后置)
		"躯干": {"vital": false},
		"四肢": {"vital": false},
	},
	"金丹": {
		"大脑": {"vital": true},
		"心脏": {"vital": true},
		"丹田": {"vital": true},       # 金丹所在——金丹碎=道基尽毁
		"眉心神识": {"vital": true},   # 识海
		"躯干": {"vital": false},
		"四肢": {"vital": false},
	},
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


## 伤害一个部位。severity: 1=轻伤一格, 2=重伤, 3=毁
func hurt(unit, part: String, severity: int = 1) -> void:
	var b: Dictionary = unit.body.get(part, {})
	if b.is_empty():
		return
	var old_state: int = b.state
	b.state = mini(old_state + severity, PartState.DESTROYED)
	if b.state >= PartState.LIGHT:
		b.bleeding = true
	EventBus.part_hurt.emit(unit, part, old_state, b.state)
	if b.state == PartState.DESTROYED:
		EventBus.part_destroyed.emit(unit, part)
		if b.vital:
			EventBus.vital_hit.emit(unit, part)


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
