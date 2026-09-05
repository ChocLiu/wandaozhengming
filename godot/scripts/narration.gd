class_name Narration
## 武侠叙事解说生成器——模板 + 变体 + 着色。
## 所有函数返回 {t: 文本, c: 颜色}，调用方通过 hud.log_nar(t, c) 输出。
## 变体词库防疲劳；着色按事件类型（破防红/招架灰/规则金/灼烧橙/死亡深红/信息白）。

# 墨色系解说配色（纸面 UI——浅色卷轴底 + 深色墨字，布局 v0.0.4）
const C_HIT := Color(0.55, 0.14, 0.1)     # 破防：朱砂墨
const C_PARRY := Color(0.33, 0.37, 0.42)  # 招架/闪避：青灰墨
const C_WEAR := Color(0.5, 0.5, 0.48)     # 磨防/失血：淡墨
const C_RULE := Color(0.6, 0.42, 0.08)    # 规则：赭金墨
const C_BURN := Color(0.75, 0.32, 0.08)   # 灼烧：赤橙墨
const C_DEATH := Color(0.52, 0.05, 0.05)  # 死亡：重朱
const C_INFO := Color(0.14, 0.12, 0.09)   # 信息：浓墨


static func pick(variants: Array) -> String:
	return variants[randi() % variants.size()]


# ---------- 出招与命中 ----------

static func attack_break(attacker, target, tech, move, part: String) -> Dictionary:
	var v := pick([
		"%s一式《%s》「%s」直取%s的「%s」——破甲而入！",
		"%s催动《%s》，「%s」寒芒直奔%s——「%s」防御如纸，一击贯穿！",
		"%s一声长啸，《%s》「%s」出手，%s的「%s」血光迸现！",
	])
	return {"t": v % [attacker.display_name, tech.display_name, move.display_name, target.display_name, part], "c": C_HIT}


static func attack_vital(attacker, target, part: String) -> Dictionary:
	var v := pick([
		"——正中命门！%s的「%s」被毁！",
		"——这一下直取要害，%s的「%s」当场被毁！",
	])
	return {"t": v % [target.display_name, part], "c": C_DEATH}


## ①层闪避（速度对抗胜——被动常驻层，无代价）
static func dodge(target, attacker) -> Dictionary:
	var v := pick([
		"千钧一发，%s堪堪闪开%s的杀招",
		"%s身形一晃，躲过%s这一击",
	])
	return {"t": v % [target.display_name, attacker.display_name], "c": C_PARRY}


## ②层招架（守势覆盖/招架架势——兵刃格挡）
static func parry_success(target, attacker) -> Dictionary:
	var v := pick([
		"%s兵刃一横，稳稳架住%s的攻势！",
		"%s看破%s来路，格挡于守势之内！",
	])
	return {"t": v % [target.display_name, attacker.display_name], "c": C_PARRY}


static func parry_broken(target, attacker) -> Dictionary:
	var v := pick([
		"%s的格挡被%s硬生生荡开——破格挡！",
		"%s力量更胜一筹，%s的兵刃挡不住，防线被破！",
	])
	return {"t": v % [target.display_name, attacker.display_name], "c": C_HIT}


static func parry_disarm(target, attacker) -> Dictionary:
	return {"t": "%s兵刃脱手飞出！%s仓皇失色" % [target.display_name, attacker.display_name], "c": C_HIT}


## 战力差距阶梯（差一阶招架必破——守势形同虚设）
static func crush_guard(attacker, target) -> Dictionary:
	return {"t": "%s的境界压制之下，%s的格挡如同虚设！" % [attacker.display_name, target.display_name], "c": C_RULE}


## ③层代受（要害被破前，用非致命部位换命）
static func substitute(target, part: String, sub: String) -> Dictionary:
	var v := pick([
		"%s来不及回防——「%s」一横，代受了攻向「%s」的杀招！",
		"电光石火间，%s以「%s」挡下了攻向「%s」的一击！",
	])
	return {"t": v % [target.display_name, sub, part], "c": C_WEAR}


