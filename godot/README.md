# Godot 工程（P0 战斗原型）

**状态：已创建（2026-08-30），P0 战斗原型骨架可运行。** 渲染器：Compatibility（gl_compatibility）——2D 回合制项目推荐，若将来需要 2D 辉光等特效可一键切换 Forward+。

## 运行方式

用工作区根目录的 `Godot_v4.7.2-stable_win64.exe` 打开本目录 → F5 运行（主场景 `scenes/battle.tscn`）。

命令行冒烟验证（headless）：
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 300
```

## 工程结构（与技术方案 §4 对应）

```
godot/
├── project.godot        # 六子系统 + EventBus 为 autoload
├── scenes/battle.tscn   # 主场景：P0 战斗演示（剑修 vs 焚天散修）
├── scripts/
│   ├── unit.gd          # 战斗单位（纯数据：部位/四池/移速敏捷/规则领悟）
│   └── battle.gd        # 主控制器：行动流程/双维命中/破防/失血/死亡判定 + 场地绘制
├── systems/             # 六大交互面子系统（autoload）
│   ├── event_bus.gd     # 信号总线
│   ├── status_system.gd # ① 状态面（灼烧/麻痹等）
│   ├── resource_system.gd # ② 资源面（战斗四池）
│   ├── field_system.gd  # ③ 场地面（10×10 地格）
│   ├── unit_system.gd   # ④ 单位面
│   ├── timeline_system.gd # ⑤ 时序面（ATB 行动条）
│   └── body_system.gd   # ⑥ 部位面（部位状态机/失血/要害）
├── mechanics/technique.gd  # 功法数据声明（Technique Resource）
├── resources/techniques/   # 功法数据：青莲剑歌/焚天诀/太虚阵经（.tres 数据驱动）
├── ui/battle_hud.gd        # 程序化 HUD
└── tests/                  # GUT 测试（P0 末期引入）
```

## P0 已实现 / 待实现

已实现（最小内核）：
- ATB 行动条（移速×体力修正×状态修正，行动中冻结）
- 部位系统：凡人/练气/金丹 三层部位结构、状态机（完好→轻伤→重伤→毁）、失血与止血、要害一击毙命
- 战斗四池：气血/体力/玄力/魂力；体力<50% 速度惩罚
- 双维命中：速度对抗 + 规则融入（空间规则碾压演示）
- 破防模型：无伤 / 磨防 / 破防 三态
- 功法数据驱动：Technique Resource + .tres
- 三种死亡途径中的两种：失血 / 要害（神魂后置）

待实现（按路线图 P0 剩余项）：
- 功法机制脚本化（剑谱连击/剑意、布阵、火势蔓延）——当前焚天灼烧为占位实现
- 神魂击杀途径、麻痹等更多状态
- 战斗回放器 + GUT 单测 + 自对弈平衡检查

## 调参入口

`scripts/battle.gd` 顶部常量：STANCE_BONUS / RULE_INFUSE_COST / RULE_CRUSH_BONUS / BLEED_RATE / ARMOR_WEAR 等；单位数值在 `_ready()` 的 spawn 字典里。
