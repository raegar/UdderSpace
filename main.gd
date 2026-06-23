extends Node2D

const W := 1152.0
const H := 648.0
const GROUND_Y := 535.0
const UFO_SPEED := 430.0
const BEAM_RANGE := 365.0

enum GameState { TITLE, PLAYING, GAME_OVER }

var state := GameState.TITLE
var ufo_pos := Vector2(W * 0.5, 170.0)
var ufo_vel := Vector2.ZERO
var cows: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var stars: Array[Vector2] = []
var clouds: Array[Dictionary] = []
var score := 0
var combo := 0
var best_combo := 0
var time_left := 60.0
var beam_energy := 100.0
var beam_on := false
var screen_shake := 0.0
var flash := 0.0
var spawn_timer := 0.0
var captured := 0
var title_bob := 0.0
var time_drain := false
var time_drain_multiplier := 3.0
var lives := 3
var hit_flash := 0.0
var farmers: Array[Dictionary] = []
var pitchforks: Array[Dictionary] = []
var farmer_spawn_timer := 8.0
var carrots := 0
var shield_time := 0.0
const SHIELD_DURATION := 5.0
const SHIELD_COST := 5
var level := 1
var level_captured := 0
var level_banner_time := 0.0
var rng := RandomNumberGenerator.new()

func cows_to_clear() -> int:
	return 5 + level * 3

func max_farmers() -> int:
	return mini(6, 1 + level / 2)

func farmer_aim_time() -> float:
	return maxf(0.5, 1.5 - level * 0.12)

func pitchfork_speed() -> float:
	return 380.0 + level * 30.0

func cow_spawn_interval() -> Array:
	var lo := maxf(0.6, 1.5 - level * 0.1)
	var hi := maxf(1.2, 3.0 - level * 0.15)
	return [lo, hi]

func farmer_spawn_interval() -> Array:
	var lo := maxf(4.0, 10.0 - level * 1.0)
	var hi := maxf(7.0, 18.0 - level * 1.5)
	return [lo, hi]

func chunky_chance() -> float:
	return minf(0.35, 0.15 + level * 0.025)

func big_chance() -> float:
	return minf(0.55, 0.40 + level * 0.02)

func red_cow_chance() -> float:
	return minf(0.25, 0.12 + level * 0.015)

func _ready() -> void:
	rng.randomize()
	for i in 90:
		stars.append(Vector2(rng.randf_range(0, W), rng.randf_range(0, 390)))
	for i in 5:
		clouds.append({
			"pos": Vector2(rng.randf_range(0, W), rng.randf_range(80, 310)),
			"speed": rng.randf_range(5, 13),
			"scale": rng.randf_range(0.7, 1.4)
		})
	queue_redraw()

func start_game() -> void:
	state = GameState.PLAYING
	ufo_pos = Vector2(W * 0.5, 155)
	ufo_vel = Vector2.ZERO
	cows.clear()
	particles.clear()
	farmers.clear()
	pitchforks.clear()
	lives = 3
	hit_flash = 0.0
	farmer_spawn_timer = 8.0
	carrots = 0
	shield_time = 0.0
	level = 1
	level_captured = 0
	level_banner_time = 0.0
	score = 0
	combo = 0
	best_combo = 0
	captured = 0
	time_left = 60.0
	beam_energy = 100.0
	time_drain = false
	spawn_timer = 0.0
	for i in 8:
		spawn_cow(90.0 + i * 135.0 + rng.randf_range(-30, 30))

func spawn_cow(x := -1.0) -> void:
	if x < 0:
		x = rng.randf_range(65, W - 65)
	var roll := rng.randf()
	var tier := 0
	if roll < chunky_chance():
		tier = 2
	elif roll < big_chance():
		tier = 1
	var cow_size: float
	var capture_time: float
	var walk_speed: float
	match tier:
		0:
			cow_size = rng.randf_range(0.88, 1.1)
			capture_time = 0.0
			walk_speed = 25.0
		1:
			cow_size = rng.randf_range(1.25, 1.45)
			capture_time = 1.4
			walk_speed = 18.0
		2:
			cow_size = rng.randf_range(1.6, 1.85)
			capture_time = 3.0
			walk_speed = 12.0
	var color_roll := rng.randf()
	var color_type := "normal"
	if time_drain and color_roll < 0.30:
		color_type = "blue"
	elif not time_drain and color_roll < red_cow_chance():
		color_type = "red"
	elif time_drain and color_roll < red_cow_chance() + 0.30:
		color_type = "red"
	cows.append({
		"pos": Vector2(x, GROUND_Y - 16),
		"vel": Vector2(rng.randf_range(-24, 24), 0),
		"dir": -1.0 if rng.randf() < 0.5 else 1.0,
		"phase": rng.randf_range(0, TAU),
		"fear": 0.0,
		"airborne": false,
		"captured": false,
		"size": cow_size,
		"tier": tier,
		"capture_time": capture_time,
		"beam_progress": 0.0,
		"walk_speed": walk_speed,
		"color_type": color_type
	})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			if state != GameState.PLAYING:
				start_game()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and state == GameState.PLAYING:
			state = GameState.TITLE
		elif event.keycode == KEY_E and state == GameState.PLAYING:
			activate_shield()
	if event is InputEventMouseButton and event.pressed:
		if state != GameState.PLAYING:
			start_game()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			activate_shield()

