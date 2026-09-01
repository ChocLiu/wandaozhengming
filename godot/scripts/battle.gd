extends Node2D
## P0.5 战斗原型主控制器（内核与表现分离：内核=六子系统+Unit 纯数据，表现=本场景绘制+HUD）
## 对应文档：《战斗系统》v0.2 + 挂载体系。
## 演示循环：ATB 读条 → 移动/普攻(随机招式)/招式面板(手动选招带CD)/切换功法/防御/止血
##           → 速度+规则双维命中 → 破防模型 → 失血/要害死亡。
## 攻击范围 = 招式基础射程 + 武器修正；面板 = 基础 + 挂载加成 + 武器（有界小属性层）。

const Grades := preload("res://scripts/cultivation_grades.gd")
const Nar := preload("res://scripts/narration.gd")
const WeaponData := preload("res://scripts/weapons.gd")

const STANCE_BONUS := 100.0     # 防御架势的招架侧重加成
const RULE_INFUSE_COST := 10.0  # 融入规则消耗玄力
const RULE_CRUSH_BONUS := 80.0  # 规则碾压（粗分阶差≥1）的命中修正
const RULE_CRUSH_STEP := 1      # 粗分阶差几阶算「碾压」
const BLEED_PER_TURN := 4.0     # 每处流血创伤每回合失血（该单位行动时结算——挂机不掉血）
const ARMOR_WEAR := 4.0         # 磨防：每次磨掉的防御
const WEAR_THRESHOLD := 6.0     # 防御高出攻击力不超过此值 → 算「相近」进入磨防
const MOVE_STAMINA_COST := 1.0  # 走 1 格消耗体力
const SWITCH_COST := 10.0       # 切换招式功法耗体力（不算出招）
const PROF_GAIN := 5.0          # 出招破防命中，功法修为 +5（一称号档）

const CELL := 60.0
const ORIGIN := Vector2(60, 80)

var player: Unit
var opponent: Unit
var current_actor: Unit = null
var current_acted := false        # 本回合是否已出手（移动与出招顺序自由，出招限一次）
var pending_move: Move = null     # 待出手的招式（普攻随机或招式面板所选）
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
		"base_speed": 55.0, "base_agility": 40.0, "base_move_speed": 55.0,
		"base_attack_power": 18.0, "base_armor": 20.0,
		"pools": ResourceSystem.init_pools(100.0, 100.0, 80.0, 50.0),
		"rules": {"空间": 60.0},
		"technique_proficiency": {"qinglian_jiange": 15.0, "pojunjuan": 5.0},
		"dao_proficiency": {"剑道": 20.0},
		"pos": Vector2i(2, 5),
		"items": {"止血丹": 3},
	})
	_mount(player,
		load("res://resources/techniques/qinglian_xinfa.tres"),
		[load("res://resources/techniques/qinglian_jiange.tres"),
		 load("res://resources/techniques/pojunjuan.tres")])
	opponent = UnitSystem.spawn({
		"id": "opponent", "display_name": "散修", "team": 1, "realm": "练气",
		"base_speed": 75.0, "base_agility": 90.0, "base_move_speed": 75.0,
		"base_attack_power": 8.0, "base_armor": 35.0,
		"pools": ResourceSystem.init_pools(90.0, 110.0, 60.0, 40.0),
		"rules": {"空间": 25.0, "火": 90.0},
		"technique_proficiency": {"fentian_jue": 10.0},
		"dao_proficiency": {},
		"pos": Vector2i(7, 5),
		"items": {"止血丹": 2},
	})
	_mount(opponent,
		load("res://resources/techniques/fentian_jue.tres"),
		[load("res://resources/techniques/fentian_jue.tres")])

	TimelineSystem.unit_ready.connect(_on_unit_ready)
	hud = BattleHud.new()
	add_child(hud)
	hud.attack_pressed.connect(_on_attack_requested)
	hud.move_menu_pressed.connect(_on_move_menu_requested)
	hud.switch_pressed.connect(_on_switch_requested)
	hud.defend_pressed.connect(_on_defend_requested)
	hud.item_pressed.connect(_on_item_requested)
	hud.end_turn_pressed.connect(_on_end_turn_requested)
	hud.part_selected.connect(_on_part_selected)
	hud.move_selected.connect(_on_move_selected)
	hud.restart_requested.connect(_on_restart)
	EventBus.battle_started.emit()
	_say(Nar.start())
	hud.log("提示：普攻随机出招；「招式」手动选招（带冷却）；「切换」换用《破军拳》（耗体力不算出招）；对手敏捷极高，试试「融入规则」")


