extends Node
## 事件总线：六子系统与功法机制只通过信号通信，不直接互相调用（技术方案 §2.1）
## 注意：总线信号的发出方在其他脚本，本类内不 emit——警告用 @warning_ignore 静默。

# ---- 战斗流程 ----
@warning_ignore("unused_signal")
signal battle_started
@warning_ignore("unused_signal")
signal turn_ready(unit)          # 某单位行动条满，轮到行动
@warning_ignore("unused_signal")
signal action_taken(unit, action) # 单位完成一次行动

# ---- ⑥ 部位面 ----
@warning_ignore("unused_signal")
signal part_hurt(unit, part, old_state: int, new_state: int)
@warning_ignore("unused_signal")
signal part_destroyed(unit, part)
@warning_ignore("unused_signal")
signal vital_hit(unit, part)     # 要害被击毁

# ---- ② 资源面 ----
@warning_ignore("unused_signal")
signal pool_changed(unit, pool: String, value: float, max_value: float)
@warning_ignore("unused_signal")
signal unit_died(unit, cause: String)  # cause: 失血 / 要害 / 神魂
