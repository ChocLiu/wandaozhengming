# 美术源文件

存放美术**源文件**（Aseprite 工程、PSD、Krita 工程等），导出的成品才放进 `godot/assets/`。

## 约定

- 目录按类型分：`characters/`（角色）、`tiles/`（地图块）、`effects/`（功法特效）、`ui/`（界面）。
- **AI 生成素材单独归档**：`ai_generated/` 子目录存放 ComfyUI 工作流 JSON 与提示词，文件命名标注生成工具与日期（如 `sword_skill_v1_20260830.json`）。原因：Steam 对 AI 生成内容有披露政策，见 [docs/05_发行与路线图/Steam发行策略.md](../docs/05_发行与路线图/Steam发行策略.md)。
- 大体积文件（>10MB）纳入 Git LFS 前先确认必要性；早期阶段宁可存本地备份目录。

风格方向（待美术风格稿确立后更新）：2D 像素/手绘，参考卷轴水墨感与清晰可读的战斗信息呈现。
