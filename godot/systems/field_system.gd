extends Node
## ③ 场地面：地格数据与区域查询
## 对应文档：《战斗系统》§2 战场框架（10×10 格）、功法组合的场地接口

const GRID_W := 10
const GRID_H := 10

var cells: Dictionary = {}  # Vector2i -> Dictionary（格内数据）


func reset() -> void:
	cells.clear()


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_W and pos.y >= 0 and pos.y < GRID_H


## 写入/改写地格（阵图节点、火区、雷域……P0 先用占位数据）
func set_cell(pos: Vector2i, data: Dictionary) -> void:
	if in_bounds(pos):
		cells[pos] = data


func get_cell(pos: Vector2i) -> Dictionary:
	return cells.get(pos, {})


func clear_cell(pos: Vector2i) -> void:
	cells.erase(pos)
