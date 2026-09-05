extends Node2D
## P0.5 战斗原型主控制器（内核与表现分离：内核=六子系统+Unit 纯数据，表现=本场景绘制+HUD）
## 对应文档：《战斗系统》v0.5 + 挂载体系。
## 演示循环：ATB 读条 → 移动/普攻(随机招式)/招式面板(手动选招带CD)/切换功法/守势宣言/丹药/策略按钮
##           → 防御链（①闪避→②招架→③代受→④护体玄气→肉身伤势）→ 失血/要害死亡。
## 攻击范围 = 招式基础射程 + 武器修正；面板 = 基础 + 挂载加成 + 武器，再乘部位伤效修正。
## v0.5：朝向与绕后 / 部位策略制与护体策略制（回合末结算）/ 流血概率化（edge/blade 武器属性）/ 受伤程度链。

const Grades := preload("res://scripts/cultivation_grades.gd")
const Nar := preload("res://scripts/narration.gd")
const WeaponData := preload("res://scripts/weapons.gd")

# —— 美术成品（art/ 源文件 → godot/assets/ 成品，AI 成分 _ai 后缀留档）——
const TEX_BG := preload("res://assets/backgrounds/战场棋盘_整屏背景_v2_ai.png")       # 1280×720 氛围层
const TEX_BOARD := preload("res://assets/backgrounds/战场棋盘_战斗背景_v2_ai.png")    # 600×600 棋盘底图
const TEX_SPRITES := {
	"player": preload("res://assets/sprites/玩家_女剑修_战斗精灵_v2_ai.png"),
	"opponent": preload("res://assets/sprites/散修_焚天诀_战斗精灵_v1_ai.png"),
}

const RULE_INFUSE_COST := 10.0  # 融入规则消耗玄力
const RULE_CRUSH_BONUS := 80.0  # 规则碾压（粗分阶差≥1）的命中修正
const RULE_CRUSH_STEP := 1      # 粗分阶差几阶算「碾压」
const BLEED_PER_TURN := 4.0     # 每处流血创伤每回合失血（该单位行动时结算——挂机不掉血）
const ARMOR_WEAR := 4.0         # 磨防：每次磨掉的防御
const WEAR_THRESHOLD := 6.0     # 防御高出攻击力不超过此值 → 算「相近」进入磨防
const MOVE_STAMINA_COST := 1.0  # 走 1 格消耗体力
const SWITCH_COST := 10.0       # 切换招式功法耗体力（不算出招）
const PROF_GAIN := 5.0          # 出招破防命中，功法修为 +5（一称号档）
# —— 防御博弈（《战斗系统》§5.1）——
const STANCE_PARRY_BONUS := 30.0  # 招架架势：②层招架判定加成
const STANCE_DODGE_BONUS := 25.0  # 闪避架势：①层闪避加成
const GUARD_ARMOR_MULT := 1.3     # 守势集中：重点部位护体↑
const IRON_ARMOR_MULT := 1.5      # 铁壁架势：重点部位护体↑↑
const IRON_DODGE_MULT := 0.8      # 铁壁代价：①层闪避判定↓
const PARRY_STAMINA_COST := 3.0   # 招架成功耗体力
const PARRY_BREAK_STAMINA := 5.0  # 破格挡耗体力
const DISARM_RATIO := 1.5         # 攻击力超招架值此倍数 → 武器脱手
const PARRY_AGILITY_WEIGHT := 0.3 # 招架值中敏捷占比
const SUB_REACTION_FACTOR := 0.85 # 代受反应门槛（守方敏捷 vs 攻方攻速）
const DODGE_STAMINA_COST := 5.0   # 闪避架势宣言耗体力
# 熟练度档系数（《功法系统》§2.2）：初窥→掌道——招式威力与臂伤降档的落点
const PROF_TIER_COEFFS := [0.8, 0.9, 1.0, 1.1, 1.2]

# —— 朝向与绕后（v0.5《战斗系统》§1.1 朝向/§5.1.7 绕后——视觉朝向与几何背向分离）——
const SPRITE_DIR := 1.0          # 贴图原始朝向基准（假定画面朝右=1，镜像=×(-1)）；试玩发现镜像反了只改此常数，不动资产
const FLANK_SPEED_MULT := 0.7    # 绕后：被绕者 ① 层防速 ×0.7（用户定量）
const THREAT_RANGE_FLOOR := 1    # 威胁半径 = 此值 + 武器射程修正（range_bonus）——区内逼近步价 ×2（横/退只 ×1）
# —— 流血概率（v0.5《战斗系统》§2.3——edge 锋利度/blade 刃长是武器基本属性）——
const EDGE_P := [0.10, 0.45, 0.75, 1.0]        # 锋利度 钝/半刃/利刃/纯刃 → 基础流血概率（纯刃必流；初值待调）
const BLADE_MULT := {0: 0.75, 1: 1.0, 2: 1.15} # 刃长 短/中/长 → 概率修正（初值待调）
const SEV_BLEED_MULT := {1: 0.6, 2: 0.85, 3: 1.0}  # 最终部位状态 轻伤/重伤/毁 → 概率修正（初值待调）
# —— 护体玄气（v0.5《战斗系统》§5.1.5 罩层 / §5.2 护体策略制——境界+功法+修为定上限，满罩开局）——
const SHIELD_REALM := {"凡人": 15.0, "练气": 30.0, "筑基": 45.0, "金丹": 60.0}  # 境界 → 罩上限基数（初值待调）
const SHIELD_PER_PROF := 2.0     # 罩上限 += 修为称号档 × 此值（称号每 5 点一档，cultivation_grades）
const SHIELD_UPKEEP := 1.0       # 罩>0 时每回合行动开始扣的维持玄力（各档同付；玄力空免扣不衰减）
const SHIELD_STRATEGY_PCT := {"守常": 0.0, "周天": 1.0, "凝罡": 1.25, "守一": 1.5}  # 策略档 → 补罩目标（罩上限倍数；守常=不灌注）
const SHIELD_POUR_MULT := [1.0, 1.25, 1.5]    # 费率段单价：罩≤100% 段 1:1 / 100~125% 段 1.25× / 125~150% 段 1.5×（先填低价段）
# —— 受伤程度链（v0.5《战斗系统》§5.3——破防余量 → 肉身强度衰减 → 对气血比例定伤档，不按倍数）——
const FLESH_ABSORB := {"凡人": 0.15, "练气": 0.2, "筑基": 0.24, "金丹": 0.28}  # 肉身强度衰减率（初值待调）
const WOUND_LIGHT_RATIO := 0.08  # 有效余量 ≥ 气血上限此比例 → 轻伤（初值待调）
const WOUND_HEAVY_RATIO := 0.18  # ≥ 此比例 → 重伤；再往上 → 毁（初值待调）

const CELL := 60.0
# 布局 v0.4：棋盘靠左（占住左侧空白），右侧整列给解说与按钮（见 HUD）
const ORIGIN := Vector2(20, 72)

var player: Unit
var opponent: Unit
var current_actor: Unit = null
var current_acted := false        # 本回合是否已出手（移动与出招顺序自由，出招限一次）
var pending_move: Move = null     # 待出手的招式（普攻随机或招式面板所选）
var battle_over := false
var hud: BattleHud
# 守势选择状态（§5.1.2：宣言不占出招，先选部位再选架势）
var _guard_selecting := false
var _guard_pending: Array[String] = []

# 截图调试模式：命令行加 -- --shot，每秒存一张图到 _debug/，6 张后自动退出
var _shot_mode := false
var _shot_elapsed := 0.0
var _shot_count := 0
# 特效截图模式：命令行加 -- --fxshot，有活跃特效(_fx 非空)才拍（每 3 帧一张、10 张退出）——验证程序化特效渲染
var _shot_fx_mode := false
var _shot_fx_frame := 0
# 自对弈模式：命令行加 -- --autoplay，AI 控制双方、战斗结束自动重开（平衡验证/机制长跑）
var _autoplay := false
var _auto_restart_left := -1
# 机制触发统计（自对弈验证：确认各防御层确实在运转，不只是「零报错」）
var _stat := {}
var _battle_turns := 0
# 招式特效（P0 程序化占位——《多媒体资产清单》§1.1；P1 换帧动画只替换 _draw_fx 与素材）
var _fx: Array[Dictionary] = []  # {kind, t, dur, a: Vector2, b: Vector2, color, text}
# —— v0.5 策略与掷骰（部位策略循环档 / 护体档持久在单位上；B 红线：新掷骰一律走 _rng，--seed 可回放）——
var _part_strategy := "自动"     # 部位策略：自动/随机/手动/重点（玩家侧；AI 恒用 _ai_pick_part）
var _focus_part := ""            # 重点策略锁定的部位（该部位毁则自动退回「自动」）
var _part_pick_mode := ""        # 部位行弹出用途："" 无 / "focus" 重点锁定 / "attack" 手动出招待点选（防两套弹窗串台）
var _rng := RandomNumberGenerator.new()


