class_name BattleHud
extends Control
## P0 战斗 HUD（程序化构建，无 .tscn）。
## 布局（1280×720 固定）：左上=单位信息 · 右侧竖排=战斗解说 · 招式面板行 · 部位按钮行 · 操作按钮行。
## v0.3：守势面板（部位行+架势按钮复用）；部位按钮标「守」；臂伤禁用招式；主用臂标记。
## 全部用 position/size 定位——锚点对 Node2D 下的根 Control 有踩坑记录（见 git 历史）。

signal attack_pressed        # 普攻（英雄坛说式随机出招）
signal move_menu_pressed     # 招式面板（侠客风云传式手动选招）
signal switch_pressed        # 切换招式功法
signal guard_pressed         # 守势宣言（§5.1.2）
signal item_pressed
signal end_turn_pressed
signal part_selected(part: String)
signal move_selected(move_id: String)
signal guard_part_toggled(part: String, on: bool)
signal guard_stance_selected(stance: String)
signal guard_cancel
signal restart_requested

const Grades := preload("res://scripts/cultivation_grades.gd")

const STANCES := ["招架", "闪避", "铁壁"]

const INK := Color(0.14, 0.12, 0.09)       # 浓墨（纸面 UI 主文字色）
const INK_DIM := Color(0.45, 0.43, 0.4)    # 淡墨（禁用文字）
## 面板图排版规范（2026-09-02 定）：
## 统一百分比（四边 10%）只作「出图提示词规范」；实际排版缩进按**每面板实测纸面边界+缓冲**（px）——
## 立卷装饰在上下（卷轴杆），横幅装饰在两端，比例天然不同。换图只改这张表。
const PANEL_INSETS := {
	# 信息横条 1256×56：轴头实测仅 2%，取 5% 留缓冲；上下为装饰边实测 16%/9%
	"info": {"l": 80, "t": 10, "r": 80, "b": 6},
	# 解说面板 632×420：卷轴杆实测上下各 15%，左右花边 5~7% 取 10% 留缓冲
	"log": {"l": 100, "t": 100, "r": 100, "b": 100},
	# 按钮 96×36：四边约 10%
	"btn": {"l": 10, "t": 4, "r": 10, "b": 4},
}

# —— 美术成品（布局 v0.4 精确尺寸：信息横条 1256×56、解说栏 632×420、按钮底板 96×36、图标 64×64）——
const TEX_PANEL_INFO := preload("res://assets/ui/UI_信息栏底板_v2_ai.png")
const TEX_PANEL_LOG := preload("res://assets/ui/UI_解说栏底板_v2_ai.png")
const TEX_BTN := preload("res://assets/ui/UI_按钮底板_v1_ai.png")
const TEX_ICONS := {
	"普攻": preload("res://assets/icons/操作图标_普攻_v1_ai.png"),
	"招式": preload("res://assets/icons/操作图标_招式_v1_ai.png"),
	"切换": preload("res://assets/icons/操作图标_切换_v1_ai.png"),
	"守势": preload("res://assets/icons/操作图标_守势_v1_ai.png"),
	"丹药": preload("res://assets/icons/操作图标_丹药_v1_ai.png"),
	"结束": preload("res://assets/icons/操作图标_结束_v1_ai.png"),
}

var info_label: Label
var log_rtl: RichTextLabel
var action_row: FlowContainer
var part_row: FlowContainer
var move_row: FlowContainer
var rule_toggle: CheckButton
var restart_btn: Button
var switch_btn: Button
var item_btn: Button
var guard_btn: Button
var _action_buttons: Array[Button] = []
var _guard_part_buttons: Dictionary = {}   # part -> Button（守势选择面板中）
var _item_used := false       # 本回合该丹药已用（每回合每种限一次）
var _battle = null


