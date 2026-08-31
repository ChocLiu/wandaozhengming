class_name Narration
## 武侠叙事解说生成器——模板 + 变体 + 着色。
## 所有函数返回 {t: 文本, c: 颜色}，调用方通过 hud.log_nar(t, c) 输出。
## 变体词库防疲劳；着色按事件类型（破防红/招架灰/规则金/灼烧橙/死亡深红/信息白）。

const C_HIT := Color(0.95, 0.45, 0.45)
const C_PARRY := Color(0.62, 0.66, 0.72)
const C_WEAR := Color(0.72, 0.72, 0.8)
const C_RULE := Color(0.92, 0.8, 0.4)
const C_BURN := Color(0.95, 0.6, 0.3)
const C_DEATH := Color(0.92, 0.3, 0.3)
const C_INFO := Color(0.93, 0.93, 0.93)


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


static func parry(attacker, target) -> Dictionary:
	var v := pick([
		"%s侧身格挡，堪堪架住%s的攻势",
		"%s早有防备，格开了%s这一击",
		"千钧一发，%s横身闪避，躲了过去",
	])
	return {"t": v % [target.display_name, attacker.display_name], "c": C_PARRY}


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
		"%s规则展开——速度已成虚妄，这一击注定命中！",
	])
	return {"t": v % [rule, tier_name, rule], "c": C_RULE}


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


static func defend(u) -> Dictionary:
	var v := pick([
		"%s沉腰立马，摆出防御架势",
		"%s护住周身要害，严阵以待",
	])
	return {"t": v % u.display_name, "c": C_INFO}


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
	return {"t": "%s的%s不足，「%s」发不出去" % [attacker.display_name, pool, move.display_name], "c": C_INFO}


static func switch_tech(u, tech, weapon: String) -> Dictionary:
	var v := pick([
		"%s手法一变——换使《%s》（%s在手）！",
		"%s收了旧势，改走《%s》的路数！",
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


static func proficiency_up(attacker, tech, title: String) -> Dictionary:
	return {"t": "%s的《%s》修为精进——「%s」" % [attacker.display_name, tech.display_name, title], "c": C_RULE}


# ---------- 流程 ----------

static func start() -> Dictionary:
	return {"t": "紫微域外，一介散修拦路——斗法开始！", "c": C_INFO}


static func turn(u, steps: int) -> Dictionary:
	return {"t": "——轮到%s行动（可移动 %d 步）——" % [u.display_name, steps], "c": C_INFO}


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