func _stat_bump(key: String) -> void:
	_stat[key] = int(_stat.get(key, 0)) + 1


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	_shot_mode = "--shot" in user_args
	_shot_fx_mode = "--fxshot" in user_args
	_autoplay = "--autoplay" in user_args
	if _autoplay:
		Engine.time_scale = 4.0  # 自对弈加速（挂机长跑更快出结果）
	# v0.5：--seed N 注入战斗内掷骰（B 红线：确定性内核可回放——判定掷骰全走 _rng）
	var seed_i := user_args.find("--seed")
	if seed_i >= 0 and seed_i + 1 < user_args.size():
		_rng.seed = int(user_args[seed_i + 1])
	else:
		_rng.randomize()  # 无 seed 时随机开局——保证多场自对弈各不相同
	randomize()  # 表现层（解说变体 / 音效噪声）仍用全局 RNG，不影响判定回放
	# 场景重载后 autoload 子系统残留上一场状态——先清场（否则时序冻结、单位堆积）
	UnitSystem.reset_all()
	TimelineSystem.reset_all()
	player = UnitSystem.spawn({
		"id": "player", "display_name": "你", "team": 0, "realm": "金丹",
		"base_speed": 75.0, "base_agility": 40.0, "base_move_speed": 75.0,
		"base_attack_power": 18.0, "base_armor": 20.0,
		"pools": ResourceSystem.init_pools(100.0, 100.0, 80.0, 50.0),
		"rules": {"空间": 60.0},
		"technique_proficiency": {"qinglian_jiange": 15.0, "pojunjuan": 5.0},
		"dao_proficiency": {"剑道": 25.0},
		"pos": Vector2i(2, 5),
		"items": {"止血丹": 3},
	})
	_mount(player,
		load("res://resources/techniques/qinglian_xinfa.tres"),
		[load("res://resources/techniques/qinglian_jiange.tres"),
		 load("res://resources/techniques/pojunjuan.tres")])
	opponent = UnitSystem.spawn({
		"id": "opponent", "display_name": "散修", "team": 1, "realm": "金丹",
		"base_speed": 75.0, "base_agility": 90.0, "base_move_speed": 75.0,
		"base_attack_power": 8.0, "base_armor": 35.0,
		"pools": ResourceSystem.init_pools(90.0, 110.0, 60.0, 40.0),
		"rules": {"空间": 5.0, "火": 25.0},
		"technique_proficiency": {"fentian_jue": 40.0},
		"dao_proficiency": {},
		"pos": Vector2i(7, 5),
		"items": {"止血丹": 2},
	})
	_mount(opponent,
		load("res://resources/techniques/fentian_jue.tres"),
		[load("res://resources/techniques/fentian_jue.tres")])
	# —— 开战对峙：双方宣言初始守势（§5.1.2）——
	_stat = {}
	_battle_turns = 0
	player.guard_parts = ["头部", "丹田"]
	player.stance = "招架"
	opponent.guard_parts = ["头部", "丹田"]
	opponent.stance = "招架"
	# —— v0.5 开战初始化：护体玄气满罩（对峙先互相轰罩）；双方视觉朝向相对（贴图镜像）——
	player.shield_cur = 0.0  # _recalc_shield 只限幅不补——先归零再满罩
	opponent.shield_cur = 0.0
	_recalc_shield(player)
	_recalc_shield(opponent)
	player.shield_cur = player.shield_max
	opponent.shield_cur = opponent.shield_max
	player.shield_strategy = "守常"
	opponent.shield_strategy = "守常"
	player.vis_facing = 1.0 if opponent.pos.x > player.pos.x else -1.0
	opponent.vis_facing = -player.vis_facing if opponent.pos.x != player.pos.x else 1.0
	# 表现层初始化：绘制位置 = 逻辑格中心（移动插值起点）
	player.render_pos = _cell_center(player.pos)
	opponent.render_pos = _cell_center(opponent.pos)

	TimelineSystem.unit_ready.connect(_on_unit_ready)
	hud = BattleHud.new()
	add_child(hud)
	hud.attack_pressed.connect(_on_attack_requested)
	hud.move_menu_pressed.connect(_on_move_menu_requested)
	hud.switch_pressed.connect(_on_switch_requested)
	hud.guard_pressed.connect(_on_guard_requested)
	hud.item_pressed.connect(_on_item_requested)
	hud.end_turn_pressed.connect(_on_end_turn_requested)
	hud.part_selected.connect(_on_part_selected)
	hud.move_selected.connect(_on_move_selected)
	hud.guard_part_toggled.connect(_on_guard_part_toggled)
	hud.guard_stance_selected.connect(_on_guard_stance_selected)
	hud.guard_cancel.connect(_on_guard_cancel)
	hud.strategy_cycled.connect(_on_strategy_cycled)
	hud.shield_strategy_cycled.connect(_on_shield_strategy_cycled)
	hud.restart_requested.connect(_on_restart)
	EventBus.battle_started.emit()
	_say(Nar.start())
	if _autoplay:
		print("AUTOPLAY battle start frame=", Engine.get_process_frames())
	_say(Nar.guard_initial(player))
	_say(Nar.guard_initial(opponent))
	hud.log("提示：普攻随机出招；「招式」手动选招（带冷却）；「守势」选重点部位+架势（不占出招）；对方守势内的部位会被格挡，要害被攻时其会以手臂代受——打空当、磨防、融入规则")


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
	_recalc_shield(u)


func _pool_max_snapshot(pools: Dictionary) -> Dictionary:
	var d := {}
	for pool in pools:
		d[pool] = pools[pool]["max"]
	return d


## 有效面板 = （基础 + 主修/激活功法挂载加成 + 武器）× 部位伤效修正（§2.5）
func _recalc_stats(u: Unit) -> void:
	var inj: Dictionary = BodySystem.injury_multipliers(u)
	u.speed = u.base_speed + _mount_bonus(u, "bonus_speed")
	u.agility = u.base_agility * inj.agi
	u.move_speed = u.base_move_speed + _mount_bonus(u, "bonus_speed")
	var w: String = "空手" if u.weapon_disarmed else u.weapon
	u.attack_power = (u.base_attack_power + WeaponData.attack(w) + _mount_bonus(u, "bonus_attack")) * inj.atk
	u.parry = WeaponData.parry(w) * inj.parry


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


## 罩上限 = 境界基数 + 主修/激活功法 bonus_shield + 修为称号档×SHIELD_PER_PROF（v0.5 §5.1.5）
## cur 只限幅不回补——补充走护体策略（§5.2），开局满罩由 _ready 显式灌满
func _recalc_shield(u: Unit) -> void:
	var tech: Technique = u.active_technique
	var prof: float = u.technique_proficiency.get(tech.id if tech != null else "", 0.0)
	u.shield_max = SHIELD_REALM.get(u.realm, 30.0) + _mount_bonus(u, "bonus_shield") + float(Grades.tier(prof)) * SHIELD_PER_PROF
	u.shield_cur = minf(u.shield_cur, u.shield_max)


# ---------- 护体策略制（v0.5 §5.2：宣言制择档、回合末结算、档位持久沿用） ----------

## 换档（自己行动窗口内宣言，不立即结算；解说+确认音）
func _set_shield_strategy(u: Unit, s: String) -> void:
	if u.shield_strategy == s:
		return
	u.shield_strategy = s
	_say(Nar.shield_strategy_set(u))
	AudioManager.sfx("凝护")


## 回合末结算：按当前档补罩——≤100% 段 1 玄力:1 罩 / 100~125% 段 1.25× / 125~150% 段 1.5×
## （先填低价段；玄力不足按可支付额部分补；择低档不放气——罩高于新档目标时原样留存）
func _apply_shield_strategy(u: Unit) -> void:
	var pct: float = SHIELD_STRATEGY_PCT.get(u.shield_strategy, 0.0)
	if pct <= 0.0:
		return  # 守常：不灌注
	var target: float = u.shield_max * pct
	if u.shield_cur >= target:
		return  # 罩已达目标（含超量）——不补也不放
	var xuan := ResourceSystem.current(u, "玄力")
	if xuan < 1.0:
		return
	var poured := 0.0
	var limits := [u.shield_max, u.shield_max * 1.25, u.shield_max * 1.5]  # 费率段上界
	for zi in limits.size():
		var seg: float = minf(target, limits[zi]) - u.shield_cur
		if seg <= 0.0:
			continue
		var need: float = seg * SHIELD_POUR_MULT[zi]
		if xuan >= need:
			u.shield_cur += seg
			poured += seg
			xuan -= need
			ResourceSystem.drain(u, "玄力", need)
		else:
			u.shield_cur += xuan / SHIELD_POUR_MULT[zi]
			poured += xuan / SHIELD_POUR_MULT[zi]
			ResourceSystem.drain(u, "玄力", xuan)
			break
	if poured > 0.0:
		_say(Nar.shield_pour(u, poured))
		AudioManager.sfx("凝护")
		_stat_bump("shield_pour")


func _mount_bonus(u: Unit, field: String) -> float:
	var total := 0.0
	for t in [u.main_technique, u.active_technique]:
		if t != null:
			total += t.get(field)
	return total


func _process(delta: float) -> void:
	if _shot_mode or _shot_fx_mode:
		_take_debug_shots(delta)
	if battle_over:
		# 自对弈：战斗结束 30 帧后自动重开下一场
		if _autoplay:
			_auto_restart_left -= 1
			if _auto_restart_left <= 0:
				get_tree().reload_current_scene()
		return
	# 失血与持续状态按回合结算（该单位行动时，见 _on_unit_ready）——不按实时
	for u in UnitSystem.alive_units():
		_check_death(u)
	if battle_over:
		return
	TimelineSystem.process_timeline(delta)
	hud.update_state(self)
	_update_render(player, delta)
	_update_render(opponent, delta)
	_update_fx(delta)
	queue_redraw()