func _process(delta: float) -> void:
	title_bob += delta
	for cloud in clouds:
		cloud.pos.x += cloud.speed * delta
		if cloud.pos.x > W + 140:
			cloud.pos.x = -140
	if state == GameState.PLAYING:
		update_game(delta)
	update_particles(delta)
	screen_shake = maxf(0.0, screen_shake - delta * 18.0)
	flash = maxf(0.0, flash - delta * 2.5)
	queue_redraw()

func update_game(delta: float) -> void:
	var drain := time_drain_multiplier if time_drain else 1.0
	time_left = maxf(0.0, time_left - delta * drain)
	if time_left <= 0 or lives <= 0:
		state = GameState.GAME_OVER
		beam_on = false
		return

	var input := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	).normalized()
	var target_vel := input * UFO_SPEED
	ufo_vel = ufo_vel.lerp(target_vel, 1.0 - exp(-delta * 8.0))
	ufo_pos += ufo_vel * delta
	ufo_pos.x = clampf(ufo_pos.x, 65, W - 65)
	ufo_pos.y = clampf(ufo_pos.y, 75, 350)

	beam_on = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	beam_on = beam_on and beam_energy > 0.5
	if beam_on:
		beam_energy = maxf(0, beam_energy - delta * 25.0)
	else:
		beam_energy = minf(100, beam_energy + delta * 18.0)

	spawn_timer -= delta
	var cs := cow_spawn_interval()
	if spawn_timer <= 0 and cows.size() < 10:
		spawn_cow()
		spawn_timer = rng.randf_range(cs[0], cs[1])

	for cow in cows:
		update_cow(cow, delta)

	for i in range(cows.size() - 1, -1, -1):
		if cows[i].captured:
			cows.remove_at(i)

	farmer_spawn_timer -= delta
	var fs := farmer_spawn_interval()
	if farmer_spawn_timer <= 0 and farmers.size() < max_farmers():
		spawn_farmer()
		farmer_spawn_timer = rng.randf_range(fs[0], fs[1])

	for farmer in farmers:
		update_farmer(farmer, delta)
	for i in range(farmers.size() - 1, -1, -1):
		if farmers[i].dead:
			farmers.remove_at(i)

	update_pitchforks(delta)
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	shield_time = maxf(0.0, shield_time - delta)
	level_banner_time = maxf(0.0, level_banner_time - delta)

	if level_captured >= cows_to_clear():
		level += 1
		level_captured = 0
		level_banner_time = 2.5
		time_left = minf(99.0, time_left + 10.0)
		beam_energy = 100.0
		screen_shake = 10.0
		flash = 0.5
		score += level * 500