func _ready() -> void:
	# 根控件显式固定尺寸（P0 固定分辨率 1280x720）：
	# 锚点预设对 Node2D 下的根 Control 在 _ready 时机不生效（实测 rect 为 0），
	# 子控件锚点是相对本控件计算的，根没尺寸 → 子控件全跑到屏幕外。
	offset_right = 1280.0
	offset_bottom = 720.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根节点不挡输入，子控件各自接收

	# 顶部：双方信息缩略条（1256×56 卷轴横条 + 三行墨字）
	var info_panel := Panel.new()
	info_panel.position = Vector2(12, 6)
	info_panel.size = Vector2(1256, 56)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_theme_stylebox_override("panel", _stylebox(TEX_PANEL_INFO))
	add_child(info_panel)
	info_label = Label.new()
	# 内容缩进：见 PANEL_INSETS["info"]
	info_label.position = Vector2(PANEL_INSETS["info"].l, PANEL_INSETS["info"].t)
	info_label.size = Vector2(1256.0 - PANEL_INSETS["info"].l - PANEL_INSETS["info"].r, 56.0 - PANEL_INSETS["info"].t - PANEL_INSETS["info"].b)
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", INK)
	info_panel.add_child(info_label)

	# 右侧：战斗解说面板（加宽 632×420；底板纹理等比拉伸——后续可重出此尺寸底图）
	var log_panel := Panel.new()
	log_panel.position = Vector2(640, 72)
	log_panel.size = Vector2(632, 420)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_theme_stylebox_override("panel", _stylebox(TEX_PANEL_LOG))
	add_child(log_panel)
	log_rtl = RichTextLabel.new()
	# 内容缩进：见 PANEL_INSETS["log"]
	log_rtl.position = Vector2(PANEL_INSETS["log"].l, PANEL_INSETS["log"].t)
	log_rtl.size = Vector2(632.0 - PANEL_INSETS["log"].l - PANEL_INSETS["log"].r, 420.0 - PANEL_INSETS["log"].t - PANEL_INSETS["log"].b)
	log_rtl.scroll_following = true
	log_rtl.add_theme_color_override("default_color", INK)
	log_rtl.add_theme_font_size_override("normal_font_size", 13)
	log_panel.add_child(log_rtl)

	# 招式面板行（手动选招，带 CD 显示；守势选择时复用为架势按钮）——FlowContainer 自动换行
	move_row = FlowContainer.new()
	move_row.position = Vector2(640, 500)
	move_row.size = Vector2(632, 44)
	move_row.add_theme_constant_override("h_separation", 6)
	add_child(move_row)

	# 部位按钮行（守势选择时复用为自己的部位）——两行高度
	part_row = FlowContainer.new()
	part_row.position = Vector2(640, 552)
	part_row.size = Vector2(632, 76)
	part_row.add_theme_constant_override("h_separation", 6)
	part_row.add_theme_constant_override("v_separation", 6)
	add_child(part_row)

	# 操作按钮区（右下，自动换行 2 行）
	action_row = FlowContainer.new()
	action_row.position = Vector2(640, 636)
	action_row.size = Vector2(632, 80)
	action_row.add_theme_constant_override("h_separation", 8)
	action_row.add_theme_constant_override("v_separation", 6)
	add_child(action_row)

	var b := _make_button("普攻", func(): attack_pressed.emit())
	_set_icon(b, "普攻")
	_action_buttons.append(b)
	action_row.add_child(b)
	b = _make_button("招式", func(): move_menu_pressed.emit())
	_set_icon(b, "招式")
	_action_buttons.append(b)
	action_row.add_child(b)
	switch_btn = _make_button("切换", func(): switch_pressed.emit())
	_set_icon(switch_btn, "切换")
	_action_buttons.append(switch_btn)
	action_row.add_child(switch_btn)
	guard_btn = _make_button("守势", func(): guard_pressed.emit())
	_set_icon(guard_btn, "守势")
	_action_buttons.append(guard_btn)
	action_row.add_child(guard_btn)
	item_btn = _make_button("丹药", func(): item_pressed.emit())
	_set_icon(item_btn, "丹药")
	_action_buttons.append(item_btn)
	action_row.add_child(item_btn)
	b = _make_button("结束行动", func(): end_turn_pressed.emit())
	_set_icon(b, "结束")
	_action_buttons.append(b)
	action_row.add_child(b)

	rule_toggle = CheckButton.new()
	rule_toggle.text = "融入规则（耗玄力）"
	rule_toggle.add_theme_color_override("font_color", INK)
	action_row.add_child(rule_toggle)

	restart_btn = _make_button("重新开始", func(): restart_requested.emit())
	restart_btn.visible = false
	restart_btn.position = Vector2(240, 300)
	restart_btn.size = Vector2(160, 44)
	add_child(restart_btn)

	enable_actions(false)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 36)
	b.pressed.connect(on_pressed)
	b.pressed.connect(func(): AudioManager.sfx("按钮"))
	# 卷轴质感按钮底板（96×36 与按钮同尺寸）+ 墨字（纸面 UI）
	# 内容缩进：见 PANEL_INSETS["btn"]——按钮文字/图标自动让出卷轴轴头区
	var sb := _stylebox(TEX_BTN)
	sb.content_margin_left = PANEL_INSETS["btn"].l
	sb.content_margin_right = PANEL_INSETS["btn"].r
	sb.content_margin_top = PANEL_INSETS["btn"].t
	sb.content_margin_bottom = PANEL_INSETS["btn"].b
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", INK_DIM)
	return b


