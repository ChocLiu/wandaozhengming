extends Node2D
## P0 战斗原型主控制器（内核与表现分离：内核=六子系统+Unit 纯数据，表现=本场景绘制+HUD）
## 对应文档：《战斗系统》v0.2。
## 演示循环：ATB 读条 → 移动(战棋)/攻击(选部位/融入规则)/防御/止血 → 速度+规则双维命中 → 破防模型 → 失血/要害死亡。
## 解说：Narration 武侠叙事模板（右侧面板）；修为：CultivationGrades 四字称号（英雄坛说36级量表）。

const Grades := preload("res://scripts/cultivation_grades.gd")
const Nar := preload("res://scripts/narration.gd")

const STANCE_BONUS := 100.0     # 防御架势的招架侧重加成
const RULE_INFUSE_COST := 10.0  # 融入规则消耗玄力
const RULE_CRUSH_BONUS := 80.0  # 规则碾压（粗分阶差≥1）的命中修正
const RULE_CRUSH_STEP := 1      # 粗分阶差几阶算「碾压」
const BLEED_RATE := 2.0         # 每处流血创伤每秒失血
const ARMOR_WEAR := 4.0         # 磨防：每次磨掉的防御
const WEAR_THRESHOLD := 6.0     # 防御高出攻击力不超过此值 → 算「相近」进入磨防
const MOVE_STAMINA_COST := 1.0  # 走 1 格消耗体力
const PROF_GAIN := 5.0          # 出招破防命中，功法修为 +5（一称号档）

const CELL := 60.0
const ORIGIN := Vector2(60, 80)

var player: Unit
var opponent: Unit
var current_actor: Unit = null
var current_acted := false        # 本回合是否已出手（侠客风云传式：移动与出招顺序自由，出招限一次）
var battle_over := false
var hud: BattleHud

# 截图调试模式：命令行加 -- --shot，每秒存一张图到 _debug/，6 张后自动退出
var _shot_mode := false
var _shot_elapsed := 0.0
var _shot_count := 0


func _ready() -> void:
	_shot_mode = "--shot" in OS.get_cmdline_user_args()
	randomize()
	player = UnitSystem.spawn({
		"id": "player", "display_name": "你", "team": 0, "realm": "金丹",
		"speed": 55.0, "agility": 40.0, "move_speed": 55.0,
		"attack_power": 30.0, "armor": 22.0,
		"pools": ResourceSystem.init_pools(100.0, 100.0, 80.0, 50.0),
		"rules": {"空间": 60.0},
		"technique_proficiency": {"qinglian_jiange": 15.0},
		"dao_proficiency": {"剑道": 20.0},
		"pos": Vector2i(2, 5),
		"items": {"止血丹": 3},
	})
	player.technique = load("res://resources/techniques/qinglian.tres")
	opponent = UnitSystem.spawn({
		"id": "opponent", "display_name": "散修", "team": 1, "realm": "练气",
		"speed": 75.0, "agility": 90.0, "move_speed": 75.0,
		"attack_power": 20.0, "armor": 35.0,
		"pools": ResourceSystem.init_pools(90.0, 110.0, 60.0, 40.0),
		"rules": {"空间": 25.0, "火": 90.0},
		"technique_proficiency": {"fentian_jue": 10.0},
		"dao_proficiency": {},
		"pos": Vector2i(7, 5),
		"items": {"止血丹": 2},
	})
	opponent.technique = load("res://resources/techniques/fentian.tres")

	TimelineSystem.unit_ready.connect(_on_unit_ready)
	hud = BattleHud.new()
	add_child(hud)
	hud.attack_pressed.connect(_on_attack_requested)
	hud.defend_pressed.connect(_on_defend_requested)
	hud.item_pressed.connect(_on_item_requested)
	hud.end_turn_pressed.connect(_on_end_turn_requested)
	hud.part_selected.connect(_on_part_selected)
	hud.restart_requested.connect(_on_restart)
	EventBus.battle_started.emit()
	_say(Nar.start())
	hud.log("提示：对手敏捷极高——普通出招会被招架，试试勾选「融入规则」（你的空间领悟·小成碾压他）")


func _process(delta: float) -> void:
	if _shot_mode:
		_take_debug_shots(delta)
	if battle_over:
		return
	StatusSystem.tick(delta)
	# 失血结算：未止血的创伤持续流失气血（《战斗系统》§2.3）
	for u in UnitSystem.alive_units():
		var bleed: float = BodySystem.bleed_amount(u)
		if bleed > 0.0:
			ResourceSystem.drain(u, "气血", bleed * BLEED_RATE * delta)
		_check_death(u)
	if battle_over:
		return
	TimelineSystem.process_timeline(delta)
	hud.update_state(self)
	queue_redraw()