# ---------- 行动流程 ----------

func _on_unit_ready(u: Unit) -> void:
	if battle_over:
		return
	TimelineSystem.active = false  # 冻结读条（战斗暂停=思考时间）
	current_actor = u
	current_acted = false
	pending_move = null
	_battle_turns += 1
	u.move_left = _calc_move_steps(u)
	# 招架架势机动受限（§5.1.2 架势代价——守势保持期间每回合生效）
	if u.stance == "招架":
		u.move_left = maxi(0, u.move_left - 1)
	# 武器脱手自动拾回（§5.1.3——下次行动时拾回）
	if u.weapon_disarmed:
		u.weapon_disarmed = false
		_say(Nar.pickup_weapon(u))
		_recalc_stats(u)
	u.items_used_this_turn.clear()  # 丹药每回合每种限用一次
	_tick_cooldowns(u)
	# —— v0.5 护体维持费（罩>0 时每回合 1 玄力，各档同付；玄力空免扣不衰减）——
	if u.shield_cur > 0.0:
		ResourceSystem.drain(u, "玄力", SHIELD_UPKEEP)
	# —— 回合结算：失血与持续状态（按回合，不按实时——挂机不会流血而死）——
	var bleed: float = BodySystem.bleed_amount(u)
	if bleed > 0.0:
		ResourceSystem.drain(u, "气血", bleed * BLEED_PER_TURN)
		_say(Nar.bleed_tick(u))
		AudioManager.sfx("失血")
	StatusSystem.tick_turn(u)
	_check_death(u)
	if battle_over:
		return
	hud.rule_toggle.button_pressed = false
	if u == player and not _autoplay:
		hud.enable_actions(true)
	else:
		hud.enable_actions(false)
		_ai_act_async(u)
	_say(Nar.turn(u, u.move_left))
	AudioManager.sfx("回合")


## 步数额度 = ceil(move_speed/20)，再按腿伤修正（§2.5：轻伤-1 / 重伤减半 / 毁=无法移动）
func _calc_move_steps(u: Unit) -> int:
	var base := maxi(1, ceili(u.move_speed / 20.0))
	var leg: int = BodySystem.leg_penalty(u)
	if leg == 3:
		return 0
	if leg == 2:
		return maxi(0, base / 2)
	if leg == 1:
		return maxi(0, base - 1)
	return base


func _tick_cooldowns(u: Unit) -> void:
	for id in u.cooldowns.keys().duplicate():
		u.cooldowns[id] = int(u.cooldowns[id]) - 1
		if int(u.cooldowns[id]) <= 0:
			u.cooldowns.erase(id)


func _end_turn(u: Unit) -> void:
	_apply_shield_strategy(u)  # v0.5 §5.2：回合末按护体策略档结算补罩（先于对方行动生效；档位持久沿用）
	u.move_left = 0
	current_acted = false
	pending_move = null
	_guard_selecting = false
	hud.clear_guard_select()
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
	if BodySystem.leg_penalty(u) == 3:
		_say(Nar.legs_destroyed(u))
		return
	var enemy: Unit = opponent if u == player else player
	_walk(u, enemy, cell, _move_graph(u, enemy, u.move_left), u.move_left)


# ---------- 走位工具（v0.5《战斗系统》§1.1：威胁区带权步 + 几何背向） ----------

## 威胁区判定：敌方武器攻击半径内的格子（区内**逼近**（距敌变近）步价 ×2——正面扑脸要付代价；
## 区内横移/后撤只计 1 步——贴着刀锋绕弧、抽身后撤不被罚，绕后才是可行的战术承诺）
func _in_threat(cell: Vector2i, enemy: Unit) -> bool:
	var w: String = "空手" if enemy.weapon_disarmed else enemy.weapon
	return _chebyshev(cell, enemy.pos) <= THREAT_RANGE_FLOOR + WeaponData.range_bonus(w)


## 绕后判定（v0.5 §5.1.7）：守方有几何背向（最近一次移动方向）且攻方在其来路对侧——
## (守.pos − 攻.pos) · 守.geo_facing > 0；从未移动的单位没有背（龟缩不可绕，但放弃走位主动权）
func _is_flanking(attacker: Unit, target: Unit) -> bool:
	var g: Vector2i = target.geo_facing
	if g == Vector2i.ZERO:
		return false
	var vec: Vector2i = target.pos - attacker.pos
	return vec.x * g.x + vec.y * g.y > 0


## 带权步最短路（10×10 小棋盘朴素 Dijkstra）：区外 1、区内逼近 2、区内横退 1（方向化，见 _in_threat）。
## 返回 {dist: {格: 步数}, prev: {格: 前驱}}——dist 只收录预算内可达格；步数即体力点数
func _move_graph(u: Unit, enemy: Unit, budget: int) -> Dictionary:
	var dist := {u.pos: 0}
	var prev := {}
	var open := [u.pos]
	while not open.is_empty():
		var cur: Vector2i = open[0]
		var ci := 0
		for i in range(1, open.size()):
			if dist[open[i]] < dist[cur]:
				cur = open[i]
				ci = i
		open.remove_at(ci)
		var cd: int = dist[cur]
		if cd >= budget:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = cur + d
			if not FieldSystem.in_bounds(np) or np == enemy.pos:
				continue
			# v0.5 威胁步方向化：区内逼近（距敌变近）2 步——横移/后撤只 1 步，绕弧可行
			var nd: int = cd + 1
			if _in_threat(np, enemy) and _chebyshev(np, enemy.pos) < _chebyshev(cur, enemy.pos):
				nd += 1
			if nd <= budget and nd < dist.get(np, 1 << 30):
				dist[np] = nd
				prev[np] = cur
				open.append(np)
	return {"dist": dist, "prev": prev}


## 由前驱表还原路径（格数组，不含起点；不可达返回空）——沿前驱链回溯到起点（起点无前驱）
func _path_from(g: Dictionary, goal: Vector2i) -> Array:
	var prev: Dictionary = g.prev
	if not prev.has(goal):
		return []
	var path: Array = []
	var cur := goal
	while prev.has(cur):
		path.push_front(cur)
		cur = prev[cur]
	return path


## 执行走位：体力/步数双扣、pos 落点、朝向与几何背向更新、特效解说
func _walk(u: Unit, enemy: Unit, goal: Vector2i, g: Dictionary, budget: int) -> void:
	if not g.dist.has(goal) or int(g.dist[goal]) > budget:
		return
	var path: Array = _path_from(g, goal)
	if path.is_empty():
		return
	var cost: int = g.dist[goal]
	if ResourceSystem.current(u, "体力") < float(cost) * MOVE_STAMINA_COST:
		_say(Nar.move_fail(u))
		return
	var from := u.pos
	var old_center := _cell_center(from)
	ResourceSystem.drain(u, "体力", float(cost) * MOVE_STAMINA_COST)
	u.pos = goal
	u.move_left -= cost
	_update_facing(u, path, from)
	hud.clear_parts()
	hud.clear_moves()
	_say(Nar.move(u, cost))
	AudioManager.sfx("移动")
	_spawn_fx("move", old_center, _cell_center(goal))
	if current_acted and u.move_left <= 0 and u == player:
		_say(Nar.turn_auto_end(u))
		_end_turn(u)


## 朝向更新（v0.5 §1.1）：视觉朝向 = 本次位移的水平方向（同列移动不翻转）；
## 几何背向 = 最后一次落步的方向（站着不动=无背——龟缩不可绕，守势期走位是绕后唯一来源）
func _update_facing(u: Unit, path: Array, from: Vector2i) -> void:
	var to_cell: Vector2i = path[-1]
	var prev_cell: Vector2i = path[-2] if path.size() >= 2 else from
	var dir: Vector2i = to_cell - prev_cell
	u.geo_facing = dir
	if dir.x != 0.0:
		u.vis_facing = 1.0 if dir.x > 0 else -1.0


## 普攻：英雄坛说式——从当前功法招式池随机出一招
func _on_attack_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	var move := _pick_random_move(player)
	if move == null:
		_say(_no_move_reason(player))
		return
	if not _in_range(player, opponent, move):
		_say(Nar.out_of_range(player.move_left))
		return
	_resolve_part_and_attack(move)  # v0.5：按部位策略直接出手（手动档才弹部位行）


## 招式面板：侠客风云传式——手动选招（带冷却）
func _on_move_menu_requested() -> void:
	if current_actor != player or current_acted:
		if current_acted:
			_say(Nar.acted_already(player))
		return
	hud.set_moves(player, self)


func _on_move_selected(move_id: String) -> void:
	if current_actor != player or current_acted:
		return
	var move := _find_move(player, move_id)
	if move == null:
		return
	if move.move_type in ["变招", "大招"] and not variant_unlocked(player, move):
		_say(Nar.variant_locked(move))
		hud.clear_moves()
		return
	if _move_cd(player, move) > 0:
		_say(Nar.cd_busy(move))
		return
	if not BodySystem.can_use_move(player, move):
		_say(Nar.arm_disabled(player, move))
		hud.clear_moves()
		return
	if not _in_range(player, opponent, move):
		_say(Nar.out_of_range(player.move_left))
		hud.clear_moves()
		return
	hud.clear_moves()
	_resolve_part_and_attack(move)  # v0.5：按部位策略直接出手（手动档才弹部位行）


