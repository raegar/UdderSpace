extends Node2D

const W := 1152.0
const H := 648.0
const GROUND_Y := 535.0
const UFO_SPEED := 430.0
const BEAM_RANGE := 365.0

enum GameState { TITLE, PLAYING, BOSS_FIGHT, BOSS2_FIGHT, VICTORY, GAME_OVER }

const BOSS_SCORE_TRIGGER := 5000
const BOSS_MAX_HP := 10000
const LASER_DAMAGE := 100
const UFO_MAX_HP := 1000
const BOSS_DAMAGE := 100
const LASER_SPEED := 800.0

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
var rng := RandomNumberGenerator.new()

var laser_charges := 0
var lasers: Array[Dictionary] = []
var boss_hp := BOSS_MAX_HP
var boss_pos := Vector2(W * 0.5, -200.0)
var boss_phase := 0.0
var boss_attack_timer := 0.0
var boss_projectiles: Array[Dictionary] = []
var boss_hit_flash := 0.0
var boss_entered := false
var boss_tentacle_phase := 0.0
var boss_eye_anger := 0.0
var ufo_hp := UFO_MAX_HP
var boss2_hp := BOSS_MAX_HP
var boss2_pos := Vector2(W * 0.5, -200.0)
var boss2_phase := 0.0
var boss2_attack_timer := 0.0
var boss2_hit_flash := 0.0
var boss2_entered := false
var boss2_spin := 0.0
var mini_aliens: Array[Dictionary] = []

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
	score = 0
	combo = 0
	best_combo = 0
	captured = 0
	time_left = 60.0
	beam_energy = 100.0
	spawn_timer = 0.0
	laser_charges = 0
	lasers.clear()
	boss_hp = BOSS_MAX_HP
	boss_pos = Vector2(W * 0.5, -200.0)
	boss_phase = 0.0
	boss_attack_timer = 0.0
	boss_projectiles.clear()
	boss_hit_flash = 0.0
	boss_entered = false
	boss_tentacle_phase = 0.0
	boss_eye_anger = 0.0
	ufo_hp = UFO_MAX_HP
	boss2_hp = BOSS_MAX_HP
	boss2_pos = Vector2(W * 0.5, -200.0)
	boss2_phase = 0.0
	boss2_attack_timer = 0.0
	boss2_hit_flash = 0.0
	boss2_entered = false
	boss2_spin = 0.0
	mini_aliens.clear()
	for i in 8:
		spawn_cow(90.0 + i * 135.0 + rng.randf_range(-30, 30))

func spawn_cow(x := -1.0) -> void:
	if x < 0:
		x = rng.randf_range(65, W - 65)
	cows.append({
		"pos": Vector2(x, GROUND_Y - 16),
		"vel": Vector2(rng.randf_range(-24, 24), 0),
		"dir": -1.0 if rng.randf() < 0.5 else 1.0,
		"phase": rng.randf_range(0, TAU),
		"fear": 0.0,
		"airborne": false,
		"captured": false,
		"size": rng.randf_range(0.88, 1.1)
	})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			if state == GameState.TITLE or state == GameState.GAME_OVER or state == GameState.VICTORY:
				start_game()
				get_viewport().set_input_as_handled()
			elif state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT:
				fire_laser()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if state == GameState.PLAYING or state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT:
				state = GameState.TITLE
	if event is InputEventMouseButton and event.pressed:
		if state == GameState.TITLE or state == GameState.GAME_OVER or state == GameState.VICTORY:
			start_game()
		elif state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT:
			fire_laser()

func _process(delta: float) -> void:
	title_bob += delta
	for cloud in clouds:
		cloud.pos.x += cloud.speed * delta
		if cloud.pos.x > W + 140:
			cloud.pos.x = -140
	if state == GameState.PLAYING:
		update_game(delta)
	elif state == GameState.BOSS_FIGHT:
		update_boss_fight(delta)
	elif state == GameState.BOSS2_FIGHT:
		update_boss2_fight(delta)
	update_particles(delta)
	screen_shake = maxf(0.0, screen_shake - delta * 18.0)
	flash = maxf(0.0, flash - delta * 2.5)
	queue_redraw()

func update_game(delta: float) -> void:
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0:
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
	if spawn_timer <= 0 and cows.size() < 10:
		spawn_cow()
		spawn_timer = rng.randf_range(0.8, 1.8)

	for cow in cows:
		update_cow(cow, delta)

	for i in range(cows.size() - 1, -1, -1):
		if cows[i].captured:
			cows.remove_at(i)