func update_cow(cow: Dictionary, delta: float) -> void:
	cow.phase += delta * 5.0
	var offset: Vector2 = cow.pos - ufo_pos
	var in_beam: bool = beam_on and cow.pos.y > ufo_pos.y and absf(offset.x) < beam_width_at(cow.pos.y) and offset.length() < BEAM_RANGE

	if in_beam:
		cow.airborne = true
		cow.fear = minf(1.0, cow.fear + delta * 4.0)
		cow.beam_progress = minf(cow.capture_time, cow.beam_progress + delta)
		var pull_strength := 4.3 / maxf(1.0, cow.size * 0.8)
		var lift := -245.0 / maxf(1.0, cow.size * 0.6)
		var pull := Vector2((ufo_pos.x - cow.pos.x) * pull_strength, lift)
		cow.vel = cow.vel.lerp(pull, 1.0 - exp(-delta * 3.4))
		cow.vel.y -= delta * 100.0
		if rng.randf() < delta * 8.0:
			add_particle(cow.pos + Vector2(rng.randf_range(-15, 15), 10), Color("#caff70"), "spark")
	else:
		cow.fear = maxf(0.0, cow.fear - delta * 2.0)
		cow.beam_progress = maxf(0.0, cow.beam_progress - delta * 0.5)
		if cow.airborne:
			cow.vel.y += 420.0 * delta
		else:
			cow.vel.x = move_toward(cow.vel.x, cow.dir * cow.walk_speed, delta * 20.0)
			if rng.randf() < delta * 0.25:
				cow.dir *= -1.0

	cow.pos += cow.vel * delta
	if cow.pos.y >= GROUND_Y - 16:
		if cow.airborne and cow.vel.y > 170:
			for j in 5:
				add_particle(cow.pos + Vector2(rng.randf_range(-18, 18), 12), Color("#b69568"), "dust")
		cow.pos.y = GROUND_Y - 16
		cow.vel.y = 0
		cow.airborne = false
	if cow.pos.x < 35:
		cow.pos.x = 35
		cow.dir = 1.0
	if cow.pos.x > W - 35:
		cow.pos.x = W - 35
		cow.dir = -1.0

	var can_capture: bool = cow.beam_progress >= cow.capture_time
	if cow.pos.distance_to(ufo_pos) < 48 and can_capture:
		cow.captured = true
		captured += 1
		level_captured += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		var tier_bonus: int = [1, 3, 6][cow.tier]
		var points := 100 * combo * tier_bonus
		score += points
		var time_bonus: float = [2.0, 3.5, 5.0][cow.tier]
		time_left = minf(99.0, time_left + time_bonus)
		beam_energy = minf(100, beam_energy + 22)
		var shake_amount: float = [8.0, 12.0, 18.0][cow.tier]
		screen_shake = shake_amount
		flash = 0.35 + cow.tier * 0.15
		var carrot_reward: int = [1, 2, 4][cow.tier]
		var burst_color := Color("#d7ff75")
		if cow.color_type == "red":
			time_drain = true
			burst_color = Color("#ff4444")
			screen_shake = maxf(screen_shake, 14.0)
			carrot_reward = 0
		elif cow.color_type == "blue":
			time_drain = false
			burst_color = Color("#44bbff")
			score += 200
			carrot_reward += 2
		carrots += carrot_reward
		var burst_count: int = [18, 28, 40][cow.tier]
		for j in burst_count:
			add_particle(ufo_pos + Vector2(rng.randf_range(-35, 35), 15), burst_color, "burst")
	elif not in_beam and cow.airborne and cow.pos.y >= GROUND_Y - 17:
		combo = 0

func activate_shield() -> void:
	if carrots >= SHIELD_COST and shield_time <= 0:
		carrots -= SHIELD_COST
		shield_time = SHIELD_DURATION
		screen_shake = 5.0
		for j in 24:
			var angle := TAU * j / 24.0
			add_particle(ufo_pos + Vector2(cos(angle), sin(angle)) * 50, Color("#ff9933"), "burst")

func spawn_farmer() -> void:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var x := 30.0 if side > 0 else W - 30.0
	farmers.append({
		"pos": Vector2(x, GROUND_Y + 35),
		"dir": side,
		"state": "walking",
		"timer": 0.0,
		"aim_target": Vector2.ZERO,
		"dead": false,
		"phase": rng.randf_range(0, TAU)
	})

func update_farmer(farmer: Dictionary, delta: float) -> void:
	farmer.phase += delta * 4.0
	match farmer.state:
		"walking":
			farmer.pos.x += farmer.dir * 40.0 * delta
			if farmer.pos.x > 100 and farmer.pos.x < W - 100:
				if rng.randf() < delta * 0.4:
					farmer.state = "aiming"
					farmer.timer = farmer_aim_time()
					farmer.aim_target = ufo_pos
			if farmer.pos.x < 20 or farmer.pos.x > W - 20:
				farmer.dir *= -1.0
		"aiming":
			farmer.aim_target = farmer.aim_target.lerp(ufo_pos, 1.0 - exp(-delta * 2.5))
			farmer.timer -= delta
			if farmer.timer <= 0:
				farmer.state = "throwing"
				farmer.timer = 0.4
				var dir_to_ufo: Vector2 = (ufo_pos - farmer.pos).normalized()
				pitchforks.append({
					"pos": farmer.pos + Vector2(0, -20),
					"vel": dir_to_ufo * pitchfork_speed(),
					"life": 3.0,
					"rotation": dir_to_ufo.angle()
				})
		"throwing":
			farmer.timer -= delta
			if farmer.timer <= 0:
				farmer.state = "cooldown"
				farmer.timer = rng.randf_range(2.5, 5.0)
		"cooldown":
			farmer.timer -= delta
			farmer.pos.x += farmer.dir * 20.0 * delta
			if farmer.pos.x < 30:
				farmer.pos.x = 30
				farmer.dir = 1.0
			if farmer.pos.x > W - 30:
				farmer.pos.x = W - 30
				farmer.dir = -1.0
			if farmer.timer <= 0:
				farmer.state = "walking"