## 挂载：主修槽 + 招式槽，激活第一门招式功法，重算面板与四池上限
func _mount(u: Unit, main_tech: Technique, move_techs: Array) -> void:
	u.main_technique = main_tech
	u.move_techniques = []
	for t in move_techs:
		u.move_techniques.append(t)
	if not u.move_techniques.is_empty():
		u.active_technique = u.move_techniques[0]
		u.weapon = u.active_technique.weapon_req
	u.base_pool_max = _pool_max_snapshot(u.pools)
	_recalc_stats(u)
	_recalc_pools(u)


func _pool_max_snapshot(pools: Dictionary) -> Dictionary:
	var d := {}
	for pool in pools:
		d[pool] = pools[pool]["max"]
	return d


## 有效面板 = 基础 + 主修/激活功法挂载加成 + 武器
func _recalc_stats(u: Unit) -> void:
	u.speed = u.base_speed + _mount_bonus(u, "bonus_speed")
	u.agility = u.base_agility
	u.move_speed = u.base_move_speed + _mount_bonus(u, "bonus_speed")
	u.armor = u.base_armor + _mount_bonus(u, "bonus_armor")
	u.attack_power = u.base_attack_power + WeaponData.attack(u.weapon) + _mount_bonus(u, "bonus_attack")


func _recalc_pools(u: Unit) -> void:
	var mapping := {"气血": "bonus_qi_max", "体力": "bonus_stamina_max", "玄力": "bonus_xuan_max", "魂力": ""}
	for pool in mapping:
		var extra := 0.0
		if mapping[pool] != "":
			for t in [u.main_technique, u.active_technique]:
				if t != null:
					extra += t.get(mapping[pool])
		var p: Dictionary = u.pools[pool]
		p.max = u.base_pool_max[pool] + extra
		p.cur = minf(p.cur, p.max)


func _mount_bonus(u: Unit, field: String) -> float:
	var total := 0.0
	for t in [u.main_technique, u.active_technique]:
		if t != null:
			total += t.get(field)
	return total


func _process(delta: float) -> void:
	if _shot_mode:
		_take_debug_shots(delta)
	if battle_over:
		return
	# 失血与持续状态按回合结算（该单位行动时，见 _on_unit_ready）——不按实时
	for u in UnitSystem.alive_units():
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
	pending_move = null
	u.move_left = maxi(1, ceili(u.move_speed / 20.0))
	u.items_used_this_turn.clear()  # 丹药每回合每种限用一次
	_tick_cooldowns(u)
	# —— 回合结算：失血与持续状态（按回合，不按实时——挂机不会流血而死）——
	var bleed: float = BodySystem.bleed_amount(u)
	if bleed > 0.0:
		ResourceSystem.drain(u, "气血", bleed * BLEED_PER_TURN)
		_say(Nar.bleed_tick(u))
	StatusSystem.tick_turn(u)
	_check_death(u)
	if battle_over:
		return
	hud.rule_toggle.button_pressed = false
	if u == player:
		hud.enable_actions(true)
	else:
		hud.enable_actions(false)
		_ai_act_async(u)
	_say(Nar.turn(u, u.move_left))


func _tick_cooldowns(u: Unit) -> void:
	for id in u.cooldowns.keys().duplicate():
		u.cooldowns[id] = int(u.cooldowns[id]) - 1
		if int(u.cooldowns[id]) <= 0:
			u.cooldowns.erase(id)


func _end_turn(u: Unit) -> void:
	u.move_left = 0
	current_acted = false
	pending_move = null
	TimelineSystem.begin_turn(u)
	current_actor = null
	hud.enable_actions(false)
	hud.clear_parts()
	hud.clear_moves()


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
	hud.clear_moves()
	_say(Nar.move(u, dist))
	if current_acted and u.move_left <= 0:
		_end_turn(u)


