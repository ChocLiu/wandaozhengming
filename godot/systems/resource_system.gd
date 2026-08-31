extends Node
## ② 资源面：战斗四池（气血/体力/玄力/魂力）收支与透支
## 对应文档：《战斗系统》§3——没有总体血条，只有四个池。

const POOLS := ["气血", "体力", "玄力", "魂力"]


func init_pools(qi: float, stamina: float, xuan: float, hun: float) -> Dictionary:
	return {
		"气血": {"cur": qi, "max": qi},
		"体力": {"cur": stamina, "max": stamina},
		"玄力": {"cur": xuan, "max": xuan},
		"魂力": {"cur": hun, "max": hun},
	}


## 消费，不足返回 false
func spend(unit, pool: String, amount: float) -> bool:
	if not unit.pools.has(pool):
		return false
	var p: Dictionary = unit.pools[pool]
	if p.cur < amount:
		return false
	p.cur -= amount
	EventBus.pool_changed.emit(unit, pool, p.cur, p.max)
	return true


## 增加（不超过上限）
func gain(unit, pool: String, amount: float) -> void:
	if not unit.pools.has(pool):
		return
	var p: Dictionary = unit.pools[pool]
	p.cur = minf(p.cur + amount, p.max)
	EventBus.pool_changed.emit(unit, pool, p.cur, p.max)


## 流失（失血/灼烧等），可扣到 0 以下
func drain(unit, pool: String, amount: float) -> void:
	if not unit.pools.has(pool):
		return
	var p: Dictionary = unit.pools[pool]
	p.cur = maxf(p.cur - amount, 0.0)
	EventBus.pool_changed.emit(unit, pool, p.cur, p.max)


func current(unit, pool: String) -> float:
	return unit.pools.get(pool, {}).get("cur", 0.0)


## 体力惩罚：体力 < 50% → 速度渐慢（《战斗系统》§1/§4）
func stamina_penalty(unit) -> float:
	var p: Dictionary = unit.pools.get("体力", {})
	if p.is_empty() or p.max <= 0.0:
		return 1.0
	return 1.0 if p.cur >= p.max * 0.5 else 0.6
