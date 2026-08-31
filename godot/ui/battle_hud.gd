class_name BattleHud
extends Control
## P0 战斗 HUD（程序化构建，无 .tscn）。
## 布局（1280×720 固定）：左上=单位信息 · 右侧竖排=战斗解说 · 招式面板行 · 部位按钮行 · 操作按钮行。
## 全部用 position/size 定位——锚点对 Node2D 下的根 Control 有踩坑记录（见 git 历史）。

signal attack_pressed        # 普攻（英雄坛说式随机出招）
signal move_menu_pressed     # 招式面板（侠客风云传式手动选招）
signal switch_pressed        # 切换招式功法
signal defend_pressed
signal item_pressed
signal end_turn_pressed
signal part_selected(part: String)
signal move_selected(move_id: String)
signal restart_requested

const Grades := preload("res://scripts/cultivation_grades.gd")

var info_label: Label
var log_rtl: RichTextLabel
var action_row: HBoxContainer
var part_row: HBoxContainer
var move_row: HBoxContainer
var rule_toggle: CheckButton
var restart_btn: Button
var switch_btn: Button
var item_btn: Button
var _action_buttons: Array[Button] = []
var _item_used := false       # 本回合该丹药已用（每回合每种限一次）
var _battle = null


func _ready() -> void:
	# 根控件显式固定尺寸（P0 固定分辨率 1280x720）：
	# 锚点预设对 Node2D 下的根 Control 在 _ready 时机不生效（实测 rect 为 0），
	# 子控件锚点是相对本控件计算的，根没尺寸 → 子控件全跑到屏幕外。
	offset_right = 1280.0
	offset_bottom = 720.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根节点不挡输入，子控件各自接收

	# 左上：单位信息
	info_label = Label.new()
	info_label.position = Vector2(12, 12)
	info_label.size = Vector2(850, 170)
	add_child(info_label)

	# 右侧竖排：战斗解说面板（不遮挡棋盘与按钮）
	log_rtl = RichTextLabel.new()
	log_rtl.position = Vector2(890, 12)
	log_rtl.size = Vector2(378, 628)
	log_rtl.scroll_following = true
	add_child(log_rtl)

	# 招式面板行（手动选招，带 CD 显示）
	move_row = HBoxContainer.new()
	move_row.position = Vector2(12, 494)
	move_row.size = Vector2(1260, 44)
	move_row.add_theme_constant_override("separation", 6)
	add_child(move_row)

	# 部位按钮行
	part_row = HBoxContainer.new()
	part_row.position = Vector2(12, 556)
	part_row.size = Vector2(1260, 42)
	part_row.add_theme_constant_override("separation", 6)
	add_child(part_row)

	# 操作按钮行
	action_row = HBoxContainer.new()
	action_row.position = Vector2(12, 648)
	action_row.size = Vector2(1260, 44)
	action_row.add_theme_constant_override("separation", 8)
	add_child(action_row)

	var b := _make_button("普攻", func(): attack_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	b = _make_button("招式", func(): move_menu_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	switch_btn = _make_button("切换", func(): switch_pressed.emit())
	_action_buttons.append(switch_btn)
	action_row.add_child(switch_btn)
	b = _make_button("防御", func(): defend_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	item_btn = _make_button("丹药·止血", func(): item_pressed.emit())
	_action_buttons.append(item_btn)
	action_row.add_child(item_btn)
	b = _make_button("结束行动", func(): end_turn_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)

	rule_toggle = CheckButton.new()
	rule_toggle.text = "融入规则（耗玄力）"
	action_row.add_child(rule_toggle)

	restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.visible = false
	restart_btn.position = Vector2(600, 340)
	restart_btn.size = Vector2(160, 44)
	add_child(restart_btn)
	restart_btn.pressed.connect(func(): restart_requested.emit())

	enable_actions(false)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 36)
	b.pressed.connect(on_pressed)
	return b


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


## 弹出招式面板（当前激活功法的招式池，带 CD 状态）
func set_moves(unit) -> void:
	clear_moves()
	if unit.active_technique == null:
		return
	for m in unit.active_technique.moves:
		var cd := int(unit.cooldowns.get(m.id, 0))
		var label: String = m.display_name if cd <= 0 else "%s（CD%d）" % [m.display_name, cd]
		var mid: String = m.id
		var b := _make_button(label, func(): move_selected.emit(mid))
		b.disabled = cd > 0
		move_row.add_child(b)


func clear_moves() -> void:
	for child in move_row.get_children():
		child.queue_free()


## 弹出目标单位的可选部位按钮（已毁部位不可选）
func set_parts(unit) -> void:
	clear_parts()
	for part in unit.body:
		var pd: Dictionary = unit.body[part]
		if pd.state == BodySystem.PartState.DESTROYED:
			continue
		var p: String = part
		var label := "%s·%s" % [p, BodySystem.STATE_NAMES[pd.state]]
		var b := _make_button(label, func(): part_selected.emit(p))
		b.custom_minimum_size = Vector2(120, 32)
		part_row.add_child(b)


func clear_parts() -> void:
	for child in part_row.get_children():
		child.queue_free()


func update_state(battle) -> void:
	var actor: Unit = battle.current_actor
	var turn_text := actor.display_name if actor != null else "——"
	var hint := ""
	if actor == battle.player:
		hint = "\n▶ 轮到你：点棋盘空格移动（剩%d步）→ 普攻随机出招 / 「招式」手动选招 / 「切换」换功法 / 防御 / 丹药" % actor.move_left
	info_label.text = "【你】%s\n【对手】%s\n当前行动：%s%s" % [
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


func _unit_line(u: Unit) -> String:
	if u == null:
		return "—"
	var tech_name := u.active_technique.display_name if u.active_technique != null else "无功法"
	var main_name := u.main_technique.display_name if u.main_technique != null else "无主修"
	var s := "%s（%s·主修《%s》·出招《%s》·%s）气血%d/%d 体力%d/%d 玄力%d/%d 魂力%d/%d 攻击%.0f 防御%.0f 止血丹×%d" % [
		u.display_name, u.realm, main_name, tech_name, u.weapon,
		int(ResourceSystem.current(u, "气血")), int(u.pools["气血"].max),
		int(ResourceSystem.current(u, "体力")), int(u.pools["体力"].max),
		int(ResourceSystem.current(u, "玄力")), int(u.pools["玄力"].max),
		int(ResourceSystem.current(u, "魂力")), int(u.pools["魂力"].max),
		u.attack_power, u.armor, int(u.items.get("止血丹", 0)),
	]
	# 功法修为称号（英雄坛说四字量表）
	if u.active_technique != null and u.technique_proficiency.has(u.active_technique.id):
		var prof: float = u.technique_proficiency[u.active_technique.id]
		s += " | 修为「%s」" % Grades.title(prof)
	# 规则领悟（称号+粗分阶）
	var rl: Array[String] = []
	for rule in u.rules:
		var val: float = u.rules[rule]
		rl.append("%s·%s(%s)" % [rule, Grades.title(val), Grades.tier_name(val)])
	if not rl.is_empty():
		s += "\n领悟: " + " ".join(rl)
	# 部位状态
	var parts: Array[String] = []
	for part in u.body:
		var pd: Dictionary = u.body[part]
		parts.append("%s[%s%s]" % [part, BodySystem.STATE_NAMES[pd.state], "·流血" if pd.bleeding else ""])
	s += "\n部位: " + " ".join(parts)
	# 状态
	var st: Array[String] = []
	for id in u.statuses:
		st.append("%s·%d回合" % [id, int(u.statuses[id].turns)])
	if not st.is_empty():
		s += " | 状态: " + " ".join(st)
	if u.is_defending:
		s += " | 防御架势"
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