func update_pitchforks(delta: float) -> void:
	for fork in pitchforks:
		fork.pos += fork.vel * delta
		fork.vel.y += 120.0 * delta
		fork.rotation = fork.vel.angle()
		fork.life -= delta
		if fork.pos.distance_to(ufo_pos) < 38:
			if shield_time > 0:
				fork.vel = -fork.vel * 0.5
				fork.life = 0.5
				screen_shake = 4.0
				for j in 6:
					add_particle(ufo_pos + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10)), Color("#ff9933"), "burst")
			else:
				lives -= 1
				hit_flash = 1.0
				screen_shake = 15.0
				fork.life = 0
				for j in 12:
					add_particle(ufo_pos + Vector2(rng.randf_range(-25, 25), rng.randf_range(-10, 15)), Color("#ff5555"), "burst")
	for i in range(pitchforks.size() - 1, -1, -1):
		if pitchforks[i].life <= 0 or pitchforks[i].pos.y > H + 20 or pitchforks[i].pos.x < -20 or pitchforks[i].pos.x > W + 20:
			pitchforks.remove_at(i)

func beam_width_at(y: float) -> float:
	var t := clampf((y - ufo_pos.y) / BEAM_RANGE, 0, 1)
	return lerpf(30, 125, t)

func add_particle(pos: Vector2, color: Color, kind: String) -> void:
	var velocity := Vector2(rng.randf_range(-90, 90), rng.randf_range(-140, -25))
	if kind == "spark":
		velocity = Vector2(rng.randf_range(-25, 25), rng.randf_range(-65, -15))
	particles.append({
		"pos": pos,
		"vel": velocity,
		"life": rng.randf_range(0.35, 0.8),
		"max_life": 0.8,
		"color": color,
		"kind": kind
	})

func update_particles(delta: float) -> void:
	for p in particles:
		p.life -= delta
		p.pos += p.vel * delta
		p.vel.y += 180.0 * delta
	for i in range(particles.size() - 1, -1, -1):
		if particles[i].life <= 0:
			particles.remove_at(i)

func _draw() -> void:
	var shake := Vector2.ZERO
	if screen_shake > 0:
		shake = Vector2(rng.randf_range(-screen_shake, screen_shake), rng.randf_range(-screen_shake, screen_shake))
	draw_set_transform(shake)
	draw_background()
	for farmer in farmers:
		draw_farmer(farmer)
	for cow in cows:
		draw_cow(cow)
	if state == GameState.PLAYING and beam_on:
		draw_beam()
	draw_ufo(ufo_pos, state == GameState.TITLE)
	if shield_time > 0 and state == GameState.PLAYING:
		var shield_alpha := 0.2 + sin(title_bob * 8.0) * 0.08
		if shield_time < 1.5:
			shield_alpha *= shield_time / 1.5
		draw_arc(ufo_pos, 52, 0, TAU, 32, Color(1.0, 0.6, 0.15, shield_alpha + 0.15), 3)
		draw_circle(ufo_pos, 50, Color(1.0, 0.65, 0.2, shield_alpha * 0.5))
	for fork in pitchforks:
		draw_pitchfork(fork)
	for farmer in farmers:
		if farmer.state == "aiming":
			draw_aim_dot(farmer)
	for p in particles:
		draw_particle(p)
	draw_set_transform(Vector2.ZERO)
	if state == GameState.TITLE:
		draw_title()
	elif state == GameState.PLAYING:
		draw_hud()
	else:
		draw_game_over()
	if flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(0.8, 1.0, 0.65, flash), true)
	if hit_flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.15, 0.1, hit_flash * 0.4), true)
	if level_banner_time > 0 and state == GameState.PLAYING:
		var ba := minf(1.0, level_banner_time / 0.5) * minf(1.0, (2.5 - level_banner_time) / 0.3)
		draw_panel(Rect2(W * 0.5 - 160, 260, 320, 70), Color(0.02, 0.06, 0.14, 0.9 * ba))
		draw_centered("LEVEL %d" % level, 298, 36, Color("#e8ff77").lerp(Color.WHITE, 1.0 - ba))
		draw_centered("COWS ARE GETTING TOUGHER!", 324, 16, Color(0.8, 1.0, 0.7, ba))