func _on_part_selected(part: String) -> void:
	if current_actor != player:
		return
	if _part_pick_mode == "focus":
		# 重点策略：点选一次锁定重点部位（不占行动、不出招）
		_part_pick_mode = ""
		_focus_part = part
		hud.clear_parts()
		_say(Nar.focus_part_set(player, part))
		return
	if current_acted:
		return
	if _part_pick_mode != "attack" or pending_move == null:
		hud.clear_parts()  # 弹窗用途已失效（被守势/换招顶掉）——清行不误出招
		return
	var move: Move = pending_move
	pending_move = null
	_part_pick_mode = ""
	hud.clear_parts()
	_do_attack(player, opponent, part, move, hud.rule_toggle.button_pressed)
	current_acted = true
	if player.move_left <= 0:
		_say(Nar.turn_auto_end(player))
		_end_turn(player)


# ---------- 部位策略制（v0.5 §6：自动/随机/手动/重点循环——每击不再强制手选部位） ----------

## 策略按钮循环（标签随档变；「重点」无有效部位时弹部位行选一次，锁定后不复弹）
func _on_strategy_cycled() -> void:
	if battle_over or current_actor != player or _guard_selecting:
		return  # 守势选择中部位行被占——不打断，忽略
	var order := ["自动", "随机", "手动", "重点"]
	_part_strategy = order[(order.find(_part_strategy) + 1) % order.size()]
	pending_move = null
	_part_pick_mode = ""
	hud.clear_parts()
	hud.clear_moves()
	if _part_strategy == "重点" and not _focus_valid():
		_part_pick_mode = "focus"
		hud.set_parts(opponent)
		_say(Nar.focus_part_pick())
	elif _part_strategy == "重点":
		_say(Nar.focus_part_keep(player, _focus_part))
	else:
		_say(Nar.strategy_set(player, _part_strategy))


## 护体策略按钮循环（守常/周天/凝罡/守一——宣言不立即结算，本回合末自动按档补罩；档位持久沿用）
func _on_shield_strategy_cycled() -> void:
	if battle_over or current_actor != player:
		return
	var order := ["守常", "周天", "凝罡", "守一"]
	_set_shield_strategy(player, order[(order.find(player.shield_strategy) + 1) % order.size()])


## 出招出口：手动档 → 弹部位行等点选（旧流程保留）；其余档按策略定部位直接出手
func _resolve_part_and_attack(move: Move) -> void:
	if _part_strategy == "手动":
		pending_move = move
		_part_pick_mode = "attack"
		hud.set_parts(opponent)
		return
	hud.clear_parts()  # 弹窗还开着（如重点锁定中）——出招即收起
	_part_pick_mode = ""
	_do_attack(player, opponent, _part_by_strategy(move), move, hud.rule_toggle.button_pressed)
	current_acted = true
	if player.move_left <= 0:
		_say(Nar.turn_auto_end(player))
		_end_turn(player)


## 按当前策略定出手部位（v0.5：重点部位打毁 → 自动退回「自动」并解说）
func _part_by_strategy(move: Move) -> String:
	if _part_strategy == "重点":
		if _focus_valid():
			return _focus_part
		_part_strategy = "自动"
		_focus_part = ""
		_say(Nar.focus_part_lost())
	elif _part_strategy == "随机":
		var alive: Array[String] = []
		for p in opponent.body:
			if int(opponent.body[p].state) != BodySystem.PartState.DESTROYED:
				alive.append(p)
		if not alive.is_empty():
			return alive[_rng.randi() % alive.size()]
	return _auto_pick_part()  # 「自动」= AI 选部位脑确定性化（双方公平同款优先级）


## 自动策略脑（确定性）：未守势要害 → 未守势部位 → 兜底（无随机——可回放）
func _auto_pick_part() -> String:
	for p in opponent.body:
		if int(opponent.body[p].state) != BodySystem.PartState.DESTROYED and opponent.body[p].vital \
				and not opponent.guard_parts.has(p):
			return p
	for p in opponent.body:
		if int(opponent.body[p].state) != BodySystem.PartState.DESTROYED and not opponent.guard_parts.has(p):
			return p
	return "胸腹"


func _focus_valid() -> bool:
	return (
		_focus_part != ""
		and opponent.body.has(_focus_part)
		and int(opponent.body[_focus_part].state) != BodySystem.PartState.DESTROYED
	)


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
	AudioManager.sfx("切换")


# ---------- 守势宣言（§5.1.2） ----------

func _on_guard_requested() -> void:
	if current_actor != player or _guard_selecting:
		return
	_guard_selecting = true
	_guard_pending = player.guard_parts.duplicate()  # 预选当前守势，微调即可
	hud.show_guard_select(player)


func _on_guard_part_toggled(part: String, on: bool) -> void:
	if not _guard_selecting:
		return
	if on:
		if _guard_pending.size() >= 2:
			_say(Nar.guard_full())
			hud.update_guard_parts(_guard_pending)  # 已满两位：回弹刚按下的按钮
			return
		_guard_pending.append(part)
	else:
		_guard_pending.erase(part)
	hud.update_guard_parts(_guard_pending)


## 架势确认：守势生效（不占出招）；闪避架势耗体力、招架架势本回合机动 -1
func _on_guard_stance_selected(stance: String) -> void:
	if not _guard_selecting:
		return
	if _guard_pending.is_empty():
		_say(Nar.no_guard_parts())
		return
	if stance == "闪避":
		if not ResourceSystem.spend(player, "体力", DODGE_STAMINA_COST):
			_say(Nar.no_stamina(player, "体力", null))
			_guard_selecting = false
			hud.clear_guard_select()
			return
	var stance_changed: bool = player.stance != stance  # 重确认同一架势不重复扣步（保持制）
	player.guard_parts = _guard_pending.duplicate()
	player.stance = stance
	if stance == "招架" and stance_changed:
		player.move_left = maxi(0, player.move_left - 1)
	_say(Nar.guard_declared(player, " ".join(_guard_pending), stance))
	AudioManager.sfx("守势")
	_spawn_fx("guard", _cell_center(player.pos), _cell_center(player.pos))
	_guard_selecting = false
	hud.clear_guard_select()


func _on_guard_cancel() -> void:
	_guard_selecting = false
	hud.clear_guard_select()


func _on_item_requested() -> void:
	if current_actor != player:
		return
	_do_item(player)
	# 丹药不占出招机会：已出手且无步数时才自动结束回合
	if current_acted and player.move_left <= 0:
		_say(Nar.turn_auto_end(player))
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
	await get_tree().create_timer(0.0 if _autoplay else 0.9).timeout
	if battle_over:
		return
	# 0) 守势宣言（保持制——只在无守势时宣言；不占出招，招架架势机动 -1）
	if u.stance == "":
		_ai_declare_guard(u)
	var target: Unit = player if u == opponent else opponent
	# 0b) v0.5 护体策略档（罩不满且玄力过半 → 周天回满；否则守常省玄力——持久沿用、回合末同出口结算）
	_ai_pick_shield_strategy(u)
	# 1) 走位（v0.5 带权步：敌方威胁区内**逼近**双倍步价，横退单倍）——重伤流血小撤退（拉开吃药不出招，给对手绕后窗口）
	if _ai_retreat_condition(u):
		_ai_retreat(u, target)
		_do_item(u)
		_end_turn(u)
		return
	var want_range := _max_ready_range(u)
	if _chebyshev(u.pos, target.pos) > want_range:
		_ai_approach(u, target, want_range)  # 射程外 → 带权最短路逼近（最后贴脸段付双倍步价）
	elif _rng.randf() < 0.3:
		_flank_opportunity(u, target, want_range)  # 射程内 → 概率尝试绕背（成败都照常出招）
	# 2) 丹药不占行动——流血先吃药（每回合每种限一次），再出招
	if _bleeding(u) and int(u.items.get("止血丹", 0)) > 0 and int(u.items_used_this_turn.get("止血丹", 0)) < 1 and _rng.randf() < 0.3:
		_do_item(u)
	# 3) 在射程内 → 随机出招（英雄坛说式），打空当（§5.1.6）；无招可用（臂废/冷却）则就此结束
	if not current_acted:
		var move := _pick_random_move(u, true)
		if move != null and _in_range(u, target, move):
			# AI 融入规则：有融入槽且玄力充足时按概率融入（速度劣势靠规则破局，§4.1）
			var infuse: bool = (
				not u.active_technique.rule_slots.is_empty()
				and ResourceSystem.current(u, "玄力") >= RULE_INFUSE_COST
				and _rng.randf() < 0.4
			)
			_do_attack(u, target, _ai_pick_part(u, target), move, infuse)
			current_acted = true
	_end_turn(u)


## v0.5 护体策略档决策：罩低于上限且玄力过半 → 抬到周天（回合末自动补满，费率 1:1）；否则回落守常省玄力
func _ai_pick_shield_strategy(u: Unit) -> void:
	var want_pour: bool = (
		u.shield_cur < u.shield_max - 1.0
		and ResourceSystem.current(u, "玄力") > 0.5 * float(u.pools["玄力"]["max"])
	)
	_set_shield_strategy(u, "周天" if want_pour else "守常")


