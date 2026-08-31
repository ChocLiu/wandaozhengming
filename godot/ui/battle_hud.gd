class_name BattleHud
extends Control
## P0 战斗 HUD（程序化构建，无 .tscn）。
## 表现层职责：展示四池/部位状态/战斗日志，收集玩家输入——所有逻辑在 battle.gd 与六子系统。

signal attack_pressed
signal defend_pressed
signal item_pressed
signal end_turn_pressed
signal part_selected(part: String)
signal restart_requested

var info_label: Label
var log_rtl: RichTextLabel
var action_row: HBoxContainer
var part_row: HBoxContainer
var rule_toggle: CheckButton
var restart_btn: Button
var _action_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根节点不挡输入，子控件各自接收

	info_label = Label.new()
	info_label.position = Vector2(12, 12)
	info_label.size = Vector2(880, 180)
	add_child(info_label)

	log_rtl = RichTextLabel.new()
	log_rtl.anchor_top = 1.0
	log_rtl.anchor_bottom = 1.0
	log_rtl.offset_left = 12.0
	log_rtl.offset_top = -320.0
	log_rtl.offset_right = 880.0
	log_rtl.offset_bottom = -12.0
	log_rtl.scroll_following = true
	add_child(log_rtl)

	part_row = HBoxContainer.new()
	part_row.anchor_top = 1.0
	part_row.anchor_bottom = 1.0
	part_row.offset_left = 12.0
	part_row.offset_top = -160.0
	part_row.offset_right = 1240.0
	part_row.offset_bottom = -120.0
	part_row.add_theme_constant_override("separation", 6)
	add_child(part_row)

	action_row = HBoxContainer.new()
	action_row.anchor_top = 1.0
	action_row.anchor_bottom = 1.0
	action_row.offset_left = 12.0
	action_row.offset_top = -70.0
	action_row.offset_right = 1240.0
	action_row.offset_bottom = -28.0
	action_row.add_theme_constant_override("separation", 8)
	add_child(action_row)

	var b := _make_button("攻击", func(): attack_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	b = _make_button("防御", func(): defend_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	b = _make_button("丹药·止血", func(): item_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)
	b = _make_button("结束行动", func(): end_turn_pressed.emit())
	_action_buttons.append(b)
	action_row.add_child(b)

	rule_toggle = CheckButton.new()
	rule_toggle.text = "融入规则（耗玄力）"
	action_row.add_child(rule_toggle)

	restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.visible = false
	restart_btn.anchor_left = 0.5
	restart_btn.anchor_top = 0.5
	restart_btn.anchor_right = 0.5
	restart_btn.anchor_bottom = 0.5
	restart_btn.offset_left = -80.0
	restart_btn.offset_top = -20.0
	restart_btn.offset_right = 80.0
	restart_btn.offset_bottom = 20.0
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
	for b in _action_buttons:
		b.disabled = not enabled
	rule_toggle.disabled = not enabled
	if not enabled:
		clear_parts()


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
		hint = "\n▶ 轮到你：点「攻击」再选部位（可勾选「融入规则」），或防御 / 吃止血丹"
	info_label.text = "【你】%s\n【对手】%s\n当前行动：%s%s" % [
		_unit_line(battle.player),
		_unit_line(battle.opponent),
		turn_text, hint,
	]


func _unit_line(u: Unit) -> String:
	if u == null:
		return "—"
	var tech_name := u.technique.display_name if u.technique != null else "无功法"
	var s := "%s（%s·%s）气血%d/%d 体力%d/%d 玄力%d/%d 魂力%d/%d 防御%.0f 止血丹×%d" % [
		u.display_name, u.realm, tech_name,
		int(ResourceSystem.current(u, "气血")), int(u.pools["气血"].max),
		int(ResourceSystem.current(u, "体力")), int(u.pools["体力"].max),
		int(ResourceSystem.current(u, "玄力")), int(u.pools["玄力"].max),
		int(ResourceSystem.current(u, "魂力")), int(u.pools["魂力"].max),
		u.armor, int(u.items.get("止血丹", 0)),
	]
	var parts: Array[String] = []
	for part in u.body:
		var pd: Dictionary = u.body[part]
		parts.append("%s[%s%s]" % [part, BodySystem.STATE_NAMES[pd.state], "·流血" if pd.bleeding else ""])
	s += "\n部位: " + " ".join(parts)
	var st: Array[String] = []
	for id in u.statuses:
		st.append("%s(%ds)" % [id, int(u.statuses[id].duration)])
	if not st.is_empty():
		s += " | 状态: " + " ".join(st)
	if u.is_defending:
		s += " | 防御架势"
	return s


func log(text: String) -> void:
	log_rtl.append_text(text + "\n")


func show_restart() -> void:
	restart_btn.visible = true
