class_name Weapons
## 武器数据表——攻击范围 = 招式基础射程 + 武器修正；攻击力 = 基础 + 武器面板 + 挂载加成。
## v0.0.5 追加基本属性：edge 锋利度 0~3（钝/半刃/利刃/纯刃）+ blade 刃长 0~2（短/中/长）——
##   流血概率 = EDGE_P[edge] × BLADE_MULT[blade] × 部位状态档（《战斗系统》§2.3）；威胁半径 = 1 + range_bonus。
## 平衡参照侠客风云传：拳掌（空手）面板攻击最高但必近身，长兵加射程但面板低。

const DATA := {
	"空手": {"attack": 12.0, "range_bonus": 0, "parry": 5.0, "edge": 0, "blade": 0},
	"剑": {"attack": 10.0, "range_bonus": 0, "parry": 20.0, "edge": 3, "blade": 2},
	"枪": {"attack": 6.0, "range_bonus": 1, "parry": 15.0, "edge": 1, "blade": 2},
}


static func attack(name: String) -> float:
	return DATA.get(name, DATA["空手"]).attack


static func range_bonus(name: String) -> int:
	return DATA.get(name, DATA["空手"]).range_bonus


static func parry(name: String) -> float:
	return DATA.get(name, DATA["空手"]).parry


static func edge(name: String) -> int:
	return DATA.get(name, DATA["空手"]).edge


static func blade(name: String) -> int:
	return DATA.get(name, DATA["空手"]).blade