# ---------- 行动流程 ----------

func _on_unit_ready(u: Unit) -> void:
	if battle_over:
		return
	TimelineSystem.active = false  # 冻结读条（战斗暂停=思考时间）
	current_actor = u
	current_acted = false
	u.move_left = maxi(1, ceili(u.move_speed / 20.0))
	hud.rule_toggle.button_pressed = false
	if u == player:
		hud.enable_actions(true)
	else:
		hud.enable_actions(false)
		_ai_act_async(u)
	_say(Nar.turn(u, u.move_left))


func _end_turn(u: Unit) -> void:
	u.move_left = 0
	current_acted = false
	TimelineSystem.begin_turn(u)
	current_actor = null
	hud.enable_actions(false)
	hud.clear_parts()


# ---------- 玩家输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if battle_over or current_actor != player:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _pixel_to_cell(event.position)
		if cell.x >= 0:
			_try_move(player, cell)


func _try_move(u: Unit, cell: Vector2i) -> void:
	if not FieldSystem.in_bounds(cell):
		return
	if cell == u.pos:
		return
	if cell == opponent.pos:
		return
	var dist := _manhattan(u.pos, cell)
	if dist > u.move_left:
		return
	var cost := float(dist) * MOVE_STAMINA_COST
	if ResourceSystem.current(u, "体力") < cost:
		_say(Nar.move_fail(u))
		return
	ResourceSystem.drain(u, "体力", cost)
	u.pos = cell
	u.move_left -= dist
	hud.clear_parts()
	_say(Nar.move(u, dist))
	if current_acted and u.move_left <= 0:
		_end_turn(u)


func _on_attack_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	var tech: Technique = player.technique
	if tech == null:
		return
	var dist := _chebyshev(player.pos, opponent.pos)
	if dist < tech.range_min or dist > tech.range_max:
		_say(Nar.out_of_range(player.move_left))
		return
	hud.set_parts(opponent)


func _on_part_selected(part: String) -> void:
	if current_actor != player or current_acted:
		return
	_do_attack(player, opponent, part, hud.rule_toggle.button_pressed)
	current_acted = true
	if player.move_left <= 0:
		_end_turn(player)


func _on_defend_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	_do_defend(player)
	current_acted = true
	if player.move_left <= 0:
		_end_turn(player)


func _on_item_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	_do_item(player)
	current_acted = true
	if player.move_left <= 0:
		_end_turn(player)


func _on_end_turn_requested() -> void:
	if current_actor != player:
		return
	hud.log("你结束行动")
	_end_turn(player)


func _on_restart() -> void:
	get_tree().reload_current_scene()


# ---------- AI ----------

func _ai_act_async(u: Unit) -> void:
	await get_tree().create_timer(0.9).timeout
	if battle_over:
		return
	var target: Unit = player if u == opponent else opponent
	# 1) 不在射程 → 逼近（移动先行，侠客风云传式）
	var range_max := 1
	if u.technique != null:
		range_max = u.technique.range_max
	if _chebyshev(u.pos, target.pos) > range_max:
		_ai_move_toward(u, target)
	# 2) 在射程内 → 行动一次
	if not current_acted and _chebyshev(u.pos, target.pos) <= range_max:
		var roll := randf()
		if _bleeding(u) and int(u.items.get("止血丹", 0)) > 0 and roll < 0.25:
			_do_item(u)
		elif roll < 0.85:
			_do_attack(u, target, _random_part(target), false)
		else:
			_do_defend(u)
		current_acted = true
	_end_turn(u)


## 简单贪婪逼近：每步选择切比雪夫距离缩小的相邻格，进入射程即停
func _ai_move_toward(u: Unit, target: Unit) -> void:
	var steps := 0
	var range_max := 1
	if u.technique != null:
		range_max = u.technique.range_max
	while steps < u.move_left and _chebyshev(u.pos, target.pos) > range_max:
		if ResourceSystem.current(u, "体力") < MOVE_STAMINA_COST:
			break
		var best := u.pos
		var best_d := _chebyshev(u.pos, target.pos)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = u.pos + d
			if not FieldSystem.in_bounds(np) or np == target.pos:
				continue
			var nd := _chebyshev(np, target.pos)
			if nd < best_d:
				best = np
				best_d = nd
		if best == u.pos:
			break
		u.pos = best
		steps += 1
	if steps > 0:
		ResourceSystem.drain(u, "体力", float(steps) * MOVE_STAMINA_COST)
		_say(Nar.move(u, steps))