func draw_background() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("#08152f"), true)
	for y in range(0, 470, 4):
		var t := float(y) / 470.0
		draw_rect(Rect2(0, y, W, 5), Color("#08152f").lerp(Color("#68456d"), t), true)
	for i in stars.size():
		var twinkle := 0.45 + sin(title_bob * 2.0 + i * 1.7) * 0.3
		draw_circle(stars[i], 2.0 if i % 7 == 0 else 1.0, Color(1, 0.95, 0.75, twinkle))
	draw_circle(Vector2(980, 108), 48, Color("#f5dfb1"))
	draw_circle(Vector2(960, 93), 44, Color("#182348"))
	for cloud in clouds:
		draw_cloud(cloud.pos, cloud.scale)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 475), Vector2(145, 370), Vector2(295, 475),
		Vector2(455, 345), Vector2(650, 475), Vector2(850, 380),
		Vector2(1030, 475), Vector2(W, 405), Vector2(W, GROUND_Y), Vector2(0, GROUND_Y)
	]), Color("#18264a"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 500), Vector2(180, 425), Vector2(370, 500),
		Vector2(610, 420), Vector2(845, 500), Vector2(1040, 440),
		Vector2(W, 485), Vector2(W, GROUND_Y + 5), Vector2(0, GROUND_Y + 5)
	]), Color("#26365a"))
	draw_rect(Rect2(0, GROUND_Y, W, H - GROUND_Y), Color("#172d2b"), true)
	draw_rect(Rect2(0, GROUND_Y, W, 8), Color("#7ca34b"), true)
	for x in range(12, 1152, 34):
		var sway := sin(title_bob * 1.7 + x) * 3
		draw_line(Vector2(x, GROUND_Y + 2), Vector2(x + sway, GROUND_Y - 10 - x % 9), Color("#a6c65d"), 2)
	draw_fence()

func draw_cloud(pos: Vector2, scale_value: float) -> void:
	var c := Color(0.68, 0.64, 0.75, 0.16)
	draw_circle(pos, 28 * scale_value, c)
	draw_circle(pos + Vector2(29, 5) * scale_value, 21 * scale_value, c)
	draw_circle(pos + Vector2(-30, 8) * scale_value, 18 * scale_value, c)
	draw_rect(Rect2(pos + Vector2(-35, 5) * scale_value, Vector2(70, 22) * scale_value), c, true)

func draw_fence() -> void:
	var c := Color("#6c4c3e")
	for x in range(45, 1152, 150):
		draw_rect(Rect2(x, GROUND_Y + 12, 8, 65), c, true)
	draw_line(Vector2(0, GROUND_Y + 30), Vector2(W, GROUND_Y + 30), c, 5)
	draw_line(Vector2(0, GROUND_Y + 60), Vector2(W, GROUND_Y + 60), c, 5)

func draw_beam() -> void:
	var end_y := minf(GROUND_Y + 8, ufo_pos.y + BEAM_RANGE)
	var width := beam_width_at(end_y)
	var poly := PackedVector2Array([
		ufo_pos + Vector2(-27, 18),
		ufo_pos + Vector2(27, 18),
		Vector2(ufo_pos.x + width, end_y),
		Vector2(ufo_pos.x - width, end_y)
	])
	draw_colored_polygon(poly, Color(0.55, 1.0, 0.45, 0.14))
	draw_polyline(PackedVector2Array([poly[0], poly[3]]), Color(0.65, 1, 0.55, 0.42), 2)
	draw_polyline(PackedVector2Array([poly[1], poly[2]]), Color(0.65, 1, 0.55, 0.42), 2)
	for i in 8:
		var y := fmod(title_bob * 160 + i * 47, end_y - ufo_pos.y - 25) + ufo_pos.y + 25
		var local_width := beam_width_at(y)
		var x := ufo_pos.x + sin(i * 4.2 + title_bob * 3) * local_width * 0.7
		draw_circle(Vector2(x, y), 2.5, Color(0.8, 1, 0.55, 0.65))

