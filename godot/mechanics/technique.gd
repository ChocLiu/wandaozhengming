class_name Technique
extends Resource
## 功法数据声明——字段与《功法系统》§2 声明一一对应。
## P0：核心循环暂为文案描述；机制脚本（连击谱系/布阵/火势）后续挂载到本 Resource。

@export var id: String = ""
@export var display_name: String = ""
@export var daoxi: String = ""                 # 道系（剑道/阵道/火行道…）
@export var category: String = ""              # 类别：体修/玄修/神魂/混修
@export var cost_pool: String = "体力"          # 主消耗池
@export var cost_amount: float = 5.0
@export var speed_bonus: float = 0.0           # 招法速度加成（《战斗系统》§4）
@export_multiline var core_loop: String = ""   # 机制描述（机制脚本后置）
@export var target_parts: PackedStringArray = []  # 部位倾向
@export var rule_slots: PackedStringArray = []    # 规则融入槽（可融入哪些法则）