func _stylebox(tex: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	return sb


## 操作按钮图标（64×64 源图在加载时缩至 24px——Button 图标按自然尺寸显示，不缩放会撑高按钮行）
func _set_icon(b: Button, key: String) -> void:
	var tex: Texture2D = TEX_ICONS.get(key, null)
	if tex == null:
		return
	var img := tex.get_image()
	img.resize(24, 24, Image.INTERPOLATE_LANCZOS)
	b.icon = ImageTexture.create_from_image(img)


func enable_actions(enabled: bool) -> void:
	if enabled:
		_item_used = false  # 新回合，丹药限次清零
	for b in _action_buttons:
		b.disabled = (not enabled) or (b == item_btn and _item_used)
	rule_toggle.disabled = not enabled
	if not enabled:
		clear_parts()
		clear_moves()


## 本回合该丹药已用 → 禁用按钮（不占出招机会的丹药规则）
func set_item_used(used: bool) -> void:
	_item_used = used
	item_btn.disabled = _item_used or item_btn.disabled


## 弹出招式面板（当前激活功法的招式池，带 CD 与臂伤禁用状态）
func set_moves(unit) -> void:
	clear_moves()
	if unit.active_technique == null:
		return
	for m in unit.active_technique.moves:
		var cd := int(unit.cooldowns.get(m.id, 0))
		var arm_ok: bool = BodySystem.can_use_move(unit, m)
		var label: String
		if cd > 0:
			label = "%s（CD%d）" % [m.display_name, cd]
		elif not arm_ok:
			label = "%s（臂伤）" % m.display_name
		else:
			label = m.display_name
		var mid: String = m.id
		var b := _make_button(label, func(): move_selected.emit(mid))
		b.disabled = cd > 0 or not arm_ok
		move_row.add_child(b)


func clear_moves() -> void:
	for child in move_row.get_children():
		child.queue_free()


## 弹出目标单位的可选部位按钮（已毁部位不可选；守势内的部位标「守」）
func set_parts(unit) -> void:
	clear_parts()
	for part in unit.body:
		var pd: Dictionary = unit.body[part]
		if pd.state == BodySystem.PartState.DESTROYED:
			continue
		var p: String = part
		var label := "%s·%s%s" % [p, BodySystem.STATE_NAMES[pd.state], "·守" if unit.guard_parts.has(p) else ""]
		var b := _make_button(label, func(): part_selected.emit(p))
		b.custom_minimum_size = Vector2(120, 32)
		part_row.add_child(b)


func clear_parts() -> void:
	for child in part_row.get_children():
		child.queue_free()


# ---------- 守势选择面板（§5.1.2） ----------

## 部位行 = 自己的部位（toggle 最多 2 个）；招式行 = 架势三选 + 取消
func show_guard_select(unit) -> void:
	clear_guard_select()
	for part in unit.body:
		var p: String = part
		var b := Button.new()
		b.text = p
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 32)
		b.toggled.connect(func(on: bool): guard_part_toggled.emit(p, on))
		b.toggled.connect(func(_on: bool): AudioManager.sfx("按钮"))
		_guard_part_buttons[p] = b
		part_row.add_child(b)
	for s in STANCES:
		var st: String = s
		move_row.add_child(_make_button(st, func(): guard_stance_selected.emit(st)))
	move_row.add_child(_make_button("取消", func(): guard_cancel.emit()))
	# 预显当前守势部位（保持制——打开面板即回显已选，微调即可）
	update_guard_parts(unit.guard_parts)