## v0.5 小撤退条件：气血<35% 且失血未止且体力>40 → 拉开吃药、本回合不出招
func _ai_retreat_condition(u: Unit) -> bool:
	return (
		ResourceSystem.current(u, "气血") < 0.35 * float(u.pools["气血"]["max"])
		and _bleeding(u)
		and ResourceSystem.current(u, "体力") > 40.0
	)


## 小撤退执行：选可达最远格（同远者优先站到威胁区外）拉远——付威胁费也值得，命要紧
func _ai_retreat(u: Unit, target: Unit) -> void:
	var g: Dictionary = _move_graph(u, target, u.move_left)
	var goal := Vector2i(-1, -1)
	var best_score := 0
	for c in g.dist.keys():
		if c == target.pos:
			continue
		var d := _chebyshev(c, target.pos)
		var score: int = d * 10 - (2 if _in_threat(c, target) else 0)
		if score > best_score:
			best_score = score
			goal = c
	if goal.x >= 0 and _chebyshev(goal, target.pos) > _chebyshev(u.pos, target.pos):
		_walk(u, target, goal, g, u.move_left)
	else:
		_say(Nar.no_retreat_room(u))


## v0.5 绕后尝试：守方有几何背向且其背后贴身格可达 → 走过去再出招（绕后判定在 _do_attack 现算）；
## 已然在背后则直接打。返回是否已绕到背后
func _flank_opportunity(u: Unit, target: Unit, want_range: int) -> bool:
	if target.geo_facing == Vector2i.ZERO or _chebyshev(u.pos, target.pos) > want_range:
		return false
	if _is_flanking(u, target):
		return true  # 站位已在其身后——无需走位
	var g: Dictionary = _move_graph(u, target, u.move_left)
	for c in g.dist.keys():
		if c == target.pos:
			continue
		var vec: Vector2i = target.pos - c
		if _chebyshev(c, target.pos) == 1 and vec.x * target.geo_facing.x + vec.y * target.geo_facing.y > 0:
			_walk(u, target, c, g, u.move_left)  # 背后贴身格
			return true
	return false


## AI 守势：保护自己最危险的两个要害，招架架势（§5.1）
func _ai_declare_guard(u: Unit) -> void:
	var vitals: Array[String] = []
	for part in u.body:
		if u.body[part].vital:
			vitals.append(part)
	u.guard_parts = vitals.slice(0, 2)
	u.stance = "招架"
	u.move_left = maxi(0, u.move_left - 1)
	_say(Nar.guard_declared(u, " ".join(u.guard_parts), "招架"))
	AudioManager.sfx("守势")
	_spawn_fx("guard", _cell_center(u.pos), _cell_center(u.pos))


## AI 观察守势打空当（§5.1.6）：优先未保护的要害 → 未保护部位 → 随机
func _ai_pick_part(u: Unit, target: Unit) -> String:
	var candidates: Array[String] = []
	for part in target.body:
		if int(target.body[part].state) != BodySystem.PartState.DESTROYED:
			candidates.append(part)
	if candidates.is_empty():
		return "胸腹"
	var unguarded_vitals: Array[String] = []
	for p in candidates:
		if target.body[p].vital and not target.guard_parts.has(p):
			unguarded_vitals.append(p)
	if not unguarded_vitals.is_empty() and _rng.randf() < 0.6:
		return unguarded_vitals[_rng.randi() % unguarded_vitals.size()]
	var unguarded: Array[String] = []
	for p in candidates:
		if not target.guard_parts.has(p):
			unguarded.append(p)
	if not unguarded.is_empty():
		return unguarded[_rng.randi() % unguarded.size()]
	return candidates[_rng.randi() % candidates.size()]


## 逼近（v0.5 带权最短路）：目标 = 可达的射程边界格（chebyshev==want_range，语义同旧贪婪版——
## 恰好站进射程就停）；边界格不可达则尽量走到最近的可达格。结算交给 _walk（步数/体力/朝向）
func _ai_approach(u: Unit, target: Unit, want_range: int) -> void:
	var g: Dictionary = _move_graph(u, target, u.move_left)
	var cur_d: int = _chebyshev(u.pos, target.pos)
	var goal := Vector2i(-1, -1)
	var best_cost := 1 << 30
	for c in g.dist.keys():
		if c == target.pos:
			continue
		if _chebyshev(c, target.pos) == want_range and int(g.dist[c]) < best_cost:
			goal = c
			best_cost = g.dist[c]
	if goal.x < 0:
		# 射程边界够不到：选最接近的可达格（距离同取步数少者）
		var best_d := cur_d
		for c in g.dist.keys():
			if c == target.pos:
				continue
			var cd: int = _chebyshev(c, target.pos)
			if cd < best_d or (cd == best_d and int(g.dist[c]) < best_cost):
				goal = c
				best_d = cd
				best_cost = g.dist[c]
	if goal.x >= 0 and _chebyshev(goal, target.pos) < cur_d:
		_walk(u, target, goal, g, u.move_left)