static func substitute_fail(attacker, target, part: String) -> Dictionary:
	return {"t": "%s攻势太快，%s来不及代受——「%s」直接暴露！" % [attacker.display_name, target.display_name, part], "c": C_HIT}


static func wear(attacker, target) -> Dictionary:
	var v := pick([
		"剑锋被%s的护体玄气阻住——只削去一层防御",
		"这一击闷在%s的护体气劲上，防御被磨去几分",
	])
	return {"t": v % [target.display_name], "c": C_WEAR}


static func no_damage(attacker, target) -> Dictionary:
	var v := pick([
		"这一击如击金石——%s的防御远高于此，纹丝不动",
		"%s岿然不动，这一击连印记都没留下",
	])
	return {"t": v % [target.display_name], "c": C_WEAR}


# ---------- 规则 ----------

static func rule_crush(attacker, rule: String, tier_name: String) -> Dictionary:
	var v := pick([
		"这一击分明慢了半息，却像早已写在对方身上——%s之道·%s，避无可避！",
		"%s规则展开（%s）——速度已成虚妄，这一击注定命中！",
	])
	return {"t": v % [rule, tier_name], "c": C_RULE}


static func rule_fail(attacker, rule: String) -> Dictionary:
	return {"t": "%s融入%s规则，但对方领悟不弱于你，未能碾压" % [attacker.display_name, rule], "c": C_INFO}


static func no_rule() -> Dictionary:
	return {"t": "没有可融入的法则（功法无融入槽，或未领悟对应规则）", "c": C_INFO}


static func no_xuan() -> Dictionary:
	return {"t": "玄力不足，无法融入规则", "c": C_INFO}


# ---------- 状态/行动 ----------

static func burn(target) -> Dictionary:
	return {"t": "%s被灼烧！烈焰缠身，每回合流失气血" % target.display_name, "c": C_BURN}


static func bleed_tick(u) -> Dictionary:
	var v := pick([
		"%s的伤口仍在淌血……",
		"血珠从%s的创口滚落……",
	])
	return {"t": v % [u.display_name], "c": C_WEAR}


## 守势宣言（§5.1.2）
static func guard_declared(u, parts: String, stance_name: String) -> Dictionary:
	var v := pick([
		"%s护住「%s」，摆开%s架势",
		"%s收摄心神——「%s」已在%s架势笼罩之下",
	])
	return {"t": v % [u.display_name, parts, stance_name], "c": C_INFO}


static func guard_initial(u) -> Dictionary:
	return {"t": "双方对峙，%s先护住周身要害，摆开招架架势" % u.display_name, "c": C_INFO}


static func no_guard_parts() -> Dictionary:
	return {"t": "至少选一个重点保护部位（点自己的部位按钮）", "c": C_INFO}


static func guard_full() -> Dictionary:
	return {"t": "守势最多重点保护两处——先取消一处再选新的", "c": C_INFO}


static func seal(u) -> Dictionary:
	return {"t": "%s服下止血丹——创口止血，血不再流" % u.display_name, "c": C_INFO}


static func item_used_this_turn(u) -> Dictionary:
	return {"t": "%s本回合已服过此丹，药力未化，不宜再服" % u.display_name, "c": C_INFO}


static func no_item(u) -> Dictionary:
	return {"t": "%s摸向药囊——止血丹已经用尽了" % u.display_name, "c": C_INFO}


static func move(u, steps: int) -> Dictionary:
	var v := pick([
		"%s提气纵身，欺近%d步",
		"%s身形一闪，连踏%d步",
	])
	return {"t": v % [u.display_name, steps], "c": C_INFO}


static func move_fail(u) -> Dictionary:
	return {"t": "%s气息不济，迈不动步子" % u.display_name, "c": C_INFO}


static func out_of_range(steps: int) -> Dictionary:
	return {"t": "距离不够——先点棋盘走近（还剩 %d 步）" % steps, "c": C_INFO}


static func no_stamina(attacker, pool: String, move) -> Dictionary:
	var what: String = move.display_name if move != null else "这一招"
	return {"t": "%s的%s不足，「%s」发不出去" % [attacker.display_name, pool, what], "c": C_INFO}