func draw_ufo(pos: Vector2, title_mode := false) -> void:
	var p := pos
	if title_mode:
		p = Vector2(W * 0.5, 224 + sin(title_bob * 2.0) * 8)
	draw_circle(p + Vector2(0, 8), 48, Color(0.04, 0.12, 0.2, 0.35))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-64, 4), p + Vector2(-42, -12), p + Vector2(42, -12),
		p + Vector2(64, 4), p + Vector2(42, 20), p + Vector2(-42, 20)
	]), Color("#9bb7b5"))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-62, 4), p + Vector2(62, 4), p + Vector2(42, 20), p + Vector2(-42, 20)
	]), Color("#405d69"))
	draw_circle(p + Vector2(0, -13), 29, Color("#8be4d1"))
	draw_arc(p + Vector2(0, -13), 29, PI, TAU, 30, Color("#d1fff2"), 3)
	draw_circle(p + Vector2(-9, -18), 6, Color(1, 1, 1, 0.28))
	for i in 5:
		var lx := -40 + i * 20
		var lc := Color("#dfff58") if (int(title_bob * 8) + i) % 2 == 0 else Color("#ffcb4f")
		draw_circle(p + Vector2(lx, 10), 4.5, lc)
	draw_line(p + Vector2(-26, 22), p + Vector2(26, 22), Color("#c9ff6a"), 4)

func draw_cow(cow: Dictionary) -> void:
	var p: Vector2 = cow.pos
	var s: float = cow.size
	var angle := clampf(cow.vel.x / 500.0, -0.35, 0.35)
	if cow.airborne:
		angle += sin(cow.phase) * 0.12
	if cow.color_type == "red":
		var glow_alpha := 0.2 + sin(cow.phase * 0.8) * 0.1
		draw_circle(p, 28 * s, Color(1.0, 0.2, 0.15, glow_alpha))
	elif cow.color_type == "blue":
		var glow_alpha := 0.2 + sin(cow.phase * 0.8) * 0.1
		draw_circle(p, 28 * s, Color(0.15, 0.5, 1.0, glow_alpha))
	draw_set_transform(p, angle, Vector2(s, s))
	var body: Color
	var dark := Color("#252733")
	var spot_color: Color
	match cow.tier:
		0:
			body = Color("#f4eee2")
			spot_color = dark
		1:
			body = Color("#f0e6d0")
			spot_color = Color("#6b4226")
		2:
			body = Color("#e8dcc8")
			spot_color = Color("#8b5a2b")
	if cow.color_type == "red":
		body = Color("#f2b0a8")
		spot_color = Color("#8b1a1a")
		dark = Color("#5c1010")
	elif cow.color_type == "blue":
		body = Color("#a8cef2")
		spot_color = Color("#1a3d8b")
		dark = Color("#10205c")
	draw_custom_ellipse(Vector2.ZERO, Vector2(27, 16), body)
	if cow.tier >= 1:
		draw_custom_ellipse(Vector2(-5, 2), Vector2(8, 5), spot_color)
	if cow.tier == 2:
		draw_custom_ellipse(Vector2(8, -2), Vector2(6, 4), spot_color)
		draw_custom_ellipse(Vector2(-14, -3), Vector2(5, 4), spot_color)
	draw_circle(Vector2(25, -5), 12, body)
	draw_circle(Vector2(31, -4), 5, Color("#e7b7a8"))
	draw_colored_polygon(PackedVector2Array([Vector2(17, -14), Vector2(12, -24), Vector2(22, -17)]), dark)
	draw_colored_polygon(PackedVector2Array([Vector2(31, -14), Vector2(38, -23), Vector2(37, -12)]), dark)
	draw_custom_ellipse(Vector2(-10, -5), Vector2(9, 7), dark)
	draw_custom_ellipse(Vector2(9, 7), Vector2(7, 6), dark)
	var leg_thickness: int = [5, 6, 8][cow.tier]
	var leg_kick := sin(cow.phase) * (7 if cow.airborne else 2)
	draw_line(Vector2(-15, 12), Vector2(-16 + leg_kick, 27), dark, leg_thickness)
	draw_line(Vector2(13, 12), Vector2(14 - leg_kick, 27), dark, leg_thickness)
	draw_line(Vector2(-26, -4), Vector2(-34, -14 + sin(cow.phase) * 4), dark, 3)
	draw_circle(Vector2(28, -8), 2.3, Color("#10151d"))
	if cow.fear > 0.2:
		draw_circle(Vector2(28, -8), 5, Color.WHITE, false, 1.5)
	if cow.capture_time > 0 and cow.beam_progress > 0:
		draw_set_transform(p, 0, Vector2.ONE)
		var bar_w := 30.0 * s
		var bar_h := 5.0
		var bar_pos := Vector2(-bar_w * 0.5, -28 * s)
		var progress: float = cow.beam_progress / cow.capture_time
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.5), true)
		var fill_color := Color("#ff6b69").lerp(Color("#caff63"), progress)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * progress, bar_h)), fill_color, true)
	draw_set_transform(Vector2.ZERO)

