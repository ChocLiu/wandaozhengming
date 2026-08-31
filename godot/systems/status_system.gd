extends Node
## ① 状态面：状态/标记的添加、叠层、到期（debuff 参与读条与命中速度修正）
## 对应文档：《战斗系统》§4、法则属性加成表 §4.1

## 状态定义表：id -> 效果
## dot_qi: 每秒流失气血; speed_mult: 读条/速度乘区（机制级，非数值加成）
const STATUS_DEFS := {
	"灼烧": {"dot_qi": 2.0},
	"麻痹": {"speed_mult": 0.5},
}


func add_status(unit, status_id: String, duration: float) -> void:
	if not STATUS_DEFS.has(status_id):
		return
	unit.statuses[status_id] = {
		"duration": duration,
		"def": STATUS_DEFS[status_id],
	}


func has(unit, status_id: String) -> bool:
	return unit.statuses.has(status_id)


## 每帧结算：dot 与到期
func tick(delta: float) -> void:
	for u in UnitSystem.units:
		if not u.alive or u.statuses.is_empty():
			continue
		var expired: Array[String] = []
		for id in u.statuses:
			var s: Dictionary = u.statuses[id]
			s.duration -= delta
			if s.duration <= 0.0:
				expired.append(id)
				continue
			var dot: float = s.get("def", {}).get("dot_qi", 0.0)
			if dot > 0.0:
				ResourceSystem.drain(u, "气血", dot * delta)
		for id in expired:
			u.statuses.erase(id)


## 状态对读条速度的修正（乘区）
func speed_modifier(unit) -> float:
	var mult := 1.0
	for id in unit.statuses:
		mult *= unit.statuses[id].get("def", {}).get("speed_mult", 1.0)
	return mult