func update_cow(cow: Dictionary, delta: float) -> void:
	cow.phase += delta * 5.0
	var offset: Vector2 = cow.pos - ufo_pos
	var in_beam: bool = beam_on and cow.pos.y > ufo_pos.y and absf(offset.x) < beam_width_at(cow.pos.y) and offset.length() < BEAM_RANGE

	if in_beam:
		cow.airborne = true
		cow.fear = minf(1.0, cow.fear + delta * 4.0)
		var pull := Vector2((ufo_pos.x - cow.pos.x) * 4.3, -245.0)
		cow.vel = cow.vel.lerp(pull, 1.0 - exp(-delta * 3.4))
		cow.vel.y -= delta * 100.0
		if rng.randf() < delta * 8.0:
			add_particle(cow.pos + Vector2(rng.randf_range(-15, 15), 10), Color("#caff70"), "spark")
	else:
		cow.fear = maxf(0.0, cow.fear - delta * 2.0)
		if cow.airborne:
			cow.vel.y += 420.0 * delta
		else:
			cow.vel.x = move_toward(cow.vel.x, cow.dir * 65.0, delta * 40.0)
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

	if cow.pos.distance_to(ufo_pos) < 48:
		cow.captured = true
		captured += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		var points := 100 * combo
		score += points
		laser_charges += 1
		time_left = minf(99.0, time_left + 2.0)
		beam_energy = minf(100, beam_energy + 22)
		screen_shake = 8.0
		flash = 0.35
		for j in 18:
			add_particle(ufo_pos + Vector2(rng.randf_range(-35, 35), 15), Color("#d7ff75"), "burst")
		if score >= BOSS_SCORE_TRIGGER and state == GameState.PLAYING:
			enter_boss_fight()
	elif not in_beam and cow.airborne and cow.pos.y >= GROUND_Y - 17:
		combo = 0

func enter_boss_fight() -> void:
	state = GameState.BOSS_FIGHT
	beam_on = false
	boss_hp = BOSS_MAX_HP
	boss_pos = Vector2(W * 0.5, -200.0)
	boss_entered = false
	boss_attack_timer = 2.5
	boss_projectiles.clear()
	lasers.clear()
	boss_phase = 0.0
	boss_tentacle_phase = 0.0
	boss_eye_anger = 0.0

func update_boss_fight(delta: float) -> void:
	boss_phase += delta
	boss_tentacle_phase += delta * 2.5
	boss_hit_flash = maxf(0.0, boss_hit_flash - delta * 5.0)

	var input := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	).normalized()
	ufo_vel = ufo_vel.lerp(input * UFO_SPEED, 1.0 - exp(-delta * 8.0))
	ufo_pos += ufo_vel * delta
	ufo_pos.x = clampf(ufo_pos.x, 65, W - 65)
	ufo_pos.y = clampf(ufo_pos.y, 75, H - 80)

	beam_on = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	beam_on = beam_on and beam_energy > 0.5
	if beam_on:
		beam_energy = maxf(0, beam_energy - delta * 25.0)
	else:
		beam_energy = minf(100, beam_energy + delta * 18.0)

	spawn_timer -= delta
	if spawn_timer <= 0 and cows.size() < 6:
		spawn_cow()
		spawn_timer = rng.randf_range(2.0, 4.0)

	for cow in cows:
		update_boss_cow(cow, delta)
	for i in range(cows.size() - 1, -1, -1):
		if cows[i].captured:
			cows.remove_at(i)

	if not boss_entered:
		boss_pos.y = move_toward(boss_pos.y, 140.0, delta * 120.0)
		if boss_pos.y >= 140.0:
			boss_entered = true
			screen_shake = 12.0
		return

	if boss_hp > 0:
		boss_pos.x = W * 0.5 + sin(boss_phase * 0.7) * 280.0
		boss_pos.y = 140.0 + sin(boss_phase * 1.1) * 40.0
		boss_eye_anger = clampf(1.0 - float(boss_hp) / BOSS_MAX_HP, 0.0, 1.0)

		boss_attack_timer -= delta
		if boss_attack_timer <= 0:
			boss_attack_timer = maxf(0.3, 1.0 - boss_eye_anger * 0.5)
			var proj_speed := 380.0
			var predicted := predict_target(boss_pos, ufo_pos, ufo_vel, proj_speed)
			var aim: Vector2 = (predicted - boss_pos).normalized()
			boss_projectiles.append({"pos": boss_pos + Vector2(0, 60), "vel": aim * proj_speed, "life": 4.0})
			if boss_eye_anger > 0.5:
				var spread := aim.rotated(0.2)
				boss_projectiles.append({"pos": boss_pos + Vector2(0, 60), "vel": spread * proj_speed, "life": 4.0})
				spread = aim.rotated(-0.2)
				boss_projectiles.append({"pos": boss_pos + Vector2(0, 60), "vel": spread * proj_speed, "life": 4.0})

	for ma in mini_aliens:
		ma.phase += delta
		var ma_target := ufo_pos + Vector2(sin(ma.phase * 2 + ma.id) * 60, cos(ma.phase * 1.5 + ma.id) * 40)
		var ma_dir: Vector2 = (ma_target - ma.pos).normalized()
		ma.vel = ma.vel.lerp(ma_dir * 180.0, 1.0 - exp(-delta * 2.0))
		ma.pos += ma.vel * delta
		ma.pos.x = clampf(ma.pos.x, 40, W - 40)
		ma.pos.y = clampf(ma.pos.y, 60, H - 60)
		ma.attack_timer -= delta
		if ma.attack_timer <= 0:
			ma.attack_timer = rng.randf_range(1.2, 2.5)
			var proj_speed := 350.0
			var predicted := predict_target(ma.pos, ufo_pos, ufo_vel, proj_speed)
			var aim: Vector2 = (predicted - ma.pos).normalized()
			boss_projectiles.append({"pos": ma.pos, "vel": aim * proj_speed, "life": 3.5})

	for proj in boss_projectiles:
		proj.pos += proj.vel * delta
		proj.life -= delta
		if proj.pos.distance_to(ufo_pos) < 38:
			proj.life = 0
			screen_shake = 10.0
			flash = 0.3
			ufo_hp -= BOSS_DAMAGE
			for j in 10:
				add_particle(ufo_pos + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10)), Color("#ff5544"), "burst")
			if ufo_hp <= 0:
				state = GameState.GAME_OVER
				screen_shake = 20.0
				flash = 0.8
				return

	for i in range(boss_projectiles.size() - 1, -1, -1):
		if boss_projectiles[i].life <= 0 or boss_projectiles[i].pos.x < -50 or boss_projectiles[i].pos.x > W + 50 or boss_projectiles[i].pos.y > H + 50:
			boss_projectiles.remove_at(i)

	for laser in lasers:
		laser.pos += laser.vel * delta
		laser.life -= delta
		if boss_hp > 0 and laser.pos.distance_to(boss_pos) < 75:
			laser.life = 0
			boss_hp -= LASER_DAMAGE
			boss_hit_flash = 1.0
			screen_shake = 6.0
			score += 500
			for j in 12:
				add_particle(boss_pos + Vector2(rng.randf_range(-40, 40), rng.randf_range(-30, 30)), Color("#ff77ff"), "burst")
			if boss_hp <= 0:
				screen_shake = 20.0
				flash = 0.8
				for j in 50:
					add_particle(boss_pos + Vector2(rng.randf_range(-80, 80), rng.randf_range(-60, 60)), Color("#ffaa00"), "burst")
				for j in 50:
					add_particle(boss_pos + Vector2(rng.randf_range(-100, 100), rng.randf_range(-80, 80)), Color("#ff5500"), "burst")
				spawn_mini_aliens()
		else:
			for ma in mini_aliens:
				if laser.life > 0 and laser.pos.distance_to(ma.pos) < 30:
					laser.life = 0
					ma.hp -= 10
					screen_shake = 4.0
					score += 200
					for j in 8:
						add_particle(ma.pos + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)), Color("#ff77ff"), "burst")

	for i in range(mini_aliens.size() - 1, -1, -1):
		if mini_aliens[i].hp <= 0:
			var dead_pos: Vector2 = mini_aliens[i].pos
			for j in 20:
				add_particle(dead_pos + Vector2(rng.randf_range(-25, 25), rng.randf_range(-25, 25)), Color("#ffaa00"), "burst")
			mini_aliens.remove_at(i)

	if boss_hp <= 0 and mini_aliens.is_empty():
		enter_boss2_fight()

	for i in range(lasers.size() - 1, -1, -1):
		if lasers[i].life <= 0 or lasers[i].pos.y < -50:
			lasers.remove_at(i)

