# Godot 工程（P0 战斗原型）

**状态：P0.5 战斗原型（2026-09-02 v0.0.3 防御博弈版）。** 渲染器：Compatibility（gl_compatibility）——2D 回合制项目推荐，若将来需要 2D 辉光等特效可一键切换 Forward+。

## 运行方式

用工作区根目录的 `Godot_v4.7.2-stable_win64.exe` 打开本目录 → F5 运行（主场景 `scenes/battle.tscn`）。

命令行冒烟验证：
```
# headless 短跑（脚本/资源加载检查）
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 300

# 自对弈长跑（AI 打 AI、战斗自动重开、4 倍速，含机制统计打印）——平衡与机制验证
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 12000 -- --autoplay

# 截图调试（窗口模式——headless 无渲染纹理），每秒存 _debug/shot_N.png
Godot_v4.7.2-stable_win64_console.exe --path . --quit-after 600 -- --shot
```

## 工程结构（与技术方案 §4 对应）

```
godot/
├── project.godot        # 六子系统 + EventBus 为 autoload
├── scenes/battle.tscn   # 主场景：P0 战斗演示（金丹剑修 vs 金丹焚天散修；布局 v0.0.4：左棋盘右面板）
├── scripts/
│   ├── unit.gd          # 战斗单位（纯数据：部位/四池/主用臂/守势/规则领悟）
│   ├── battle.gd        # 主控制器：ATB 行动流/四层防御链/伤效/破防/死亡 + 场地绘制
│   ├── narration.gd     # 武侠叙事解说模板（变体+着色）
│   ├── cultivation_grades.gd  # 英雄坛说 36 级成语修为量表（title/tier 双轨）
│   └── weapons.gd       # 武器数据（攻击/射程修正/招架值）
├── systems/             # 六大交互面子系统（autoload）
│   ├── event_bus.gd     # 信号总线
│   ├── status_system.gd # ① 状态面（灼烧/麻痹等）
│   ├── resource_system.gd # ② 资源面（战斗四池）
│   ├── field_system.gd  # ③ 场地面（10×10 地格）
│   ├── unit_system.gd   # ④ 单位面（战斗重开时 reset_all 清场）
│   ├── timeline_system.gd # ⑤ 时序面（ATB 行动条；reset_all 防跨场景残留）
│   └── body_system.gd   # ⑥ 部位面（部位状态机/失血/要害/伤效修正/代受映射/换手）
├── mechanics/
│   ├── technique.gd     # 功法声明（含 arm_usage 手臂依赖）
│   └── move.gd          # 招法声明（含 arms_required 需手臂）
├── resources/techniques/   # 功法数据 .tres（数据驱动）
├── assets/                 # 美术成品（art/ 源文件的导入副本——源成品分离）
│   ├── backgrounds/        # 整屏水墨棋盘背景 1280×720
│   ├── sprites/            # 战斗精灵 256×256 透明底
│   ├── ui/                 # UI 底板（信息栏850×170/解说栏378×628/按钮96×36）
│   └── icons/              # 操作图标 64×64
├── ui/battle_hud.gd        # 程序化 HUD（守势面板/部位·守标记/臂伤禁用）
└── tests/                  # GUT 测试（P0 末期引入）
```

## P0 已实现 / 待实现

已实现（v0.0.3 防御博弈版）：
- ATB 行动条（移速×体力修正×状态修正，行动中冻结）+ 最小战棋（移动步数=移速，腿伤修正）
- 部位系统：凡人/练气/金丹 三层部位结构（**左臂/右臂/双腿拆分**）、状态机（完好→轻伤→重伤→毁）、失血与止血、要害一击毙命
- 战斗四池：气血/体力/玄力/魂力；体力<50% 速度惩罚
- 双维命中：速度对抗 + 规则融入（粗分阶差≥1 碾压）
- **四层防御链（§5.1）**：①闪避（速度对抗）→ ②招架（守势覆盖/招架架势，仅物理招式；破格挡/武器脱手）→ ③代受（要害被攻用非致命部位换命，反应判定）→ ④部位化护体（守势集中/铁壁加成）
- **守势宣言**：重点保护部位 1~2 个 + 架势三选（招架/闪避/铁壁），保持到主动更改、不占出招
- **战力差距阶梯**：境界差 1 阶招架必破、差 2 阶护体虚设+伤害加深（含境界碾压解说）
- **部位伤效（§2.5）**：臂腿伤 → 攻击/招架/身法/熟练度/移动 乘区+禁用；主臂毁自动换手（×0.8 惩罚）；需臂招式臂毁禁用
- 功法修为成语称号 + 熟练度档系数（招式威力）——臂伤「临时降档」的落点
- 破防模型：无伤 / 磨防 / 破防 三态（磨防磨装备耐久，按部位护体）
- AI：守势宣言、观察守势打空当（优先未保护要害）、融入规则、吃药、逼近
- 自对弈模式（--autoplay）：多场连跑 + 机制触发统计（招架/代受/换手/脱手计数）
- **美术接入（v0.0.4 布局版）**：水墨背景画压淡作氛围层（画中棋盘与逻辑格不对齐，战术网格线为准）；棋盘靠左 600×600；右侧 632 宽解说栏 + 按钮区（FlowContainer 自动换行）；顶部 56px 缩略信息条（墨字纸面配色）

待实现（按路线图 P0 剩余项）：
- 功法机制脚本化（剑谱连击/剑意、布阵、火势蔓延）——当前焚天灼烧为占位实现
- 神魂击杀途径、麻痹等更多状态
- 战斗回放器 + GUT 单测（自对弈已有雏形）
- 平衡调参：当前演示对手（敏捷 90 焚天散修）自对弈胜率偏高——玩家靠「融入空间规则+打空当」可破（见开局提示）

## 调参入口

`scripts/battle.gd` 顶部常量：防御博弈（STANCE_PARRY_BONUS/GUARD_ARMOR_MULT/DISARM_RATIO/SUB_REACTION_FACTOR…）、RULE_INFUSE_COST / RULE_CRUSH_BONUS / ARMOR_WEAR / BLEED_PER_TURN 等；伤效乘区在 `systems/body_system.gd` 的 INJURY_MULT / ARM_USAGE / SUBSTITUTES；单位数值在 `battle.gd _ready()` 的 spawn 字典里。