## 普攻：英雄坛说式——从当前功法招式池随机出一招
func _on_attack_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	var move := _pick_random_move(player)
	if move == null:
		_say(Nar.all_cd(player.active_technique))
		return
	if not _in_range(player, opponent, move):
		_say(Nar.out_of_range(player.move_left))
		return
	pending_move = move
	hud.set_parts(opponent)


## 招式面板：侠客风云传式——手动选招（带冷却）
func _on_move_menu_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	hud.set_moves(player)


func _on_move_selected(move_id: String) -> void:
	if current_actor != player or current_acted:
		return
	var move := _find_move(player, move_id)
	if move == null:
		return
	if _move_cd(player, move) > 0:
		_say(Nar.cd_busy(move))
		return
	if not _in_range(player, opponent, move):
		_say(Nar.out_of_range(player.move_left))
		hud.clear_moves()
		return
	pending_move = move
	hud.clear_moves()
	hud.set_parts(opponent)


func _on_part_selected(part: String) -> void:
	if current_actor != player or current_acted:
		return
	if pending_move == null:
		return
	var move: Move = pending_move
	pending_move = null
	_do_attack(player, opponent, part, move, hud.rule_toggle.button_pressed)
	current_acted = true
	if player.move_left <= 0:
		_end_turn(player)


## 切换招式功法（耗体力，不算出招；主修玄术不可切换——挂载规则）
func _on_switch_requested() -> void:
	if current_actor != player:
		return
	if player.move_techniques.size() < 2:
		_say(Nar.no_switch())
		return
	if not ResourceSystem.spend(player, "体力", SWITCH_COST):
		_say(Nar.move_fail(player))
		return
	var idx := player.move_techniques.find(player.active_technique)
	var next: Technique = player.move_techniques[(idx + 1) % player.move_techniques.size()]
	player.active_technique = next
	player.weapon = next.weapon_req
	_recalc_stats(player)
	_recalc_pools(player)
	pending_move = null
	hud.clear_parts()
	hud.clear_moves()
	_say(Nar.switch_tech(player, next, player.weapon))


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
	if current_actor != player:
		return
	_do_item(player)
	# 丹药不占出招机会：已出手且无步数时才自动结束回合
	if current_acted and player.move_left <= 0:
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
	# 1) 不在最远可用招式射程内 → 逼近（移动先行，侠客风云传式）
	var want_range := _max_ready_range(u)
	if _chebyshev(u.pos, target.pos) > want_range:
		_ai_move_toward(u, target, want_range)
	# 2) 丹药不占行动——流血先吃药（每回合每种限一次），再出招
	if _bleeding(u) and int(u.items.get("止血丹", 0)) > 0 and int(u.items_used_this_turn.get("止血丹", 0)) < 1 and randf() < 0.3:
		_do_item(u)
	# 3) 在射程内 → 随机出招（英雄坛说式），无招可用则防御兜底
	if not current_acted:
		var move := _pick_random_move(u)
		if move != null and _in_range(u, target, move):
			_do_attack(u, target, _random_part(target), move, false)
		else:
			_do_defend(u)
		current_acted = true
	_end_turn(u)


## 简单贪婪逼近：每步选择切比雪夫距离缩小的相邻格，进入射程即停
func _ai_move_toward(u: Unit, target: Unit, want_range: int) -> void:
	var steps := 0
	while steps < u.move_left and _chebyshev(u.pos, target.pos) > want_range:
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

