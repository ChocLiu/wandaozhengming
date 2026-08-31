extends Node
## 事件总线：六子系统与功法机制只通过信号通信，不直接互相调用（技术方案 §2.1）

# ---- 战斗流程 ----
signal battle_started
signal turn_ready(unit)          # 某单位行动条满，轮到行动
signal action_taken(unit, action) # 单位完成一次行动

# ---- ⑥ 部位面 ----
signal part_hurt(unit, part, old_state: int, new_state: int)
signal part_destroyed(unit, part)
signal vital_hit(unit, part)     # 要害被击毁

# ---- ② 资源面 ----
signal pool_changed(unit, pool: String, value: float, max_value: float)
signal unit_died(unit, cause: String)  # cause: 失血 / 要害 / 神魂