# ---------- 行动结算：四层防御链（§5.1） ----------

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
	# 手臂可用性（§2.5）：主臂毁则需臂招式禁用
	if not BodySystem.can_use_move(attacker, move):
		_say(Nar.arm_disabled(attacker, move))
		return
	if not ResourceSystem.spend(attacker, move.cost_pool, move.cost_amount):
		_say(Nar.no_stamina(attacker, move.cost_pool, move))
		return
	# —— v0.5 朝向与绕后（§1.1/§5.1.7）：出动作先转向对手（同一纵轴保持上一步朝向）；
	# 几何背向 = 守方最近一次移动方向，攻方在其来路对侧即绕后（视觉与几何分离——转身不消除背）——
	var dx_facing: int = target.pos.x - attacker.pos.x
	if dx_facing != 0:
		attacker.vis_facing = 1.0 if dx_facing > 0 else -1.0
		target.vis_facing = -attacker.vis_facing
	var flank: bool = _is_flanking(attacker, target)
	if flank:
		_say(Nar.flank(attacker, target))
		_stat_bump("flank")
	# 大招：出招即倾尽剑意（代价前置——无论命中与否，§3）
	if move.move_type == "大招":
		attacker.sword_intent = 0
		_say(Nar.ultimate_drain(attacker, move))
		AudioManager.sfx("大招")
	# —— 速度维度（《战斗系统》§4）：移速+敏捷+招式加成 ——
	var atk_speed: float = (
		(attacker.speed + attacker.agility + move.speed_bonus)
		* ResourceSystem.stamina_penalty(attacker) * StatusSystem.speed_modifier(attacker)
	)
	var dodge_bonus: float = STANCE_DODGE_BONUS if target.stance == "闪避" else 0.0
	var iron_dodge: float = IRON_DODGE_MULT if target.stance == "铁壁" else 1.0
	var def_speed: float = (
		(target.speed + target.agility * 0.5 + dodge_bonus)
		* ResourceSystem.stamina_penalty(target) * StatusSystem.speed_modifier(target) * iron_dodge
		* (FLANK_SPEED_MULT if flank else 1.0)  # v0.5 绕后：被绕者防速 ×0.7
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
	var realm_d: int = BodySystem.realm_diff(attacker, target)
	# —— ① 闪避层（被动常驻，无代价）——
	if total_atk <= def_speed:
		_say(Nar.dodge(target, attacker))
		AudioManager.sfx("闪避")
		_spawn_fx("dodge", _cell_center(target.pos), _cell_center(target.pos))
		_break_intent(attacker)
		_stat_bump("dodge")
		_apply_cooldown(attacker, move)
		return
	# —— ② 招架层（守势覆盖 / 招架架势）——
	# 注：招架只挡物理招式（兵器/拳脚）——玄术/神魂无实体可格（§5.1.3 修订）
	# v0.5 绕后：招架层失效——背后看不见来剑（守势集中护体加成同由 flank 关断，见 _apply_hit）
	var physical: bool = attacker.active_technique != null and attacker.active_technique.category in ["兵器", "拳脚"]
	if physical and not flank and (target.guard_parts.has(part) or target.stance == "招架"):
		if realm_d >= 1:
			# 战力差距阶梯：差一阶招架必破（§5.1.3）
			_say(Nar.crush_guard(attacker, target))
		else:
			var force: float = attacker.attack_power * move.power_mod * _prof_coeff(attacker) + atk_speed * 0.5
			var parry_val: float = target.parry + (STANCE_PARRY_BONUS if target.stance == "招架" else 0.0) + target.agility * PARRY_AGILITY_WEIGHT
			if force <= parry_val:
				_say(Nar.parry_success(target, attacker))
				AudioManager.sfx("招架")
				_spawn_fx("spark", _cell_center(target.pos), _cell_center(target.pos))
				_break_intent(attacker)
				_stat_bump("parry_ok")
				ResourceSystem.drain(target, "体力", PARRY_STAMINA_COST)
				_apply_cooldown(attacker, move)
				return
			_say(Nar.parry_broken(target, attacker))
			AudioManager.sfx("破格挡")
			_spawn_fx("break", _cell_center(target.pos), _cell_center(target.pos))
			_stat_bump("parry_break")
			ResourceSystem.drain(target, "体力", PARRY_BREAK_STAMINA)
			# 耐久与脱手只针对持械者（空手无耐久、无可脱）
			if target.weapon != "空手":
				target.weapon_durability = maxf(0.0, target.weapon_durability - 1.0)
				if target.weapon_durability <= 0.0 or force > parry_val * DISARM_RATIO:
					target.weapon_disarmed = true
					target.weapon_durability = 10.0  # 拾回后耐久重置（P0 简化）
					_say(Nar.parry_disarm(target, attacker))
					AudioManager.sfx("脱手")
					_stat_bump("disarm")
					_recalc_stats(target)
	# —— ③ 代受层（要害被攻，境界差<2 且守方反应够快 → 用非致命部位换命）——
	if target.body[part].vital:
		if "无视代受" in move.effects:
			_say(Nar.ignore_substitute(attacker, target))
		elif realm_d >= 2:
			_say(Nar.crush_guard(attacker, target))
		else:
			var sub: String = BodySystem.substitute_for(target, part)
			if sub != "":
				var reaction: float = target.agility * ResourceSystem.stamina_penalty(target)
				if reaction >= atk_speed * SUB_REACTION_FACTOR:
					_say(Nar.substitute(target, part, sub))
					AudioManager.sfx("代受")
					_spawn_fx("sub", _cell_center(target.pos), _cell_center(target.pos))
					_stat_bump("substitute")
					part = sub
				else:
					_say(Nar.substitute_fail(attacker, target, part))
					_stat_bump("sub_fail")
	# —— ④ 护体层（破防模型，按部位——§5 + §5.1.5）——
	_apply_hit(attacker, target, part, move, realm_d, flank)
	_apply_cooldown(attacker, move)


## ④ 护体层 + 肉身伤势（v0.5《战斗系统》§5.1.5 罩层 / §5.3 受伤程度链）：
## 破防（ap > 有效护体）→ 先耗罩（罩足=护体受震，无创伤无流血；告破后余量才进肉身）→
## 肉身强度二次衰减 → 对气血比例定伤档（不按倍数）；未破防：相近磨防、差距大无伤。
## 罩层在 armor 之外且只在破防时耗（磨防走 armor，数值简单）；境界差≥2 → 罩与肉身形同虚设（§5.1.3）。
## v0.5 绕后：守势集中（guard_parts/铁壁）护体加成只对正面对敌生效——flank 时看不见来剑。
func _apply_hit(attacker: Unit, target: Unit, part: String, move: Move, realm_d: int, flank: bool) -> void:
	var ap: float = attacker.attack_power * move.power_mod * _prof_coeff(attacker)
	var armor: float = target.armor
	if realm_d >= 2:
		armor = 0.0
	elif target.guard_parts.has(part) and not flank:
		armor *= IRON_ARMOR_MULT if target.stance == "铁壁" else GUARD_ARMOR_MULT
	var tc: Vector2 = _cell_center(target.pos)
	var ac: Vector2 = _cell_center(attacker.pos)
	if ap <= armor:
		# —— 未破防：相近磨防（-4，永不回） / 差距大无伤 ——
		if target.armor - ap <= WEAR_THRESHOLD:
			target.armor = maxf(target.armor - ARMOR_WEAR, 0.0)
			_say(Nar.wear(attacker, target))
			AudioManager.sfx("磨防")
			_spawn_fx("wear", tc, tc)
		else:
			_say(Nar.no_damage(attacker, target))
			AudioManager.sfx("无伤")
			_spawn_fx("block", tc, tc)
		return
	# —— ④a 护体玄气层（罩先耗——罩是破防余量的缓冲带）——
	var net: float = ap - armor
	if realm_d < 2 and target.shield_cur > 0.0:
		var absorb: float = minf(target.shield_cur, net)
		target.shield_cur = maxf(0.0, target.shield_cur - absorb)
		net -= absorb
		_stat_bump("shield_absorb")
		if target.shield_cur <= 0.0 and not target.shield_broken_noted:
			target.shield_broken_noted = true  # 罩首次归零解说一次（此后破防直伤肉身）
			_say(Nar.shield_break(target))
			AudioManager.sfx("破罩")
			_spawn_fx("break", tc, tc)
			_stat_bump("shield_break")
		if net <= 0.0:
			# 护体受震——伤不及体：无创伤无流血（剑意同被招架而溃）
			_say(Nar.shield_hit(attacker, target))
			AudioManager.sfx("护体")
			_spawn_fx("wear", tc, tc, {"text": "护体受震"})
			_break_intent(attacker)
			return
	# —— ④b 受伤程度链（不按倍数：余量 → 肉身强度二次衰减 → 对气血比例定档）——
	var net2: float = net if realm_d >= 2 else net * (1.0 - FLESH_ABSORB.get(target.realm, 0.2))
	var qi_max: float = maxf(float(target.pools["气血"]["max"]), 1.0)
	var r: float = net2 / qi_max
	var severity: int = 1 if r < WOUND_LIGHT_RATIO else (2 if r < WOUND_HEAVY_RATIO else 3)
	if realm_d >= 2:
		severity = maxi(severity, 2)  # 战力差距阶梯伤害加深底线保留（§5.1.3）
	_say(Nar.attack_break(attacker, target, attacker.active_technique, move, part))
	var cat: String = attacker.active_technique.category if attacker.active_technique != null else ""
	# 特效与音效同点（视听同点——P1 换帧动画只替换 _draw_fx）
	if move.move_type == "大招":
		AudioManager.sfx("大招")
		_spawn_fx("hit", tc, tc, {"color": Color(0.2, 0.55, 0.6)})
	else:
		AudioManager.sfx({"兵器": "剑击", "拳脚": "钝击", "玄术": "火浪"}.get(cat, "剑击"))
		match cat:
			"兵器":
				_spawn_fx("slash", ac, tc)
			"玄术":
				_spawn_fx("fire", ac, tc)
		var hit_col: Color = {
			"兵器": Color(0.2, 0.55, 0.6), "拳脚": Color(0.75, 0.6, 0.3), "玄术": Color(0.85, 0.35, 0.12),
		}.get(cat, Color(0.2, 0.55, 0.6))
		_spawn_fx("hit", tc, tc, {"color": hit_col})
	BodySystem.hurt(target, part, severity)
	# —— 流血掷骰（v0.5 §2.3：edge 锋利度 × blade 刃长 × 部位状态——纯刃必流 / 钝器大概率不流）——
	var weapon: String = "空手" if attacker.weapon_disarmed else attacker.weapon
	if cat in ["兵器", "拳脚"]:
		var p_bleed: float = minf(1.0, EDGE_P[WeaponData.edge(weapon)]
			* BLADE_MULT[WeaponData.blade(weapon)] * SEV_BLEED_MULT.get(int(target.body[part].state), 0.6))
		if _rng.randf() < p_bleed:
			BodySystem.set_bleeding(target, part, true)
			_say(Nar.bleed_wound(attacker, target, part))
			_stat_bump("bleed_start")
	# 主臂被毁 → 自动换手（§2.5）
	if part == target.main_arm and int(target.body[part].state) == BodySystem.PartState.DESTROYED:
		if BodySystem.switch_main_arm(target):
			_say(Nar.switch_hand(target))
			_stat_bump("switch_hand")
	_recalc_stats(target)  # 伤效即时生效
	# 功法修为精进（命中 +5，一称号档）
	_gain_proficiency(attacker)
	# 剑意结算（《功法系统》§3：按谱命中积累/乱序不积/被打断清空）
	_on_intent_hit(attacker, move)
	# 要害被毁（一击毙命途）
	var b: Dictionary = target.body[part]
	if b.state == BodySystem.PartState.DESTROYED and b.vital:
		_say(Nar.attack_vital(attacker, target, part))
	# 招式机制标签
	if "灼烧" in move.effects:
		StatusSystem.add_status(target, "灼烧", 3)
		_say(Nar.burn(target))
		AudioManager.sfx("灼烧")
		_spawn_fx("burn", tc, tc)


func _gain_proficiency(u: Unit) -> void:
	var tech: Technique = u.active_technique
	if tech == null:
		return
	var before: float = u.technique_proficiency.get(tech.id, 0.0)
	u.technique_proficiency[tech.id] = before + PROF_GAIN
	if Grades.title(before) != Grades.title(before + PROF_GAIN):
		_say(Nar.proficiency_up(u, tech, Grades.title(before + PROF_GAIN)))


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
	AudioManager.sfx("服药")
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
		AudioManager.sfx("死亡")
		_spawn_fx("death", _cell_center(u.pos), _cell_center(u.pos))
		_battle_end(u, cause)


func _battle_end(loser: Unit, cause: String = "") -> void:
	battle_over = true
	TimelineSystem.active = false
	hud.enable_actions(false)
	hud.show_restart()
	var winner: Unit = opponent if loser == player else player
	_say(Nar.end(winner))
	AudioManager.sfx("胜利" if winner == player else "失败")
	if _autoplay:
		_auto_restart_left = 30
		print("AUTOPLAY battle end: winner=%s loser=%s cause=%s 回合数=%d 统计=%s 双方部位=%s vs %s" % [
			winner.display_name, loser.display_name, cause, _battle_turns,
			_stat, _brief_body(loser), _brief_body(winner),
		])


## 自对弈简报：各部位状态速览（如 头部[毁] 左臂[轻伤]）
func _brief_body(u: Unit) -> String:
	var out: Array[String] = []
	for part in u.body:
		var st: int = u.body[part].state
		if st != BodySystem.PartState.OK:
			out.append("%s[%s]" % [part, BodySystem.STATE_NAMES[st]])
	return " ".join(out) if not out.is_empty() else "无伤"


# ---------- 剑意机制（《功法系统》§3：按谱出招积累剑意 / 连击解锁变招 / 被打断溃散） ----------

## 有谱机制？——variants（变招/大招池）非空的功法有谱
func _has_song(u: Unit) -> bool:
	return u.active_technique != null and not u.active_technique.variants.is_empty()


## 谱下一式：谱 = 功法 moves 数组顺序（剑意层推进循环——叁层后回到起手式）
func _on_beat_move(u: Unit) -> Move:
	if not _has_song(u):
		return null
	var moves: Array = u.active_technique.moves
	if moves.is_empty():
		return null
	return moves[u.sword_intent % moves.size()]


func _is_on_beat(u: Unit, move: Move) -> bool:
	var beat: Move = _on_beat_move(u)
	return beat != null and beat.id == move.id


## 变招/大招解锁判定：剑意层 + 功法修为（修为是机制解锁的挂钩点，§2.1）
func variant_unlocked(u: Unit, m: Move) -> bool:
	if u.sword_intent < m.unlock_intent:
		return false
	var prof: float = u.technique_proficiency.get(u.active_technique.id, 0.0)
	return prof >= m.unlock_proficiency


## 剑意溃散（被打断：被闪避/被招架——§3 风险；挂在单位上，切换功法不清空）
func _break_intent(u: Unit) -> void:
	if u.sword_intent <= 0:
		return
	u.sword_intent = 0
	_say(Nar.intent_break(u))
	AudioManager.sfx("溃散")
	_spawn_fx("intent_break", _cell_center(u.pos), _cell_center(u.pos), {"text": "剑意溃散"})
	_stat_bump("intent_break")


## 命中剑意结算（破防命中才叫「命中」——磨防/无伤不算；§3）
func _on_intent_hit(attacker: Unit, move: Move) -> void:
	if not _has_song(attacker):
		return
	if move.move_type == "大招":
		_stat_bump("ultimate_used")
		return
	if move.move_type == "变招":
		_stat_bump("variant_used")
		return
	if _is_on_beat(attacker, move):
		if attacker.sword_intent < 3:
			attacker.sword_intent += 1
			var level: int = attacker.sword_intent
			_say(Nar.intent_up(attacker, level))
			AudioManager.sfx("剑意")
			_spawn_fx("intent_up", _cell_center(attacker.pos), _cell_center(attacker.pos), {"text": "剑意·%s层" % Nar.INTENT_NAMES[level - 1]})
			_stat_bump("intent_up")
			# 解锁变招提示
			for v in attacker.active_technique.variants:
				if v.unlock_intent == level:
					_say(Nar.variant_unlocked(attacker, v))
	else:
		_say(Nar.off_beat(attacker))


# ---------- 招式工具 ----------

## 随机出招（英雄坛说式）。include_variants：AI 用 true（谱意识+用变招/大招，自对弈可验证剑意机制）；
## 玩家普攻用 false——变招/大招只能手动选（随机消耗剑意不可控，体验差）
func _pick_random_move(u: Unit, include_variants: bool = false) -> Move:
	var tech: Technique = u.active_technique
	if tech == null or tech.moves.is_empty():
		return null
	var ready: Array[Move] = []
	for m in tech.moves:
		if _move_cd(u, m) <= 0 and BodySystem.can_use_move(u, m):
			ready.append(m)
	if include_variants:
		var ultimate: Move = null
		for v in tech.variants:
			if _move_cd(u, v) <= 0 and BodySystem.can_use_move(u, v) and variant_unlocked(u, v):
				ready.append(v)
				if v.move_type == "大招":
					ultimate = v
		if ultimate != null and _rng.randf() < 0.3:
			return ultimate
	if ready.is_empty():
		return null
	# 谱机制功法：50% 权重按谱出下一式（AI 也打谱）
	var beat: Move = _on_beat_move(u)
	if beat != null and ready.has(beat) and _rng.randf() < 0.5:
		return beat
	return ready[_rng.randi() % ready.size()]


## 普攻无招可用的原因提示：全部冷却 vs 手臂已废（§2.5）
func _no_move_reason(u: Unit) -> Dictionary:
	var tech: Technique = u.active_technique
	for m in tech.moves:
		if _move_cd(u, m) > 0:
			return Nar.all_cd(tech)
	return Nar.arm_disabled(u, tech.moves[0])


func _find_move(u: Unit, move_id: String) -> Move:
	if u.active_technique == null:
		return null
	for m in u.active_technique.moves:
		if m.id == move_id:
			return m
	for m in u.active_technique.variants:
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
			if _move_cd(u, m) <= 0 and BodySystem.can_use_move(u, m):
				r = maxi(r, _eff_range(u, m).y)
	return r


## 熟练度档系数（《功法系统》§2.2）——招式威力与臂伤「临时降档」的落点
func _prof_coeff(u: Unit) -> float:
	var tech: Technique = u.active_technique
	if tech == null:
		return 1.0
	var prof: float = u.technique_proficiency.get(tech.id, 0.0)
	var tier: int = Grades.tier(prof) - int(BodySystem.injury_multipliers(u).prof_down)
	tier = clampi(tier, 0, PROF_TIER_COEFFS.size() - 1)
	return PROF_TIER_COEFFS[tier]


func _apply_cooldown(attacker: Unit, move: Move) -> void:
	if move.cooldown > 0:
		attacker.cooldowns[move.id] = move.cooldown


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


func _bleeding(u: Unit) -> bool:
	return BodySystem.bleed_amount(u) > 0.0


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _pixel_to_cell(p: Vector2) -> Vector2i:
	var cell := Vector2i(floori((p.x - ORIGIN.x) / CELL), floori((p.y - ORIGIN.y) / CELL))
	if not FieldSystem.in_bounds(cell):
		return Vector2i(-1, -1)
	return cell


# ---------- 表现层：特效与插值（P0 程序化占位——P1 帧动画替换只动本段与 _draw_fx） ----------

func _cell_center(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)


## 特效入队：{kind, t, dur, a, b, color, text}——a/b 为格中心坐标
func _spawn_fx(kind: String, a: Vector2, b: Vector2, extra: Dictionary = {}) -> void:
	_fx.append({
		"kind": kind, "t": 0.0, "dur": extra.get("dur", 0.35),
		"a": a, "b": b, "color": extra.get("color", Color.WHITE), "text": extra.get("text", ""),
	})


func _update_fx(delta: float) -> void:
	for f in _fx:
		f.t += delta
	_fx = _fx.filter(func(f): return f.t < f.dur)


## 单位绘制位置插值（移动平滑，~8 格/秒）与死亡淡出
func _update_render(u: Unit, delta: float) -> void:
	if u == null:
		return
	u.render_pos = u.render_pos.lerp(_cell_center(u.pos), minf(1.0, delta * 8.0))
	if not u.alive:
		u.render_alpha = maxf(0.0, u.render_alpha - delta * 1.6)


## 特效绘制（与 AudioManager.sfx 同点触发——视听同点）
func _draw_fx() -> void:
	for f in _fx:
		var k: float = f.t / f.dur  # 0→1
		var b: Vector2 = f.b
		var a: Vector2 = f.a
		match f.kind:
			"hit":
				draw_arc(b, 10.0 + 20.0 * k, 0, TAU, 24, Color(f.color, 1.0 - k), 3.0)
			"slash":
				_draw_slash(a, b, k)
			"fire":
				draw_line(a, b, Color(0.85, 0.35, 0.12, (1.0 - k) * 0.7), 10.0 * (1.0 - k))
			"spark":
				var c2 := Color(0.9, 0.85, 0.5, 1.0 - k)
				var r2: float = 10.0 + 14.0 * k
				draw_line(b + Vector2(-r2, 0), b + Vector2(r2, 0), c2, 2.0)
				draw_line(b + Vector2(0, -r2), b + Vector2(0, r2), c2, 2.0)
			"break":
				var c3 := Color(0.75, 0.6, 0.2, 1.0 - k)
				for i in 8:
					var ang := TAU * i / 8.0
					var dir := Vector2(cos(ang), sin(ang))
					draw_line(b, b + dir * (8.0 + 22.0 * k), c3, 2.0)
			"dodge":
				draw_circle(b + Vector2(-16.0 * k, -6.0 * k), 16.0, Color(0.5, 0.75, 1.0, (1.0 - k) * 0.35))
			"sub":
				draw_circle(b, 18.0, Color(0.85, 0.2, 0.15, (1.0 - k) * 0.5))
			"wear":
				draw_arc(b, 14.0 + 12.0 * k, 0, TAU, 24, Color(0.85, 0.75, 0.3, (1.0 - k) * 0.8), 2.0)
			"block":
				draw_circle(b, 16.0, Color(0.75, 0.75, 0.75, (1.0 - k) * 0.55))
			"burn":
				for i in 5:
					var t2 := fmod(k * 3.0 + i * 0.37, 1.0)
					draw_circle(b + Vector2((i - 2) * 7.0, -t2 * 22.0), 3.0 * (1.0 - t2), Color(0.9, 0.35, 0.1, 1.0 - t2))
			"death":
				draw_circle(b, 10.0 + 40.0 * k, Color(0.12, 0.1, 0.1, (1.0 - k) * 0.55))
			"guard":
				draw_arc(b, 20.0 + 10.0 * k, 0, TAU, 24, Color(0.9, 0.9, 0.85, (1.0 - k) * 0.8), 2.0)
			"intent_up":
				draw_arc(b, 18.0 + 16.0 * k, 0, TAU, 24, Color(0.2, 0.55, 0.6, (1.0 - k) * 0.9), 2.5)
				draw_arc(b, 10.0 + 16.0 * k, 0, TAU, 24, Color(0.2, 0.55, 0.6, (1.0 - k) * 0.55), 1.5)
			"intent_break":
				var c4 := Color(0.35, 0.4, 0.45, 1.0 - k)
				for i in 8:
					var ang := TAU * i / 8.0
					var dir := Vector2(cos(ang), sin(ang))
					var r4: float = 20.0 - 14.0 * k
					draw_line(b + dir * r4, b + dir * (r4 + 6.0), c4, 2.0)
			"move":
				draw_line(a, b, Color(0.4, 0.6, 0.9, (1.0 - k) * 0.35), 3.0)
		if not f.text.is_empty():
			_draw_fx_text(f)


## 浮动文字（升层/溃散提示）
func _draw_fx_text(f: Dictionary) -> void:
	var k: float = f.t / f.dur
	var font := ThemeDB.fallback_font
	draw_string(font, f.b + Vector2(-32, -34 - 14.0 * k), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.2, 0.55, 0.6, 1.0 - k))