func _do_attack(attacker: Unit, target: Unit, part: String, move: Move, infused: bool) -> void:
	if move == null or not target.body.has(part):
		return
	if _move_cd(attacker, move) > 0:
		_say(Nar.cd_busy(move))
		return
	# 射程检查（招式基础射程 + 武器修正，超出不消耗资源）
	if not _in_range(attacker, target, move):
		_say(Nar.out_of_range(attacker.move_left))
		return
	if not ResourceSystem.spend(attacker, move.cost_pool, move.cost_amount):
		_say(Nar.no_stamina(attacker, move.cost_pool, move))
		return
	# —— 速度维度（《战斗系统》§4）：移速+敏捷+招式加成 ——
	var atk_speed: float = (
		(attacker.speed + attacker.agility + move.speed_bonus)
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
		var rule: String = _pick_rule(attacker)
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
		_apply_hit(attacker, target, part, move)
	else:
		_say(Nar.parry(attacker, target))
		ResourceSystem.drain(target, "体力", 5.0)
	# 冷却（侠客风云传式：起手式 0 CD，大招隔回合）
	if move.cooldown > 0:
		attacker.cooldowns[move.id] = move.cooldown


## 破防模型（《战斗系统》§5）：远低于→无伤 / 相近→磨防 / 高于→破防
func _apply_hit(attacker: Unit, target: Unit, part: String, move: Move) -> void:
	var ap: float = attacker.attack_power * move.power_mod
	if ap > target.armor:
		_say(Nar.attack_break(attacker, target, attacker.active_technique, move, part))
		BodySystem.hurt(target, part, 1)
		# 功法修为精进（命中 +5，一称号档）
		_gain_proficiency(attacker)
		# 要害被毁（一击毙命途）
		var b: Dictionary = target.body[part]
		if b.state == BodySystem.PartState.DESTROYED and b.vital:
			_say(Nar.attack_vital(attacker, target, part))
		# 招式机制标签
		if "灼烧" in move.effects:
			StatusSystem.add_status(target, "灼烧", 3)
			_say(Nar.burn(target))
	elif target.armor - ap <= WEAR_THRESHOLD:
		target.armor = maxf(target.armor - ARMOR_WEAR, 0.0)
		_say(Nar.wear(attacker, target))
	else:
		_say(Nar.no_damage(attacker, target))


func _gain_proficiency(u: Unit) -> void:
	var tech: Technique = u.active_technique
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


## 丹药规则：每回合每种限用一次、不占攻防行动次数（《战斗系统》§6）
func _do_item(u: Unit) -> void:
	if int(u.items_used_this_turn.get("止血丹", 0)) >= 1:
		_say(Nar.item_used_this_turn(u))
		return
	if int(u.items.get("止血丹", 0)) <= 0:
		_say(Nar.no_item(u))
		return
	u.items["止血丹"] = int(u.items["止血丹"]) - 1
	u.items_used_this_turn["止血丹"] = int(u.items_used_this_turn.get("止血丹", 0)) + 1
	BodySystem.seal_wounds(u)
	_say(Nar.seal(u))
	if u == player:
		hud.set_item_used(true)


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


# ---------- 招式工具 ----------

func _pick_random_move(u: Unit) -> Move:
	var tech: Technique = u.active_technique
	if tech == null or tech.moves.is_empty():
		return null
	var ready: Array[Move] = []
	for m in tech.moves:
		if _move_cd(u, m) <= 0:
			ready.append(m)
	if ready.is_empty():
		return null
	return ready[randi() % ready.size()]


func _find_move(u: Unit, move_id: String) -> Move:
	if u.active_technique == null:
		return null
	for m in u.active_technique.moves:
		if m.id == move_id:
			return m
	return null


func _move_cd(u: Unit, move: Move) -> int:
	return int(u.cooldowns.get(move.id, 0))


func _eff_range(u: Unit, move: Move) -> Vector2i:
	var bonus := WeaponData.range_bonus(u.weapon)
	return Vector2i(move.range_min + bonus, move.range_max + bonus)


func _in_range(u: Unit, target: Unit, move: Move) -> bool:
	var r := _eff_range(u, move)
	var dist := _chebyshev(u.pos, target.pos)
	return dist >= r.x and dist <= r.y


func _max_ready_range(u: Unit) -> int:
	var r := 1
	if u.active_technique != null:
		for m in u.active_technique.moves:
			if _move_cd(u, m) <= 0:
				r = maxi(r, _eff_range(u, m).y)
	return r


# ---------- 其他工具 ----------

func _say(d: Dictionary) -> void:
	hud.log_nar(d.t, d.c)


func _pick_rule(attacker: Unit) -> String:
	var tech: Technique = attacker.active_technique
	if tech == null:
		return ""
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
		return "胸腹"
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
