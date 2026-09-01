# 美术源文件

存放美术**源文件**（Krita/PS 工程、ComfyUI 工作流 JSON、3D 源文件），导出的成品才放进 `godot/assets/`。

## 风格方向（2026-09-01 定）

2D 国风水墨手绘（质量线：不输鬼谷八荒）；P2 试点 3D 卡通渲染战斗角色。详见 [docs/06_美术与音效/视觉风格指南.md](../docs/06_美术与音效/视觉风格指南.md)。

## 目录约定

- `characters/`（立绘源文件）、`battle/`（战场/精灵）、`ui/`（界面切图）、`effects/`（特效）、`concepts/`（概念探索图）
- **AI 生成物单独归档**：`ai_generated/` 子目录存放 ComfyUI 工作流 JSON 与提示词，命名标注工具与日期（如 `sword_skill_v1_20260901.json`）。原因：Steam 对 AI 生成内容有披露政策，见 [Steam发行策略](../docs/05_发行与路线图/Steam发行策略.md)
- 大体积文件（>10MB）纳入 Git LFS 前先确认必要性；早期阶段宁可存本地备份目录
