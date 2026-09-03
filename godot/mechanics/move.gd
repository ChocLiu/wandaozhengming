class_name Move
extends Resource
## 招法数据声明——功法的「叶」，战斗动作单元。
## 对应《功法系统》§2.2：范围由招式+武器决定；冷却（侠客风云传式：起手式 0 CD）；
## 修为节点解锁（大招）后置。move_type: 普通 / 大招 / 散招（本轮只做普通）。

@export var id: String = ""
@export var display_name: String = ""
@export var move_type: String = "普通"
@export var cost_pool: String = "体力"
@export var cost_amount: float = 5.0
@export var speed_bonus: float = 0.0       # 招式速度加成（命中结算用）
@export var range_min: int = 1             # 基础射程（切比雪夫距离），实际射程 = 基础 + 武器修正
@export var range_max: int = 1
@export var area_pattern: String = "单体"  # 单体/直线/扇形/溅射（图案为数据位，P0.5 只结算单体）
@export var cooldown: int = 0              # 冷却回合数（0 = 每回合可用）
@export var arms_required: int = 1         # 需手臂（§2.5）：0=心念发动 / 1=单臂 / 2=双臂——臂毁则禁用
@export var power_mod: float = 1.0         # 攻击力修正（破防对比用）
@export var target_parts: PackedStringArray = []
@export var effects: PackedStringArray = []  # 机制标签：灼烧/麻痹/破防+ 等
# —— 变招/大招解锁（剑意机制，《功法系统》§3）：0 = 无门槛 ——
@export var unlock_intent: int = 0          # 所需剑意层（变招/大招挂于 Technique.variants）
@export var unlock_proficiency: float = 0.0 # 所需功法修为（修为是机制解锁的挂钩点，§2.1）