func draw_farmer(farmer: Dictionary) -> void:
	var p: Vector2 = farmer.pos
	var skin := Color("#e8b88a")
	var overalls := Color("#4a6fa5")
	var hat := Color("#c4956a")
	var dark := Color("#2a2020")
	var bob := sin(farmer.phase) * 2.0 if farmer.state == "walking" else 0.0
	draw_rect(Rect2(p.x - 8, p.y - 42 + bob, 16, 24), overalls, true)
	draw_rect(Rect2(p.x - 6, p.y - 50 + bob, 12, 12), skin, true)
	draw_rect(Rect2(p.x - 10, p.y - 54 + bob, 20, 6), hat, true)
	draw_rect(Rect2(p.x - 7, p.y - 56 + bob, 14, 4), hat, true)
	var leg_kick := sin(farmer.phase * 1.2) * 4.0 if farmer.state == "walking" else 0.0
	draw_line(Vector2(p.x - 4, p.y - 18 + bob), Vector2(p.x - 5 + leg_kick, p.y), dark, 4)
	draw_line(Vector2(p.x + 4, p.y - 18 + bob), Vector2(p.x + 5 - leg_kick, p.y), dark, 4)
	if farmer.state == "aiming":
		var arm_dir: Vector2 = (farmer.aim_target - p).normalized()
		draw_line(Vector2(p.x, p.y - 36 + bob), Vector2(p.x + arm_dir.x * 18, p.y - 36 + bob + arm_dir.y * 18), dark, 3)
	else:
		draw_line(Vector2(p.x - 8, p.y - 38 + bob), Vector2(p.x - 14, p.y - 28 + bob), dark, 3)
		draw_line(Vector2(p.x + 8, p.y - 38 + bob), Vector2(p.x + 14, p.y - 28 + bob), dark, 3)
	draw_circle(Vector2(p.x - 3, p.y - 46 + bob), 1.5, dark)
	draw_circle(Vector2(p.x + 3, p.y - 46 + bob), 1.5, dark)

func draw_aim_dot(farmer: Dictionary) -> void:
	var pulse := 0.5 + sin(title_bob * 12.0) * 0.5
	var target: Vector2 = farmer.aim_target
	draw_circle(target, 6.0, Color(1.0, 0.1, 0.1, 0.25 * pulse))
	draw_circle(target, 3.0, Color(1.0, 0.15, 0.1, 0.7 * pulse))
	draw_line(farmer.pos + Vector2(0, -36), target, Color(1.0, 0.1, 0.05, 0.15 * pulse), 1.5)

func draw_pitchfork(fork: Dictionary) -> void:
	var p: Vector2 = fork.pos
	var r: float = fork.rotation
	var dir := Vector2.from_angle(r)
	var perp := Vector2(-dir.y, dir.x)
	var handle_end := p - dir * 22
	draw_line(p, handle_end, Color("#8b6914"), 3)
	draw_line(p + dir * 2, p + dir * 10, Color("#c0c0c0"), 2.5)
	draw_line(p + dir * 10 + perp * 5, p + dir * 14 + perp * 5, Color("#c0c0c0"), 2)
	draw_line(p + dir * 10 - perp * 5, p + dir * 14 - perp * 5, Color("#c0c0c0"), 2)

func draw_carrot_icon(pos: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-3, 2) * s, pos + Vector2(0, -10) * s,
		pos + Vector2(3, 2) * s, pos + Vector2(0, 12) * s
	]), Color("#ff8822"))
	draw_line(pos + Vector2(0, -10) * s, pos + Vector2(-4, -16) * s, Color("#55aa33"), 2)
	draw_line(pos + Vector2(0, -10) * s, pos + Vector2(3, -15) * s, Color("#55aa33"), 2)

func draw_custom_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)

func draw_particle(p: Dictionary) -> void:
	var alpha: float = clampf(p.life / p.max_life, 0, 1)
	var radius := 3.0 if p.kind == "dust" else 4.0
	draw_circle(p.pos, radius * alpha + 1, Color(p.color, alpha))