## 同步已选部位的高亮（◆ 标记）
func update_guard_parts(pending: Array) -> void:
	for part in _guard_part_buttons:
		var b: Button = _guard_part_buttons[part]
		var on: bool = pending.has(part)
		b.set_pressed_no_signal(on)
		b.text = "%s%s" % [part, "◆" if on else ""]


func clear_guard_select() -> void:
	clear_parts()
	clear_moves()
	_guard_part_buttons.clear()


func update_state(battle) -> void:
	var actor: Unit = battle.current_actor
	var turn_text := actor.display_name if actor != null else "——"
	var hint := ""
	if actor == battle.player:
		if battle.current_acted:
			hint = "▶ 已出招：可继续移动（剩%d步）/ 丹药 / 守势，或点「结束行动」" % actor.move_left
		elif actor.move_left <= 0:
			hint = "▶ 步数已尽：仍可出招 / 丹药 / 守势——出招后本回合自动结束"
		else:
			hint = "▶ 轮到你：点棋盘移动（剩%d步）→ 普攻随机 / 「招式」选招 / 「守势」 / 「切换」 / 丹药" % actor.move_left
	info_label.text = "%s\n%s\n%s %s" % [
		_unit_line(battle.player),
		_unit_line(battle.opponent),
		turn_text, hint,
	]
	# 切换按钮动态标签（显示下一门功法）
	var next_name := "切换"
	var pl: Unit = battle.player
	if pl.move_techniques.size() >= 2 and pl.active_technique != null:
		var idx := pl.move_techniques.find(pl.active_technique)
		var next: Technique = pl.move_techniques[(idx + 1) % pl.move_techniques.size()]
		next_name = "切换·%s" % next.display_name
	switch_btn.text = next_name
	# 守势按钮动态标签
	guard_btn.text = "守势·%s" % pl.stance if pl.stance != "" else "守势"


## 单位信息缩略行（布局 v0.4：顶部 56px 三条——细节在部位按钮与解说里看）
func _unit_line(u: Unit) -> String:
	if u == null:
		return "—"
	var tech_name := u.active_technique.display_name if u.active_technique != null else "无功法"
	var wname: String = "%s%s" % [u.weapon, "·脱手" if u.weapon_disarmed else ""]
	var s := "%s·%s·%s（%s）气血%d/%d 体力%d/%d 玄力%d/%d 魂力%d/%d 攻%.0f 防%.0f 架%.0f 药×%d" % [
		u.display_name, u.realm, tech_name, wname,
		int(ResourceSystem.current(u, "气血")), int(u.pools["气血"].max),
		int(ResourceSystem.current(u, "体力")), int(u.pools["体力"].max),
		int(ResourceSystem.current(u, "玄力")), int(u.pools["玄力"].max),
		int(ResourceSystem.current(u, "魂力")), int(u.pools["魂力"].max),
		u.attack_power, u.armor, u.parry, int(u.items.get("止血丹", 0)),
	]
	# 功法修为称号
	if u.active_technique != null and u.technique_proficiency.has(u.active_technique.id):
		s += " 修为「%s」" % Grades.title(u.technique_proficiency[u.active_technique.id])
	# 部位摘要：主用臂 + 非完好部位（细节见攻击时的部位按钮）
	var parts: Array[String] = []
	for part in u.body:
		var pd: Dictionary = u.body[part]
		if pd.state != BodySystem.PartState.OK or part == u.main_arm:
			parts.append("%s%s[%s%s]" % [part, "主" if part == u.main_arm else "", BodySystem.STATE_NAMES[pd.state], "·流血" if pd.bleeding else ""])
	s += " 部位:%s" % (" ".join(parts) if not parts.is_empty() else "无伤")
	# 守势
	if u.stance != "":
		s += " 守势:%s[%s]" % [u.stance, " ".join(u.guard_parts)]
	# 状态
	if not u.statuses.is_empty():
		var st: Array[String] = []
		for id in u.statuses:
			st.append("%s·%d回合" % [id, int(u.statuses[id].turns)])
		s += " 状态:" + " ".join(st)
	return s


## 解说输出（带颜色）
func log_nar(text: String, color: Color) -> void:
	log_rtl.push_color(color)
	log_rtl.append_text(text + "\n")
	log_rtl.pop()


func log(text: String) -> void:
	log_rtl.append_text(text + "\n")


func show_restart() -> void:
	restart_btn.visible = true