# ---------- 行动结算 ----------

func _do_attack(attacker: Unit, target: Unit, part: String, infused: bool) -> void:
	var tech: Technique = attacker.technique
	if tech == null:
		return
	if not target.body.has(part):
		return
	# 射程检查（超出不消耗资源）
	var dist := _chebyshev(attacker.pos, target.pos)
	if dist < tech.range_min or dist > tech.range_max:
		_say(Nar.out_of_range(attacker.move_left))
		return
	if not ResourceSystem.spend(attacker, tech.cost_pool, tech.cost_amount):
		_say(Nar.no_stamina(attacker, tech.cost_pool, tech))
		return
	# —— 速度维度（《战斗系统》§4）——
	var atk_speed: float = (
		(attacker.speed + attacker.agility + tech.speed_bonus)
		* ResourceSystem.stamina_penalty(attacker) * StatusSystem.speed_modifier(attacker)
	)
	var def_stance: float = STANCE_BONUS if target.is_defending else 0.0
	var def_speed: float = (
		(target.speed + target.agility * 0.5 + def_stance)
		* ResourceSystem.stamina_penalty(target) * StatusSystem.speed_modifier(target)
	)
	# —— 规则维度（《战斗系统》§4.1）：融入规则，粗分阶差≥1=碾压 ——
	var rule_bonus := 0.0
	if infused:
		var rule: String = _pick_rule(attacker, tech)
		if rule == "":
			_say(Nar.no_rule())
		elif ResourceSystem.spend(attacker, "玄力", RULE_INFUSE_COST):
			var diff: int = Grades.tier(attacker.rules.get(rule, 0.0)) - Grades.tier(target.rules.get(rule, 0.0))
			if diff >= RULE_CRUSH_STEP:
				rule_bonus = RULE_CRUSH_BONUS
				_say(Nar.rule_crush(attacker, rule, Grades.tier_name(attacker.rules.get(rule, 0.0))))
			else:
				_say(Nar.rule_fail(attacker, rule))
		else:
			_say(Nar.no_xuan())
	var total_atk: float = atk_speed + rule_bonus
	_say(Nar.speed_contest(total_atk, def_speed))
	if total_atk > def_speed:
		_apply_hit(attacker, target, part)
	else:
		_say(Nar.parry(attacker, target))
		ResourceSystem.drain(target, "体力", 5.0)


## 破防模型（《战斗系统》§5）：远低于→无伤 / 相近→磨防 / 高于→破防
func _apply_hit(attacker: Unit, target: Unit, part: String) -> void:
	var ap: float = attacker.attack_power
	if ap > target.armor:
		_say(Nar.attack_break(attacker, target, attacker.technique, part))
		BodySystem.hurt(target, part, 1)
		# 功法修为精进（命中 +5，一称号档）
		_gain_proficiency(attacker)
		# 要害被毁（一击毙命途）
		var b: Dictionary = target.body[part]
		if b.state == BodySystem.PartState.DESTROYED and b.vital:
			_say(Nar.attack_vital(attacker, target, part))
		# 功法附加机制：焚天诀命中附加灼烧（机制脚本后置前的占位实现）
		if attacker.technique != null and attacker.technique.id == "fentian_jue":
			StatusSystem.add_status(target, "灼烧", 6.0)
			_say(Nar.burn(target))
	elif target.armor - ap <= WEAR_THRESHOLD:
		target.armor = maxf(target.armor - ARMOR_WEAR, 0.0)
		_say(Nar.wear(attacker, target))
	else:
		_say(Nar.no_damage(attacker, target))


func _gain_proficiency(u: Unit) -> void:
	var tech: Technique = u.technique
	if tech == null:
		return
	var before: float = u.technique_proficiency.get(tech.id, 0.0)
	u.technique_proficiency[tech.id] = before + PROF_GAIN
	if Grades.title(before) != Grades.title(before + PROF_GAIN):
		_say(Nar.proficiency_up(u, tech, Grades.title(before + PROF_GAIN)))


func _do_defend(u: Unit) -> void:
	if not ResourceSystem.spend(u, "体力", 5.0):
		_say(Nar.move_fail(u))
		return
	u.is_defending = true
	_say(Nar.defend(u))


func _do_item(u: Unit) -> void:
	if int(u.items.get("止血丹", 0)) <= 0:
		_say(Nar.no_item(u))
		return
	u.items["止血丹"] = int(u.items["止血丹"]) - 1
	BodySystem.seal_wounds(u)
	_say(Nar.seal(u))


