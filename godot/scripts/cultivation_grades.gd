class_name CultivationGrades
## 四字修为量表——参照《英雄坛说》原版武功等级，每 5 点一级，共 36 级。
## 统一用于：功法修为 / 道领悟 / 规则法则领悟（境界不在此列，仍是练气/金丹/元婴）。
## 双轨：称号（成语，显示用）+ 粗分阶（每 25 点一阶，战斗判定用）。

const GRADES := [
	"不堪一击", "毫不足虑", "不足挂齿", "初学乍练", "勉勉强强",
	"初窥门径", "初出茅庐", "略知一二", "普普通通", "平平常常",
	"平淡无奇", "粗懂皮毛", "半生不熟", "登堂入室", "略有小成",
	"已有小成", "鹤立鸡群", "驾轻就熟", "青出于蓝", "融会贯通",
	"心领神会", "炉火纯青", "了然于胸", "略有大成", "已有大成",
	"豁然贯通", "非比寻常", "出类拔萃", "罕有敌手", "技冠群雄",
	"神乎其技", "出神入化", "傲视群雄", "登峰造极", "无与伦比",
	"所向披靡",
]

## 粗分阶名（战斗判定用）：每 25 点一阶，掌道为封顶
const TIER_NAMES := ["初窥", "明悟", "小成", "大成", "掌道"]


static func title(value: float) -> String:
	return GRADES[clampi(int(value) / 5, 0, GRADES.size() - 1)]


static func tier(value: float) -> int:
	return clampi(int(value) / 25, 0, 4)


static func tier_name(value: float) -> String:
	return TIER_NAMES[tier(value)]