func draw_title() -> void:
	draw_panel(Rect2(286, 75, 580, 470), Color(0.025, 0.07, 0.14, 0.78))
	draw_centered("UDDER SPACE", 132, 54, Color("#e8ff77"))
	draw_centered("A CLOSE ENCOUNTER OF THE HERD KIND", 184, 18, Color("#9ce8d5"))
	draw_centered("ABDUCT AS MANY COWS AS YOU CAN", 342, 22, Color.WHITE)
	draw_centered("ARROW KEYS / WASD  •  MOVE", 392, 18, Color("#b8c8cf"))
	draw_centered("HOLD SPACE OR LEFT CLICK  •  TRACTOR BEAM", 426, 18, Color("#b8c8cf"))
	draw_centered("E OR RIGHT CLICK  •  CARROT SHIELD (5)", 456, 18, Color("#ffaa44"))
	var pulse := 0.78 + sin(title_bob * 4) * 0.22
	draw_centered("PRESS SPACE TO INVADE", 500, 24, Color(0.9, 1, 0.45, pulse))

func draw_hud() -> void:
	draw_panel(Rect2(25, 22, 380, 100), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "COWS  %02d" % captured, 21, Color("#dffb78"))
	draw_text(Vector2(190, 52), "SCORE  %06d" % score, 21, Color.WHITE)
	draw_text(Vector2(45, 80), "COMBO  x%d" % maxi(1, combo), 17, Color("#8fe8d1"))
	for i in 3:
		var heart_x := 330.0 + i * 22.0
		var heart_color := Color("#ff4466") if i < lives else Color("#30303a")
		draw_circle(Vector2(heart_x, 80), 7, heart_color)
	draw_carrot_icon(Vector2(52, 103), 0.7)
	var carrot_color := Color("#ff9933") if carrots >= SHIELD_COST else Color("#9eb4c0")
	draw_text(Vector2(66, 110), "%d" % carrots, 17, carrot_color)
	if shield_time > 0:
		draw_text(Vector2(110, 110), "SHIELD  %.1fs" % shield_time, 15, Color("#ffaa33"))
	elif carrots >= SHIELD_COST:
		var hint_pulse := 0.5 + sin(title_bob * 4.0) * 0.3
		draw_text(Vector2(110, 110), "[E] SHIELD", 15, Color(1.0, 0.65, 0.2, hint_pulse))
	draw_panel(Rect2(W - 260, 22, 235, 100), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 240, 52), "TIME", 18, Color("#9eb4c0"))
	var time_color := Color("#ff6b69") if time_left < 10 else Color.WHITE
	draw_text(Vector2(W - 158, 56), "%02d" % ceili(time_left), 34, time_color)
	draw_text(Vector2(W - 240, 81), "BEAM", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 180, 69, 125, 12), Color("#20313b"), true)
	draw_rect(Rect2(W - 178, 71, 121 * beam_energy / 100.0, 8), Color("#caff63"), true)
	draw_text(Vector2(W - 240, 102), "LVL %d" % level, 17, Color("#e8ff77"))
	var lvl_progress := float(level_captured) / float(cows_to_clear())
	draw_rect(Rect2(W - 180, 107, 125, 8), Color("#20313b"), true)
	draw_rect(Rect2(W - 178, 108, 121 * lvl_progress, 6), Color("#9ce8d5"), true)
	if time_drain:
		var warn_pulse := 0.6 + sin(title_bob * 6.0) * 0.4
		draw_panel(Rect2(W * 0.5 - 120, 100, 240, 34), Color(0.4, 0.05, 0.05, 0.85))
		draw_centered("TIME DRAIN!  GET A BLUE COW", 124, 16, Color(1.0, 0.35, 0.35, warn_pulse))

func draw_game_over() -> void:
	draw_panel(Rect2(326, 104, 500, 425), Color(0.025, 0.07, 0.14, 0.9))
	draw_centered("MISSION COMPLETE", 155, 38, Color("#e8ff77"))
	draw_centered("LEVEL %d REACHED" % level, 192, 20, Color("#9ce8d5"))
	draw_centered("%d" % captured, 306, 72, Color.WHITE)
	draw_centered("COWS LIBERATED", 342, 17, Color("#9eb4c0"))
	draw_centered("SCORE  %06d" % score, 397, 25, Color("#e8ff77"))
	draw_centered("BEST COMBO  x%d" % best_combo, 432, 18, Color("#9ce8d5"))
	draw_centered("CARROTS  %d" % carrots, 460, 18, Color("#ffaa44"))
	draw_centered("PRESS SPACE TO RAID AGAIN", 495, 21, Color.WHITE)

func draw_panel(rect: Rect2, color: Color) -> void:
	draw_custom_box(rect, color, Color(0.55, 0.9, 0.75, 0.35))

func draw_custom_box(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 2)
	draw_line(rect.position + Vector2(18, 0), rect.position + Vector2(rect.size.x - 18, 0), Color("#dfff70"), 2)

func draw_centered(text: String, y: float, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2((W - width) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func draw_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
