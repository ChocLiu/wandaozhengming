extends Node
## ④ 单位面：实体注册与生命周期
## 单位是纯数据（Unit），表现层由场景负责——内核与表现分离（技术方案 §2.2）

var units: Array[Unit] = []


func spawn(def: Dictionary) -> Unit:
	var u := Unit.new(def)
	u.body = BodySystem.make_body(u.realm)
	units.append(u)
	TimelineSystem.register(u)
	return u


func remove_unit(u: Unit) -> void:
	units.erase(u)
	TimelineSystem.unregister(u)


func get_opponents(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.team != team and u.alive:
			result.append(u)
	return result


func alive_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.alive:
			result.append(u)
	return result
