class_name Technique
extends Resource
## 功法数据声明——字段与《功法系统》§2 声明一一对应。
## 挂载体系：主修槽（玄术/心法，战斗中不可切换）与招式槽（兵器/拳脚/身法/神魂……战斗中可切换）。
## 核心循环暂为文案描述；机制脚本（剑意/火势）后续挂载到本 Resource。

@export var id: String = ""
@export var display_name: String = ""
@export var daoxi: String = ""                 # 道系（剑道/刀道/拳道/火行道…）
@export var category: String = ""              # 挂载类别：玄术/心法/兵器/拳脚/身法/招架/神魂/肉身
@export var moves: Array[Move] = []            # 招式池（普攻随机与手动选招的来源）
@export var weapon_req: String = "空手"        # 所需武器（兵器功法），切换时自动换装
@export_multiline var core_loop: String = ""   # 机制描述（机制脚本后置）
@export var target_parts: PackedStringArray = []  # 部位倾向（招式未指定时的兜底）
@export var rule_slots: PackedStringArray = []    # 规则融入槽（可融入哪些法则）
# —— 挂载属性加成（有界小数值层——红线：机制为主、属性为辅）——
@export var bonus_attack: float = 0.0
@export var bonus_armor: float = 0.0
@export var bonus_speed: float = 0.0
@export var bonus_qi_max: float = 0.0
@export var bonus_stamina_max: float = 0.0
@export var bonus_xuan_max: float = 0.0
# —— 兼容性 v1 ——
@export var conflicts_with: PackedStringArray = []  # 冲突声明（类别/资源面：抢同一池的功法互斥）