func update_boss_cow(cow: Dictionary, delta: float) -> void:
	cow.phase += delta * 5.0
	var offset: Vector2 = cow.pos - ufo_pos
	var in_beam: bool = beam_on and cow.pos.y > ufo_pos.y and absf(offset.x) < beam_width_at(cow.pos.y) and offset.length() < BEAM_RANGE

	if in_beam:
		cow.airborne = true
		cow.fear = minf(1.0, cow.fear + delta * 4.0)
		var pull := Vector2((ufo_pos.x - cow.pos.x) * 4.3, -245.0)
		cow.vel = cow.vel.lerp(pull, 1.0 - exp(-delta * 3.4))
		cow.vel.y -= delta * 100.0
		if rng.randf() < delta * 8.0:
			add_particle(cow.pos + Vector2(rng.randf_range(-15, 15), 10), Color("#caff70"), "spark")
	else:
		cow.fear = maxf(0.0, cow.fear - delta * 2.0)
		if cow.airborne:
			cow.vel.y += 420.0 * delta
		else:
			cow.vel.x = move_toward(cow.vel.x, cow.dir * 65.0, delta * 40.0)
			if rng.randf() < delta * 0.25:
				cow.dir *= -1.0

	cow.pos += cow.vel * delta
	if cow.pos.y >= GROUND_Y - 16:
		cow.pos.y = GROUND_Y - 16
		cow.vel.y = 0
		cow.airborne = false
	if cow.pos.x < 35:
		cow.pos.x = 35
		cow.dir = 1.0
	if cow.pos.x > W - 35:
		cow.pos.x = W - 35
		cow.dir = -1.0

	if cow.pos.distance_to(ufo_pos) < 48:
		cow.captured = true
		captured += 1
		ufo_hp = mini(UFO_MAX_HP, ufo_hp + 150)
		score += 100
		screen_shake = 5.0
		flash = 0.2
		for j in 12:
			add_particle(ufo_pos + Vector2(rng.randf_range(-25, 25), 10), Color("#44ff88"), "burst")