func _check_death(u: Unit) -> void:
	if not u.alive:
		return
	var cause := ""
	if ResourceSystem.current(u, "气血") <= 0.0:
		cause = "失血"
	elif BodySystem.has_destroyed_vital(u):
		cause = "要害被毁"
	if cause != "":
		u.alive = false
		EventBus.unit_died.emit(u, cause)
		_say(Nar.death(u, cause))
		_battle_end(u)


func _battle_end(loser: Unit) -> void:
	battle_over = true
	TimelineSystem.active = false
	hud.enable_actions(false)
	hud.show_restart()
	var winner: Unit = opponent if loser == player else player
	_say(Nar.end(winner))


# ---------- 工具 ----------

func _say(d: Dictionary) -> void:
	hud.log_nar(d.t, d.c)


func _pick_rule(attacker: Unit, tech: Technique) -> String:
	for rule in tech.rule_slots:
		if attacker.rules.has(rule):
			return rule
	return ""


func _random_part(u: Unit) -> String:
	var parts: Array[String] = []
	for part in u.body:
		if u.body[part].state != BodySystem.PartState.DESTROYED:
			parts.append(part)
	if parts.is_empty():
		return "躯干"
	return parts[randi() % parts.size()]


func _bleeding(u: Unit) -> bool:
	return BodySystem.bleed_amount(u) > 0.0


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _pixel_to_cell(p: Vector2) -> Vector2i:
	var cell := Vector2i(floori((p.x - ORIGIN.x) / CELL), floori((p.y - ORIGIN.y) / CELL))
	if not FieldSystem.in_bounds(cell):
		return Vector2i(-1, -1)
	return cell


# ---------- 表现层绘制 ----------

func _draw() -> void:
	for x in range(FieldSystem.GRID_W + 1):
		draw_line(
			ORIGIN + Vector2(x * CELL, 0), ORIGIN + Vector2(x * CELL, FieldSystem.GRID_H * CELL),
			Color(0.32, 0.32, 0.5), 1.0)
	for y in range(FieldSystem.GRID_H + 1):
		draw_line(
			ORIGIN + Vector2(0, y * CELL), ORIGIN + Vector2(FieldSystem.GRID_W * CELL, y * CELL),
			Color(0.32, 0.32, 0.5), 1.0)
	# 可移动范围高亮（玩家回合）
	if current_actor == player and not battle_over:
		for x in range(FieldSystem.GRID_W):
			for y in range(FieldSystem.GRID_H):
				var c := Vector2i(x, y)
				if c == player.pos or c == opponent.pos:
					continue
				if _manhattan(player.pos, c) <= player.move_left:
					draw_rect(
						Rect2(ORIGIN + Vector2(x * CELL + 10.0, y * CELL + 10.0), Vector2(CELL - 20, CELL - 20)),
						Color(0.35, 0.9, 0.45, 0.18))
	_draw_unit(player, Color(0.4, 0.8, 1.0))
	_draw_unit(opponent, Color(1.0, 0.45, 0.45))


func _draw_unit(u: Unit, color: Color) -> void:
	if u == null:
		return
	var top_left := ORIGIN + Vector2(u.pos.x * CELL + 6.0, u.pos.y * CELL + 6.0)
	draw_rect(Rect2(top_left, Vector2(CELL - 12, CELL - 12)), color)
	# 当前行动者高亮描边
	if current_actor == u:
		draw_rect(Rect2(top_left, Vector2(CELL - 12, CELL - 12)), Color(1.0, 0.9, 0.3), false, 3.0)
	# ATB 行动条
	var bar_w := (CELL - 12) * clampf(u.atb_progress / 100.0, 0.0, 1.0)
	draw_rect(Rect2(top_left + Vector2(0, CELL - 2), Vector2(bar_w, 6)), Color(0.9, 0.85, 0.3))


# ---------- 调试 ----------

## 注意：不能叫 log——与 GDScript 内置数学函数 log() 撞名
func log_msg(text: String) -> void:
	if hud != null:
		hud.log(text)


func _take_debug_shots(delta: float) -> void:
	_shot_elapsed += delta
	if _shot_elapsed < float(_shot_count + 1):
		return
	_shot_count += 1
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://_debug")
	img.save_png("res://_debug/shot_%d.png" % _shot_count)
	print("DEBUG shot %d saved (actor=%s)" % [_shot_count, current_actor.display_name if current_actor != null else "none"])
	if _shot_count == 1:
		print("DEBUG hud rect=", hud.get_rect())
		print("DEBUG log_rtl pos=", hud.log_rtl.position, " size=", hud.log_rtl.size)
		print("DEBUG action_row pos=", hud.action_row.position, " size=", hud.action_row.size)
	if _shot_count >= 6:
		get_tree().quit()
