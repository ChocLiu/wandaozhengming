class_name Weapons
## 武器数据表——攻击范围 = 招式基础射程 + 武器修正；攻击力 = 基础 + 武器面板 + 挂载加成。
## 平衡参照侠客风云传：拳掌（空手）面板攻击最高但必近身，长兵加射程但面板低。

const DATA := {
	"空手": {"attack": 12.0, "range_bonus": 0},
	"剑": {"attack": 10.0, "range_bonus": 0},
	"枪": {"attack": 6.0, "range_bonus": 1},
}


static func attack(name: String) -> float:
	return DATA.get(name, DATA["空手"]).attack


static func range_bonus(name: String) -> int:
	return DATA.get(name, DATA["空手"]).range_bonus