static func switch_tech(u, tech, weapon: String) -> Dictionary:
	var v := pick([
		"%s手法一变——换使《%s》（%s在手）！",
		"%s收了旧势，改走《%s》的路数（%s在手）！",
	])
	return {"t": v % [u.display_name, tech.display_name, weapon], "c": C_INFO}


static func cd_busy(move) -> Dictionary:
	return {"t": "「%s」尚未回气，强行使出必伤己身" % move.display_name, "c": C_INFO}


static func all_cd(tech) -> Dictionary:
	return {"t": "《%s》的招式皆未回气" % tech.display_name, "c": C_INFO}


static func no_switch() -> Dictionary:
	return {"t": "只有一门招式功法，无可切换", "c": C_INFO}


static func acted_already(u) -> Dictionary:
	return {"t": "%s本回合已出过手" % u.display_name, "c": C_INFO}


## 部位伤效（§2.5）
static func arm_disabled(u, move) -> Dictionary:
	return {"t": "%s的手臂已废，「%s」施展不出" % [u.display_name, move.display_name], "c": C_INFO}


static func switch_hand(u) -> Dictionary:
	return {"t": "%s主臂已废，咬牙换用%s！" % [u.display_name, u.main_arm], "c": C_INFO}


static func legs_destroyed(u) -> Dictionary:
	return {"t": "%s双腿已废，寸步难行！" % u.display_name, "c": C_INFO}


static func pickup_weapon(u) -> Dictionary:
	return {"t": "%s慌忙拾回兵刃" % u.display_name, "c": C_INFO}


static func proficiency_up(attacker, tech, title: String) -> Dictionary:
	return {"t": "%s的《%s》修为精进——「%s」" % [attacker.display_name, tech.display_name, title], "c": C_RULE}


# ---------- 剑意机制（《功法系统》§3） ----------

const INTENT_NAMES := ["壹", "贰", "叁"]


static func intent_up(u, level: int) -> Dictionary:
	var v := pick([
		"%s剑意如潮，已至%s层！",
		"%s心剑合一，剑意攀升——%s层！",
	])
	return {"t": v % [u.display_name, INTENT_NAMES[level - 1]], "c": C_RULE}


static func variant_unlocked(u, move) -> Dictionary:
	var v := pick([
		"剑意涌动——「%s」解锁！",
		"剑意贯通，「%s」可用！",
	])
	return {"t": v % move.display_name, "c": C_RULE}


static func variant_locked(move) -> Dictionary:
	return {"t": "剑意未至——「%s」还用不出来" % move.display_name, "c": C_INFO}


static func intent_break(u) -> Dictionary:
	var v := pick([
		"剑势被破——%s的剑意溃散！",
		"节奏一乱，%s积累的剑意散尽！",
	])
	return {"t": v % u.display_name, "c": C_PARRY}


static func off_beat(u) -> Dictionary:
	return {"t": "%s出招乱了谱序——这一式不积剑意" % u.display_name, "c": C_WEAR}


static func ultimate_drain(u, move) -> Dictionary:
	return {"t": "%s剑意尽数倾入「%s」——孤注一掷！" % [u.display_name, move.display_name], "c": C_RULE}


static func ignore_substitute(attacker, target) -> Dictionary:
	return {"t": "剑意如丝——%s无从代受，要害尽露！" % target.display_name, "c": C_HIT}


# ---------- v0.0.5：朝向与绕后 / 部位策略 / 流血 / 护体玄气（§1.1 / §2.3 / §5.2 / §5.3） ----------

static func flank(attacker, target) -> Dictionary:
	var v := pick([
		"%s已欺到%s身后——背门大开！",
		"%s绕到%s背后，出其不意！",
	])
	return {"t": v % [attacker.display_name, target.display_name], "c": C_RULE}


## 部位策略制（自动/随机/手动/重点）
static func strategy_set(u, mode: String) -> Dictionary:
	var desc: String = {"自动": "自动寻要害、打空当", "随机": "随手出招、落点随机", "手动": "每击弹出部位行、亲手点选"}.get(mode, "")
	return {"t": "%s的攻部位策略设为「%s」（%s）" % [u.display_name, mode, desc], "c": C_INFO}