## 剑光弧（攻击者→目标格弧形光带，月白青黛渐隐）
func _draw_slash(a: Vector2, b: Vector2, k: float) -> void:
	var dir := b - a
	var perp := Vector2(-dir.y, dir.x).normalized()
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(a.lerp(b, t) + perp * sin(t * PI) * 26.0)
	for i in 8:
		draw_line(pts[i], pts[i + 1], Color(0.75, 0.9, 0.95, (1.0 - k) * 0.8), 3.0 * (1.0 - k) + 1.0)


# ---------- 表现层绘制 ----------

func _draw() -> void:
	# 整屏水墨背景（氛围层）→ 纸色遮罩压淡（布局 v0.4）
	draw_texture_rect(TEX_BG, Rect2(Vector2.ZERO, Vector2(1280, 720)), false)
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.96, 0.93, 0.86, 0.5))
	# 棋盘底图（600×600 精确对齐逻辑棋盘——不压淡，是主战场面）
	draw_texture_rect(TEX_BOARD, Rect2(ORIGIN, Vector2(FieldSystem.GRID_W * CELL, FieldSystem.GRID_H * CELL)), false)
	# 战术网格线（墨线叠在棋盘底图上，逻辑格以网格线为准）
	for x in range(FieldSystem.GRID_W + 1):
		draw_line(
			ORIGIN + Vector2(x * CELL, 0), ORIGIN + Vector2(x * CELL, FieldSystem.GRID_H * CELL),
			Color(0.35, 0.32, 0.25, 0.22), 1.0)
	for y in range(FieldSystem.GRID_H + 1):
		draw_line(
			ORIGIN + Vector2(0, y * CELL), ORIGIN + Vector2(CELL * FieldSystem.GRID_W, y * CELL),
			Color(0.35, 0.32, 0.25, 0.22), 1.0)
	# 可移动范围高亮（玩家回合；双腿已毁则不可移动）——v0.5：带权可达集（区内逼近 2 步/横退 1 步）+ 威胁区描边
	if current_actor == player and not battle_over and BodySystem.leg_penalty(player) != 3:
		var move_map: Dictionary = _move_graph(player, opponent, player.move_left).dist
		for x in range(FieldSystem.GRID_W):
			for y in range(FieldSystem.GRID_H):
				var c := Vector2i(x, y)
				if c == player.pos or c == opponent.pos:
					continue
				if move_map.has(c):
					draw_rect(
						Rect2(ORIGIN + Vector2(x * CELL + 10.0, y * CELL + 10.0), Vector2(CELL - 20, CELL - 20)),
						Color(0.35, 0.9, 0.45, 0.18))
				if _in_threat(c, opponent):
					draw_rect(
						Rect2(ORIGIN + Vector2(x * CELL + 4.0, y * CELL + 4.0), Vector2(CELL - 8, CELL - 8)),
						Color(0.85, 0.25, 0.2, 0.35), false, 1.5)  # 敌方武器威胁区描边——区内朝敌逼近步价 ×2
	_draw_unit(player, Color(0.4, 0.8, 1.0))
	_draw_unit(opponent, Color(1.0, 0.45, 0.45))
	_draw_fx()