func fire_laser() -> void:
	var target := boss2_pos
	if state == GameState.BOSS_FIGHT:
		if boss_hp > 0:
			target = boss_pos
		elif not mini_aliens.is_empty():
			var closest_dist := 99999.0
			for ma in mini_aliens:
				var d: float = ufo_pos.distance_to(ma.pos)
				if d < closest_dist:
					closest_dist = d
					target = ma.pos
	var aim: Vector2 = (target - ufo_pos).normalized()
	lasers.append({"pos": ufo_pos + Vector2(0, -20), "vel": aim * LASER_SPEED, "life": 3.0})
	for j in 6:
		add_particle(ufo_pos + Vector2(rng.randf_range(-10, 10), -15), Color("#77ffaa"), "spark")

func predict_target(from: Vector2, target_pos: Vector2, target_vel: Vector2, proj_speed: float) -> Vector2:
	var dist := from.distance_to(target_pos)
	var time_to_hit := dist / proj_speed
	return target_pos + target_vel * time_to_hit

func spawn_mini_aliens() -> void:
	for i in 5:
		var angle := TAU * i / 5.0
		mini_aliens.append({
			"pos": boss_pos + Vector2(cos(angle) * 60, sin(angle) * 40),
			"vel": Vector2(cos(angle) * 100, sin(angle) * 80),
			"hp": 100,
			"phase": rng.randf_range(0, TAU),
			"id": i,
			"attack_timer": rng.randf_range(0.5, 2.0)
		})

func enter_boss2_fight() -> void:
	state = GameState.BOSS2_FIGHT
	boss_projectiles.clear()
	lasers.clear()
	boss2_hp = BOSS_MAX_HP
	boss2_pos = Vector2(W * 0.5, -200.0)
	boss2_entered = false
	boss2_attack_timer = 2.0
	boss2_phase = 0.0
	boss2_spin = 0.0
	boss2_hit_flash = 0.0