static func focus_part_pick() -> Dictionary:
	return {"t": "重点策略：请点选敌方一个部位作为重点（点选一次即锁定，此后自动攻其要害）", "c": C_INFO}


static func focus_part_set(u, part: String) -> Dictionary:
	return {"t": "%s锁定「%s」为重点——此后出手专攻此部" % [u.display_name, part], "c": C_INFO}


static func focus_part_keep(u, part: String) -> Dictionary:
	return {"t": "重点部位仍是「%s」——若已毁则自动退回「自动」" % part, "c": C_INFO}


static func focus_part_lost() -> Dictionary:
	return {"t": "重点部位已被打毁——攻部位策略退回「自动」", "c": C_INFO}


## 流血掷骰（§2.3：纯刃必流 / 钝器大概率不流）
static func bleed_wound(attacker, target, part: String) -> Dictionary:
	var v := pick([
		"%s的「%s」创口开裂，鲜血涌出！",
		"一击见血！%s的「%s」血流不止",
	])
	return {"t": v % [target.display_name, part], "c": C_WEAR}


## 护体玄气（§5.1.5 罩层 / §5.2 策略制）
static func shield_hit(attacker, target) -> Dictionary:
	var v := pick([
		"%s的护体玄气一阵激荡——%s这一击伤不及体！",
		"%s的护体玄气如涟漪荡开，%s的攻势被尽数震散！",
	])
	return {"t": v % [target.display_name, attacker.display_name], "c": C_RULE}


static func shield_break(target) -> Dictionary:
	return {"t": "%s的护体玄气告破——玄光碎裂，肉身再无凭依！" % target.display_name, "c": C_RULE}


static func shield_strategy_set(u) -> Dictionary:
	var desc: String = {
		"守常": "不主动灌注，只付维持",
		"周天": "回合末补罩至上限（1 玄力:1）",
		"凝罡": "回合末凝气成罡至 125%（超限段 1.25×/点）",
		"守一": "回合末抱元守一至 150%（100~125% 段 1.25×、125~150% 段 1.5×/点）",
	}.get(u.shield_strategy, "")
	return {"t": "护体策略定为「%s」——%s（本回合末结算，此后沿用）" % [u.shield_strategy, desc], "c": C_INFO}


static func shield_pour(u, amount: float) -> Dictionary:
	return {"t": "%s引玄力温养护体玄气——罩回复 %.0f 点" % [u.display_name, amount], "c": C_RULE}


static func no_retreat_room(u) -> Dictionary:
	return {"t": "%s退无可退——背水一战！" % u.display_name, "c": C_INFO}


# ---------- 流程 ----------

static func start() -> Dictionary:
	return {"t": "紫微域外，一介散修拦路——斗法开始！", "c": C_INFO}


static func turn(u, steps: int) -> Dictionary:
	return {"t": "——轮到%s行动（可移动 %d 步）——" % [u.display_name, steps], "c": C_INFO}


## 回合自动结束（已出手且步数已尽——行动规则：移动耗步数、出招不耗）
static func turn_auto_end(u) -> Dictionary:
	return {"t": "%s已出手、步数已尽——本回合结束" % u.display_name, "c": C_INFO}


static func speed_contest(atk: float, defense: float) -> Dictionary:
	return {"t": "攻速 %.0f vs 防速 %.0f" % [atk, defense], "c": C_INFO}


static func death(u, cause: String) -> Dictionary:
	var text: String
	if cause == "失血":
		text = "%s血尽而亡，倒地不起" % u.display_name
	elif cause == "要害被毁":
		text = "%s的要害被毁——道基尽碎，当场陨落！" % u.display_name
	else:
		text = "%s陨落" % u.display_name
	return {"t": text, "c": C_DEATH}


static func end(winner) -> Dictionary:
	return {"t": "战斗结束——%s胜" % winner.display_name, "c": C_INFO}
