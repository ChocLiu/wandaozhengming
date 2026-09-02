extends Node
## ⑤ 时序面：ATB 行动条（仙三式）
## 对应文档：《战斗系统》§1——读条速度 = 移速 × 体力修正 × 状态修正；条满(>=100)获得行动权。
## P0 简化：有人行动时全场冻结读条（战斗暂停=思考时间）；并行读条后置调参。

signal unit_ready(unit: Unit)

var registered: Array[Unit] = []
var pending: Array[Unit] = []   # 已条满、等待行动的单位
var active: bool = true         # false = 全场冻结（菜单/行动结算中）


func register(u: Unit) -> void:
	registered.append(u)


func unregister(u: Unit) -> void:
	registered.erase(u)
	pending.erase(u)


## 读条速度（每秒进度点）
func fill_rate(u: Unit) -> float:
	return u.speed * ResourceSystem.stamina_penalty(u) * StatusSystem.speed_modifier(u)


func process_timeline(delta: float) -> void:
	if not active:
		return
	for u in registered:
		if not active:  # 有人行动中，冻结
			return
		if not u.alive or u in pending:
			continue
		u.atb_progress += fill_rate(u) * delta
		if u.atb_progress >= 100.0:
			pending.append(u)
			unit_ready.emit(u)


## 行动结算完毕后调用：清条、恢复读条
## 注：守势（stance/guard_parts）保持到主动更改，不在此清除（《战斗系统》§5.1.2）
func begin_turn(u: Unit) -> void:
	u.atb_progress = 0.0
	pending.erase(u)
	active = true


## 战斗重开时清场：autoload 跨场景残留状态（重载场景后必须调用，否则时序冻结）
func reset_all() -> void:
	registered.clear()
	pending.clear()
	active = true