func update_boss2_fight(delta: float) -> void:
	boss2_phase += delta
	boss2_spin += delta * 3.0
	boss2_hit_flash = maxf(0.0, boss2_hit_flash - delta * 5.0)

	var input := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	).normalized()
	ufo_vel = ufo_vel.lerp(input * UFO_SPEED, 1.0 - exp(-delta * 8.0))
	ufo_pos += ufo_vel * delta
	ufo_pos.x = clampf(ufo_pos.x, 65, W - 65)
	ufo_pos.y = clampf(ufo_pos.y, 75, H - 80)

	beam_on = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	beam_on = beam_on and beam_energy > 0.5
	if beam_on:
		beam_energy = maxf(0, beam_energy - delta * 25.0)
	else:
		beam_energy = minf(100, beam_energy + delta * 18.0)

	spawn_timer -= delta
	if spawn_timer <= 0 and cows.size() < 6:
		spawn_cow()
		spawn_timer = rng.randf_range(1.5, 3.0)

	for cow in cows:
		update_boss_cow(cow, delta)
	for i in range(cows.size() - 1, -1, -1):
		if cows[i].captured:
			cows.remove_at(i)

	if not boss2_entered:
		boss2_pos.y = move_toward(boss2_pos.y, 130.0, delta * 100.0)
		if boss2_pos.y >= 130.0:
			boss2_entered = true
			screen_shake = 15.0
		return

	var anger := clampf(1.0 - float(boss2_hp) / BOSS_MAX_HP, 0.0, 1.0)
	boss2_pos.x = W * 0.5 + sin(boss2_phase * 0.9) * 300.0 + cos(boss2_phase * 1.7) * 100.0
	boss2_pos.y = 130.0 + sin(boss2_phase * 1.3) * 50.0 + cos(boss2_phase * 0.6) * 20.0

	boss2_attack_timer -= delta
	if boss2_attack_timer <= 0:
		boss2_attack_timer = maxf(0.25, 0.8 - anger * 0.4)
		var proj_speed := 420.0
		var predicted := predict_target(boss2_pos, ufo_pos, ufo_vel, proj_speed)
		var aim: Vector2 = (predicted - boss2_pos).normalized()
		boss_projectiles.append({"pos": boss2_pos + Vector2(0, 50), "vel": aim * proj_speed, "life": 4.0})
		if anger > 0.3:
			boss_projectiles.append({"pos": boss2_pos + Vector2(40, 30), "vel": aim.rotated(0.15) * proj_speed, "life": 4.0})
			boss_projectiles.append({"pos": boss2_pos + Vector2(-40, 30), "vel": aim.rotated(-0.15) * proj_speed, "life": 4.0})
		if anger > 0.7:
			boss_projectiles.append({"pos": boss2_pos + Vector2(0, 50), "vel": aim.rotated(0.35) * (proj_speed * 0.9), "life": 4.0})
			boss_projectiles.append({"pos": boss2_pos + Vector2(0, 50), "vel": aim.rotated(-0.35) * (proj_speed * 0.9), "life": 4.0})

	for proj in boss_projectiles:
		proj.pos += proj.vel * delta
		proj.life -= delta
		if proj.pos.distance_to(ufo_pos) < 38:
			proj.life = 0
			screen_shake = 10.0
			flash = 0.3
			ufo_hp -= BOSS_DAMAGE
			for j in 10:
				add_particle(ufo_pos + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10)), Color("#ff5544"), "burst")
			if ufo_hp <= 0:
				state = GameState.GAME_OVER
				screen_shake = 20.0
				flash = 0.8
				return

	for i in range(boss_projectiles.size() - 1, -1, -1):
		if boss_projectiles[i].life <= 0 or boss_projectiles[i].pos.x < -50 or boss_projectiles[i].pos.x > W + 50 or boss_projectiles[i].pos.y > H + 50:
			boss_projectiles.remove_at(i)

	for laser in lasers:
		laser.pos += laser.vel * delta
		laser.life -= delta
		if laser.pos.distance_to(boss2_pos) < 80:
			laser.life = 0
			boss2_hp -= LASER_DAMAGE
			boss2_hit_flash = 1.0
			screen_shake = 6.0
			score += 500
			for j in 12:
				add_particle(boss2_pos + Vector2(rng.randf_range(-50, 50), rng.randf_range(-30, 30)), Color("#77aaff"), "burst")
			if boss2_hp <= 0:
				state = GameState.VICTORY
				screen_shake = 25.0
				flash = 1.0
				for j in 60:
					add_particle(boss2_pos + Vector2(rng.randf_range(-100, 100), rng.randf_range(-70, 70)), Color("#ffaa00"), "burst")
				for j in 60:
					add_particle(boss2_pos + Vector2(rng.randf_range(-120, 120), rng.randf_range(-90, 90)), Color("#4488ff"), "burst")

	for i in range(lasers.size() - 1, -1, -1):
		if lasers[i].life <= 0 or lasers[i].pos.y < -50:
			lasers.remove_at(i)

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
	if state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT or state == GameState.VICTORY:
		if state == GameState.BOSS_FIGHT:
			if boss_hp > 0:
				draw_boss()
			for ma in mini_aliens:
				draw_mini_alien(ma)
		elif state == GameState.BOSS2_FIGHT:
			draw_boss2()
		for proj in boss_projectiles:
			draw_boss_projectile(proj)
		for laser in lasers:
			draw_laser(laser)
	for cow in cows:
		draw_cow(cow)
	if (state == GameState.PLAYING or state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT) and beam_on:
		draw_beam()
	draw_ufo(ufo_pos, state == GameState.TITLE)
	for p in particles:
		draw_particle(p)
	draw_set_transform(Vector2.ZERO)
	if state == GameState.TITLE:
		draw_title()
	elif state == GameState.PLAYING:
		draw_hud()
	elif state == GameState.BOSS_FIGHT:
		draw_boss_hud()
	elif state == GameState.BOSS2_FIGHT:
		draw_boss2_hud()
	elif state == GameState.VICTORY:
		draw_victory()
	else:
		draw_game_over()
	if flash > 0:
		var flash_color := Color(1.0, 0.3, 0.2, flash) if (state == GameState.BOSS_FIGHT or state == GameState.BOSS2_FIGHT) else Color(0.8, 1.0, 0.65, flash)
		draw_rect(Rect2(0, 0, W, H), flash_color, true)

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
	draw_set_transform(p, angle, Vector2(s, s))
	var body := Color("#f4eee2")
	var dark := Color("#252733")
	draw_custom_ellipse(Vector2.ZERO, Vector2(27, 16), body)
	draw_circle(Vector2(25, -5), 12, body)
	draw_circle(Vector2(31, -4), 5, Color("#e7b7a8"))
	draw_colored_polygon(PackedVector2Array([Vector2(17, -14), Vector2(12, -24), Vector2(22, -17)]), dark)
	draw_colored_polygon(PackedVector2Array([Vector2(31, -14), Vector2(38, -23), Vector2(37, -12)]), dark)
	draw_custom_ellipse(Vector2(-10, -5), Vector2(9, 7), dark)
	draw_custom_ellipse(Vector2(9, 7), Vector2(7, 6), dark)
	var leg_kick := sin(cow.phase) * (7 if cow.airborne else 2)
	draw_line(Vector2(-15, 12), Vector2(-16 + leg_kick, 27), dark, 5)
	draw_line(Vector2(13, 12), Vector2(14 - leg_kick, 27), dark, 5)
	draw_line(Vector2(-26, -4), Vector2(-34, -14 + sin(cow.phase) * 4), dark, 3)
	draw_circle(Vector2(28, -8), 2.3, Color("#10151d"))
	if cow.fear > 0.2:
		draw_circle(Vector2(28, -8), 5, Color.WHITE, false, 1.5)
	draw_set_transform(Vector2.ZERO)

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
	var pulse := 0.78 + sin(title_bob * 4) * 0.22
	draw_centered("PRESS SPACE TO INVADE", 490, 24, Color(0.9, 1, 0.45, pulse))

