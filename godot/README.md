# Godot 工程目录

Godot 4.7 工程将创建在本目录（`project.godot` 在本目录下）。

创建方式：用工作区根目录的 `Godot_v4.7.2-stable_win64.exe` 打开 → 新建项目 → 选择本目录 → 渲染器选 **Compatibility**（2D 项目推荐，兼容性最好）。

## 工程内目录规划（创建后按此执行）

```
godot/
├── project.godot
├── scenes/          # 场景（战斗/地图/UI）
├── scripts/         # 代码
├── resources/       # 数据资源（功法/种族/事件等自定义 Resource）
├── systems/         # 五大交互面子系统（状态/资源/场地/单位/时序）
├── ui/              # UI 场景与主题
├── assets/          # 游戏内素材（导入产物）
└── tests/           # 自动化测试（GUT）
```

架构细节见 [docs/04_技术方案/Godot技术选型与架构.md](../docs/04_技术方案/Godot技术选型与架构.md)。
