extends Node
## ① 状态面：状态/标记的添加、叠层、回合到期
## 按「回合」结算，不按实时——该单位行动时才结算 dot 与到期（挂机不掉血）。

## 状态定义表：id -> 效果
## dot_qi_turn: 该单位每次行动时流失的气血; speed_mult: 读条/速度乘区（机制级，非数值加成）
const STATUS_DEFS := {
	"灼烧": {"dot_qi_turn": 6.0},
	"麻痹": {"speed_mult": 0.5},
}


func add_status(unit, status_id: String, turns: int) -> void:
	if not STATUS_DEFS.has(status_id):
		return
	# 重复施加取更长回合（v0.0.6 修复：火区灼烧每回合 +1 不应覆盖掉火浪的 3 回合灼烧）
	var prev: int = int(unit.statuses.get(status_id, {}).get("turns", 0))
	unit.statuses[status_id] = {
		"turns": maxi(prev, turns),
		"def": STATUS_DEFS[status_id],
	}


func has(unit, status_id: String) -> bool:
	return unit.statuses.has(status_id)


## 该单位行动时调用：dot 结算 + 回合数 -1，到期移除
func tick_turn(unit) -> void:
	if unit.statuses.is_empty():
		return
	var expired: Array[String] = []
	for id in unit.statuses:
		var s: Dictionary = unit.statuses[id]
		var dot: float = s.get("def", {}).get("dot_qi_turn", 0.0)
		if dot > 0.0:
			ResourceSystem.drain(unit, "气血", dot)
		s.turns = int(s.turns) - 1
		if int(s.turns) <= 0:
			expired.append(id)
	for id in expired:
		unit.statuses.erase(id)


## 状态对读条速度的修正（乘区）
func speed_modifier(unit) -> float:
	var mult := 1.0
	for id in unit.statuses:
		mult *= unit.statuses[id].get("def", {}).get("speed_mult", 1.0)
	return mult
