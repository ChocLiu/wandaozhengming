extends Node2D
## P0 战斗原型主控制器（内核与表现分离：内核=六子系统+Unit 纯数据，表现=本场景绘制+HUD）
## 对应文档：《战斗系统》v0.2。
## 演示循环：ATB 读条 → 攻击(选部位/融入规则)/防御/止血/放弃 → 速度+规则双维命中 → 破防模型 → 失血/要害死亡。

const STANCE_BONUS := 100.0     # 防御架势的招架侧重加成
const RULE_INFUSE_COST := 10.0  # 融入规则消耗玄力
const RULE_CRUSH_BONUS := 80.0  # 规则碾压（领悟差≥1阶）的命中修正
const RULE_CRUSH_STEP := 1      # 规则领悟差几阶算「碾压」
const BLEED_RATE := 2.0         # 每处流血创伤每秒失血
const ARMOR_WEAR := 4.0         # 磨防：每次磨掉的防御
const WEAR_THRESHOLD := 6.0     # 防御高出攻击力不超过此值 → 算「相近」进入磨防

const CELL := 60.0
const ORIGIN := Vector2(60, 80)

var player: Unit
var opponent: Unit
var current_actor: Unit = null
var battle_over := false
var hud: BattleHud


func _ready() -> void:
	randomize()
	player = UnitSystem.spawn({
		"id": "player", "display_name": "你", "team": 0, "realm": "金丹",
		"speed": 55.0, "agility": 40.0, "attack_power": 30.0, "armor": 22.0,
		"pools": ResourceSystem.init_pools(100.0, 100.0, 80.0, 50.0),
		"rules": {"空间": 2},
		"pos": Vector2i(2, 5),
		"items": {"止血丹": 3},
	})
	player.technique = load("res://resources/techniques/qinglian.tres")
	opponent = UnitSystem.spawn({
		"id": "opponent", "display_name": "散修", "team": 1, "realm": "练气",
		"speed": 75.0, "agility": 90.0, "attack_power": 20.0, "armor": 35.0,
		"pools": ResourceSystem.init_pools(90.0, 110.0, 60.0, 40.0),
		"rules": {"空间": 1, "火": 2},
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
	log_msg("P0 战斗原型已启动：ATB 读条 · 部位 · 四池 · 速度/规则双维命中 · 破防")
	log_msg("提示：对手敏捷极高——普通出招会被招架，试试勾选「融入规则」（你的空间规则碾压他）")


func _process(delta: float) -> void:
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
	if u == player:
		log_msg("轮到你行动")
		hud.enable_actions(true)
	else:
		hud.enable_actions(false)
		_ai_act_async(u)


func _end_turn(u: Unit) -> void:
	TimelineSystem.begin_turn(u)
	current_actor = null
	hud.enable_actions(false)


# ---------- 玩家输入 ----------

func _on_attack_requested() -> void:
	if current_actor != player:
		return
	hud.set_parts(opponent)


func _on_part_selected(part: String) -> void:
	if current_actor != player:
		return
	_do_attack(player, opponent, part, hud.rule_toggle.button_pressed)
	_end_turn(player)


func _on_defend_requested() -> void:
	if current_actor != player:
		return
	_do_defend(player)
	_end_turn(player)


func _on_item_requested() -> void:
	if current_actor != player:
		return
	_do_item(player)
	_end_turn(player)


func _on_end_turn_requested() -> void:
	if current_actor != player:
		return
	log_msg("你放弃行动（走位调整）")
	_end_turn(player)


func _on_restart() -> void:
	get_tree().reload_current_scene()


# ---------- AI ----------

func _ai_act_async(u: Unit) -> void:
	await get_tree().create_timer(1.0).timeout
	if battle_over:
		return
	var target: Unit = player if u == opponent else opponent
	var roll := randf()
	if _bleeding(u) and int(u.items.get("止血丹", 0)) > 0 and roll < 0.3:
		_do_item(u)
	elif roll < 0.75:
		_do_attack(u, target, _random_part(target), false)
	else:
		_do_defend(u)
	_end_turn(u)


# ---------- 行动结算 ----------

func _do_attack(attacker: Unit, target: Unit, part: String, infused: bool) -> void:
	var tech: Technique = attacker.technique
	if tech == null:
		log_msg("%s 没有功法" % attacker.display_name)
		return
	if not target.body.has(part):
		return
	if not ResourceSystem.spend(attacker, tech.cost_pool, tech.cost_amount):
		log_msg("%s 的%s不足，无法出招（%s 消耗 %d %s）" % [
			attacker.display_name, tech.cost_pool, tech.display_name, int(tech.cost_amount), tech.cost_pool])
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
	# —— 规则维度（《战斗系统》§4.1）：融入规则，差≥1阶=碾压 ——
	var rule_bonus := 0.0
	if infused:
		var rule: String = _pick_rule(attacker, tech)
		if rule == "":
			log_msg("没有可融入的法则（功法无融入槽，或你未领悟对应规则）")
		elif ResourceSystem.spend(attacker, "玄力", RULE_INFUSE_COST):
			var diff: int = _rule_level(attacker, rule) - _rule_level(target, rule)
			if diff >= RULE_CRUSH_STEP:
				rule_bonus = RULE_CRUSH_BONUS
				log_msg("%s 融入「%s」规则——规则碾压，无视速度差！" % [attacker.display_name, rule])
			else:
				log_msg("%s 融入「%s」规则，但对方领悟不弱于你，未能碾压" % [attacker.display_name, rule])
		else:
			log_msg("玄力不足，无法融入规则")
	var total_atk: float = atk_speed + rule_bonus
	log_msg("%s 以《%s》攻击「%s」：攻速 %.0f vs 防速 %.0f" % [
		attacker.display_name, tech.display_name, part, total_atk, def_speed])
	if total_atk > def_speed:
		_apply_hit(attacker, target, part)
	else:
		log_msg("%s 招架/闪避了这一击（招架消耗体力）" % target.display_name)
		ResourceSystem.drain(target, "体力", 5.0)


## 破防模型（《战斗系统》§5）：远低于→无伤 / 相近→磨防 / 高于→破防
func _apply_hit(attacker: Unit, target: Unit, part: String) -> void:
	var ap: float = attacker.attack_power
	if ap > target.armor:
		log_msg("%s 破防！「%s」受到实质伤害" % [attacker.display_name, part])
		BodySystem.hurt(target, part, 1)
		# 功法附加机制：焚天诀命中附加灼烧（机制脚本后置前的占位实现）
		if attacker.technique != null and attacker.technique.id == "fentian_jue":
			StatusSystem.add_status(target, "灼烧", 6.0)
			log_msg("%s 被灼烧！每秒流失气血" % target.display_name)
	elif target.armor - ap <= WEAR_THRESHOLD:
		target.armor = maxf(target.armor - ARMOR_WEAR, 0.0)
		log_msg("未破防——但磨掉了对方的防御（防御余 %.0f）" % target.armor)
	else:
		log_msg("无伤——对方的防御远高于这一击")


func _do_defend(u: Unit) -> void:
	if not ResourceSystem.spend(u, "体力", 5.0):
		log_msg("%s 体力不足，摆不出架势" % u.display_name)
		return
	u.is_defending = true
	log_msg("%s 摆出防御架势（招架侧重 +%d，持续到下次行动）" % [u.display_name, int(STANCE_BONUS)])


func _do_item(u: Unit) -> void:
	if int(u.items.get("止血丹", 0)) <= 0:
		log_msg("%s 没有止血丹了" % u.display_name)
		return
	u.items["止血丹"] = int(u.items["止血丹"]) - 1
	BodySystem.seal_wounds(u)
	log_msg("%s 服用止血丹——创伤止血，不再失血（部位伤势仍在）" % u.display_name)


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
		log_msg("%s 陨落（%s）" % [u.display_name, cause])
		_battle_end(u)


func _battle_end(loser: Unit) -> void:
	battle_over = true
	TimelineSystem.active = false
	hud.enable_actions(false)
	hud.show_restart()
	log_msg("战斗结束——%s 败北" % loser.display_name)


# ---------- 工具 ----------

func _pick_rule(attacker: Unit, tech: Technique) -> String:
	for rule in tech.rule_slots:
		if attacker.rules.has(rule):
			return rule
	return ""


func _rule_level(u: Unit, rule: String) -> int:
	return int(u.rules.get(rule, 0))


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


## 注意：不能叫 log——与 GDScript 内置数学函数 log() 撞名
func log_msg(text: String) -> void:
	if hud != null:
		hud.log(text)


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
	_draw_unit(player, Color(0.4, 0.8, 1.0))
	_draw_unit(opponent, Color(1.0, 0.45, 0.45))


func _draw_unit(u: Unit, color: Color) -> void:
	if u == null:
		return
	var top_left := ORIGIN + Vector2(u.pos.x * CELL + 6.0, u.pos.y * CELL + 6.0)
	draw_rect(Rect2(top_left, Vector2(CELL - 12, CELL - 12)), color)
	# ATB 行动条
	var bar_w := (CELL - 12) * clampf(u.atb_progress / 100.0, 0.0, 1.0)
	draw_rect(Rect2(top_left + Vector2(0, CELL - 2), Vector2(bar_w, 6)), Color(0.9, 0.85, 0.3))