func draw_hud() -> void:
	draw_panel(Rect2(25, 22, 315, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "COWS  %02d" % captured, 21, Color("#dffb78"))
	draw_text(Vector2(190, 52), "SCORE  %06d" % score, 21, Color.WHITE)
	draw_text(Vector2(45, 80), "COMBO  x%d" % maxi(1, combo), 17, Color("#8fe8d1"))
	draw_panel(Rect2(W - 260, 22, 235, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 240, 52), "TIME", 18, Color("#9eb4c0"))
	var time_color := Color("#ff6b69") if time_left < 10 else Color.WHITE
	draw_text(Vector2(W - 158, 56), "%02d" % ceili(time_left), 34, time_color)
	draw_text(Vector2(W - 240, 81), "BEAM", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 180, 69, 125, 12), Color("#20313b"), true)
	draw_rect(Rect2(W - 178, 71, 121 * beam_energy / 100.0, 8), Color("#caff63"), true)

func draw_game_over() -> void:
	draw_panel(Rect2(326, 104, 500, 425), Color(0.025, 0.07, 0.14, 0.9))
	draw_centered("MISSION COMPLETE", 165, 38, Color("#e8ff77"))
	draw_centered("THE FARMERS ARE CONFUSED.", 208, 18, Color("#9ce8d5"))
	draw_centered("%d" % captured, 306, 72, Color.WHITE)
	draw_centered("COWS LIBERATED", 342, 17, Color("#9eb4c0"))
	draw_centered("SCORE  %06d" % score, 397, 25, Color("#e8ff77"))
	draw_centered("BEST COMBO  x%d" % best_combo, 432, 18, Color("#9ce8d5"))
	draw_centered("PRESS SPACE TO RAID AGAIN", 490, 21, Color.WHITE)

func draw_boss() -> void:
	var p := boss_pos
	var hurt := boss_hit_flash
	var base_color := Color("#5a2866").lerp(Color.WHITE, hurt * 0.7)
	var dark := Color("#3a0f42").lerp(Color.WHITE, hurt * 0.5)
	var wart_color := Color("#7a3388").lerp(Color.WHITE, hurt * 0.4)

	for i in 6:
		var angle := boss_tentacle_phase + i * TAU / 6.0
		var tentacle_base := p + Vector2(cos(angle) * 40, 50)
		var seg1 := tentacle_base + Vector2(cos(angle + sin(boss_tentacle_phase + i) * 0.5) * 35, 30 + sin(boss_tentacle_phase * 1.3 + i) * 10)
		var seg2 := seg1 + Vector2(cos(angle + sin(boss_tentacle_phase * 0.7 + i * 2) * 0.8) * 30, 25 + sin(boss_tentacle_phase * 1.7 + i * 3) * 8)
		var seg3 := seg2 + Vector2(cos(angle + sin(boss_tentacle_phase * 1.1 + i * 1.5) * 1.0) * 20, 20)
		draw_line(tentacle_base, seg1, dark, 8)
		draw_line(seg1, seg2, dark, 6)
		draw_line(seg2, seg3, dark, 4)
		draw_circle(seg3, 5, Color("#cc44dd").lerp(Color.WHITE, hurt * 0.5))

	draw_custom_ellipse(p, Vector2(75, 55), base_color)
	draw_custom_ellipse(p + Vector2(0, -30), Vector2(55, 45), base_color)

	for i in 8:
		var wx := cos(i * 2.3 + 0.5) * 50
		var wy := sin(i * 1.7 + 0.3) * 35 - 10
		draw_circle(p + Vector2(wx, wy), 6 + sin(boss_phase + i) * 2, wart_color)

	draw_custom_ellipse(p + Vector2(-28, -35), Vector2(18, 14), Color.WHITE)
	draw_custom_ellipse(p + Vector2(28, -35), Vector2(18, 14), Color.WHITE)
	draw_custom_ellipse(p + Vector2(0, -55), Vector2(12, 10), Color.WHITE)

	var pupil_offset := (ufo_pos - p).normalized() * 5
	var anger_color := Color("#ff0000").lerp(Color("#cc2200"), sin(boss_phase * 3) * 0.5)
	draw_circle(p + Vector2(-28, -35) + pupil_offset, 7, anger_color)
	draw_circle(p + Vector2(28, -35) + pupil_offset, 7, anger_color)
	draw_circle(p + Vector2(0, -55) + pupil_offset, 5, anger_color)
	draw_circle(p + Vector2(-28, -35) + pupil_offset, 3, Color.BLACK)
	draw_circle(p + Vector2(28, -35) + pupil_offset, 3, Color.BLACK)
	draw_circle(p + Vector2(0, -55) + pupil_offset, 2, Color.BLACK)

	var mouth_open := 12 + sin(boss_phase * 2.5) * 5
	var mouth_points := PackedVector2Array()
	for i in 20:
		var a := PI * i / 19.0
		mouth_points.append(p + Vector2(cos(a) * 30, -8 + sin(a) * mouth_open))
	if mouth_points.size() >= 3:
		draw_colored_polygon(mouth_points, Color("#1a0022"))
	for i in 6:
		var tx := -22 + i * 9
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(tx, -8), p + Vector2(tx + 4, -8 + 8), p + Vector2(tx + 8, -8)
		]), Color("#ddddaa"))

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var horn_base := p + Vector2(side * 42, -60)
		var horn_mid := horn_base + Vector2(side * 15, -25)
		var horn_tip := horn_mid + Vector2(side * 8, -18)
		draw_line(horn_base, horn_mid, Color("#886644"), 7)
		draw_line(horn_mid, horn_tip, Color("#aa8855"), 5)
		draw_circle(horn_tip, 4, Color("#ffcc44"))

	var scar_start := p + Vector2(-15, -20)
	var scar_end := p + Vector2(10, -5)
	draw_line(scar_start, scar_end, Color("#2a0833"), 3)
	draw_line(scar_start + Vector2(5, -3), scar_end + Vector2(5, -3), Color("#2a0833"), 2)