func _draw_unit(u: Unit, color: Color) -> void:
	if u == null:
		return
	var alpha := u.render_alpha
	if alpha <= 0.0:
		return
	# 用插值位置绘制（移动平滑）；逻辑格以网格线为准
	var center: Vector2 = u.render_pos
	var top_left := center - Vector2(CELL / 2.0 - 6.0, CELL / 2.0 - 6.0)
	# 阵营底色（精灵对比度兜底）
	draw_rect(Rect2(top_left, Vector2(CELL - 12, CELL - 12)), Color(color, 0.22 * alpha))
	# 战斗精灵（等比缩入 48×48 格内）——v0.5 朝向镜像：美术只出一套朝向，经缩放镜像（面右基准，
	# SPRITE_DIR 修正贴图原始朝向；试玩发现镜像反了只改这一常数，不动资产）
	var tex: Texture2D = TEX_SPRITES.get(u.id, null)
	if tex != null:
		var ts: Vector2 = tex.get_size()
		var cell_rect := Rect2(top_left, Vector2(CELL - 12, CELL - 12))
		var k := minf(cell_rect.size.x / ts.x, cell_rect.size.y / ts.y)
		var draw_size := ts * k
		var mirrored: bool = u.vis_facing * SPRITE_DIR < 0.0
		# 变换原点必须无条件落到格中心：纹理 Rect 以 (0,0) 为心绘制，若只在镜像时设
		# transform，非镜像态原点留在屏幕 (0,0)，负偏移把整图推到视口左上外（精灵消失根因）
		draw_set_transform(cell_rect.get_center(), 0.0, Vector2(-1.0 if mirrored else 1.0, 1.0))
		draw_texture_rect(tex, Rect2(-draw_size / 2.0, draw_size), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # 复位（后续描边/ATB 条不受镜像）
	# 当前行动者高亮描边
	if current_actor == u:
		draw_rect(Rect2(top_left, Vector2(CELL - 12, CELL - 12)), Color(1.0, 0.9, 0.3, alpha), false, 3.0)
	# ATB 行动条
	var bar_w := (CELL - 12) * clampf(u.atb_progress / 100.0, 0.0, 1.0)
	draw_rect(Rect2(top_left + Vector2(0, CELL - 2), Vector2(bar_w, 6)), Color(0.9, 0.85, 0.3, alpha))


# ---------- 调试 ----------

## 注意：不能叫 log——与 GDScript 内置数学函数 log() 撞名
func log_msg(text: String) -> void:
	if hud != null:
		hud.log(text)


func _take_debug_shots(delta: float) -> void:
	if _shot_fx_mode:
		# 特效触发模式：_fx 非空（有活跃特效）才拍，每 3 帧一张、10 张后退出——
		# 自对弈 4x 加速下特效真实时长仅 0.05~0.12s，定时拍必然错过，须由特效事件驱动
		_shot_fx_frame += 1
		if _fx.is_empty() or _shot_fx_frame % 3 != 0:
			return
		_save_debug_shot("fxshot_%02d.png" % (_shot_count + 1))
		return
	# 定时模式：每秒一张
	_shot_elapsed += delta
	if _shot_elapsed < float(_shot_count + 1):
		return
	_save_debug_shot("shot_%d.png" % (_shot_count + 1))


func _save_debug_shot(file_name: String) -> void:
	_shot_count += 1
	var tex := get_viewport().get_texture()
	if tex == null:
		# headless 下无渲染纹理——截图调试须窗口模式运行
		print("DEBUG headless 无渲染纹理，截图模式退出（请去掉 --headless 运行）")
		get_tree().quit()
		return
	var img := tex.get_image()
	DirAccess.make_dir_recursive_absolute("res://_debug")
	img.save_png("res://_debug/%s" % file_name)
	var fx_desc := ""
	if not _fx.is_empty():
		var names: Array[String] = []
		for f in _fx:
			names.append(f.kind)
		fx_desc = " fx=%s" % str(names)
	print("DEBUG %s saved (actor=%s%s)" % [file_name, current_actor.display_name if current_actor != null else "none", fx_desc])
	if _shot_count == 1:
		print("DEBUG hud rect=", hud.get_rect())
		print("DEBUG log_rtl pos=", hud.log_rtl.position, " size=", hud.log_rtl.size)
		print("DEBUG action_row pos=", hud.action_row.position, " size=", hud.action_row.size)
	if _shot_count >= 6 and not _shot_fx_mode or _shot_count >= 10:
		get_tree().quit()