func draw_mini_alien(ma: Dictionary) -> void:
	var p: Vector2 = ma.pos
	var wobble := sin(ma.phase * 3) * 0.15
	draw_set_transform(p, wobble, Vector2.ONE)
	draw_custom_ellipse(Vector2.ZERO, Vector2(18, 14), Color("#7a3888"))
	draw_custom_ellipse(Vector2(0, -10), Vector2(13, 10), Color("#6a2878"))
	draw_custom_ellipse(Vector2(-7, -12), Vector2(6, 5), Color.WHITE)
	draw_custom_ellipse(Vector2(7, -12), Vector2(6, 5), Color.WHITE)
	var pupil_dir := (ufo_pos - p).normalized() * 2
	draw_circle(Vector2(-7, -12) + pupil_dir, 3, Color("#ff0000"))
	draw_circle(Vector2(7, -12) + pupil_dir, 3, Color("#ff0000"))
	for i in 3:
		var ta: float = ma.phase * 2.5 + i * TAU / 3.0
		var t_end := Vector2(cos(ta) * 12, 14 + sin(ta) * 5)
		draw_line(Vector2(cos(ta) * 8, 10), t_end, Color("#4a1858"), 3)
	draw_set_transform(Vector2.ZERO)

func draw_boss_projectile(proj: Dictionary) -> void:
	var glow := 0.6 + sin(title_bob * 12 + proj.pos.x * 0.1) * 0.4
	draw_circle(proj.pos, 10, Color(1.0, 0.2, 0.8, glow * 0.3))
	draw_circle(proj.pos, 6, Color("#ff33cc"))
	draw_circle(proj.pos, 3, Color("#ffaaee"))

func draw_laser(laser: Dictionary) -> void:
	var dir: Vector2 = laser.vel.normalized()
	var tail: Vector2 = laser.pos - dir * 28
	draw_line(tail, laser.pos, Color("#44ffaa"), 5)
	draw_line(tail + dir * 6, laser.pos, Color("#aaffdd"), 3)
	draw_circle(laser.pos, 4, Color("#ffffff"))

func draw_boss_hud() -> void:
	draw_panel(Rect2(25, 22, 315, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "SCORE  %06d" % score, 21, Color.WHITE)
	draw_text(Vector2(45, 80), "LASERS  INF", 17, Color("#77ffaa"))

	draw_panel(Rect2(W * 0.5 - 160, 22, 320, 45), Color(0.12, 0.02, 0.06, 0.78))
	if boss_hp > 0:
		draw_centered("ALIEN OVERLORD", 42, 14, Color("#ff88cc"))
		var bar_width := 280.0 * float(boss_hp) / BOSS_MAX_HP
		var bar_color := Color("#ff3366") if boss_hp < BOSS_MAX_HP / 3 else Color("#ff6699")
		draw_rect(Rect2(W * 0.5 - 140, 50, 280, 10), Color("#20131b"), true)
		draw_rect(Rect2(W * 0.5 - 140, 50, bar_width, 10), bar_color, true)
	elif not mini_aliens.is_empty():
		draw_centered("MINI ALIENS  x%d" % mini_aliens.size(), 42, 14, Color("#ff88cc"))
		draw_centered("DESTROY THEM ALL!", 56, 12, Color("#ffaacc"))

	draw_panel(Rect2(W - 290, 22, 265, 55), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 270, 42), "SPACE / CLICK  •  FIRE LASER", 14, Color("#b8c8cf"))
	draw_text(Vector2(W - 270, 60), "HULL", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 225, 50, 180, 12), Color("#201b13"), true)
	var hp_pct := clampf(float(ufo_hp) / UFO_MAX_HP, 0.0, 1.0)
	var hp_color := Color("#ff4444") if hp_pct < 0.3 else Color("#44ff88")
	draw_rect(Rect2(W - 223, 52, 176 * hp_pct, 8), hp_color, true)

func draw_boss2() -> void:
	var p := boss2_pos
	var hurt := boss2_hit_flash
	var hull := Color("#445566").lerp(Color.WHITE, hurt * 0.6)
	var dark_hull := Color("#223344").lerp(Color.WHITE, hurt * 0.4)
	var glow_color := Color("#ff4444").lerp(Color("#ffaaaa"), sin(boss2_phase * 4) * 0.5 + 0.5)

	draw_circle(p + Vector2(0, 10), 70, Color(0.1, 0.05, 0.15, 0.3))

	draw_custom_ellipse(p, Vector2(85, 22), hull)
	draw_custom_ellipse(p + Vector2(0, -8), Vector2(70, 18), hull)

	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-30, -22), p + Vector2(0, -55), p + Vector2(30, -22)
	]), dark_hull)
	draw_circle(p + Vector2(0, -38), 12, Color("#112233"))
	draw_circle(p + Vector2(0, -38), 8, glow_color)

	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-82, 0), p + Vector2(-120, -30), p + Vector2(-100, 5)
	]), dark_hull)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(82, 0), p + Vector2(120, -30), p + Vector2(100, 5)
	]), dark_hull)
	draw_circle(p + Vector2(-115, -25), 6, Color("#ff3333"))
	draw_circle(p + Vector2(115, -25), 6, Color("#ff3333"))

	for i in 8:
		var angle := boss2_spin + i * TAU / 8.0
		var lp := p + Vector2(cos(angle) * 65, sin(angle) * 14 + 5)
		var lc := Color("#ff6633") if (int(boss2_phase * 6) + i) % 2 == 0 else Color("#ffaa22")
		draw_circle(lp, 5, lc)

	draw_custom_ellipse(p + Vector2(0, 8), Vector2(50, 12), dark_hull)

	for i in 3:
		var cannon_x := -35.0 + i * 35.0
		draw_rect(Rect2(p.x + cannon_x - 4, p.y + 18, 8, 16), dark_hull, true)
		draw_circle(Vector2(p.x + cannon_x, p.y + 34), 4, glow_color)

	draw_line(p + Vector2(-45, 22), p + Vector2(45, 22), Color("#99ffcc"), 3)

	var antenna_sway := sin(boss2_phase * 3) * 8
	draw_line(p + Vector2(-20, -55), p + Vector2(-25 + antenna_sway, -75), Color("#667788"), 2)
	draw_circle(p + Vector2(-25 + antenna_sway, -75), 3, Color("#ff4444"))
	draw_line(p + Vector2(20, -55), p + Vector2(25 - antenna_sway, -75), Color("#667788"), 2)
	draw_circle(p + Vector2(25 - antenna_sway, -75), 3, Color("#44ff44"))

func draw_boss2_hud() -> void:
	draw_panel(Rect2(25, 22, 315, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "SCORE  %06d" % score, 21, Color.WHITE)
	draw_text(Vector2(45, 80), "LASERS  INF", 17, Color("#77ffaa"))

	draw_panel(Rect2(W * 0.5 - 160, 22, 320, 45), Color(0.06, 0.02, 0.12, 0.78))
	draw_centered("ALIEN MOTHERSHIP", 42, 14, Color("#4488ff"))
	var bar_width := 280.0 * float(boss2_hp) / BOSS_MAX_HP
	var bar_color := Color("#ff3333") if boss2_hp < BOSS_MAX_HP / 3 else Color("#4488ff")
	draw_rect(Rect2(W * 0.5 - 140, 50, 280, 10), Color("#101320"), true)
	draw_rect(Rect2(W * 0.5 - 140, 50, bar_width, 10), bar_color, true)

	draw_panel(Rect2(W - 290, 22, 265, 55), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 270, 42), "SPACE / CLICK  •  FIRE LASER", 14, Color("#b8c8cf"))
	draw_text(Vector2(W - 270, 60), "HULL", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 225, 50, 180, 12), Color("#201b13"), true)
	var hp_pct := clampf(float(ufo_hp) / UFO_MAX_HP, 0.0, 1.0)
	var hp_color := Color("#ff4444") if hp_pct < 0.3 else Color("#44ff88")
	draw_rect(Rect2(W - 223, 52, 176 * hp_pct, 8), hp_color, true)

func draw_victory() -> void:
	draw_panel(Rect2(276, 104, 600, 440), Color(0.02, 0.07, 0.14, 0.92))
	draw_centered("VICTORY!", 170, 52, Color("#ffdd44"))
	draw_centered("ALL ALIEN FORCES DESTROYED!", 220, 20, Color("#ff88cc"))
	draw_centered("THE GALAXY IS SAFE... FOR NOW.", 250, 18, Color("#9ce8d5"))
	draw_centered("%d" % captured, 340, 72, Color.WHITE)
	draw_centered("COWS LIBERATED", 376, 17, Color("#9eb4c0"))
	draw_centered("SCORE  %06d" % score, 420, 28, Color("#e8ff77"))
	draw_centered("BEST COMBO  x%d" % best_combo, 458, 18, Color("#9ce8d5"))
	var pulse := 0.78 + sin(title_bob * 4) * 0.22
	draw_centered("PRESS SPACE TO PLAY AGAIN", 510, 21, Color(1, 1, 1, pulse))

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
