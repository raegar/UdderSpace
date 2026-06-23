extends Node2D

const W := 1152.0
const H := 648.0
const GROUND_Y := 535.0
const UFO_SPEED := 430.0
const BEAM_RANGE := 365.0

enum GameState { TITLE, PLAYING, LEVEL_COMPLETE, GAME_OVER }

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

const PENTATONIC_HZ := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 784.0, 880.0]
const NOTE_COLORS := [Color("#ff6b6b"), Color("#ffa94d"), Color("#ffd43b"), Color("#69db7c"), Color("#4dabf7"), Color("#748ffc"), Color("#da77f2"), Color("#f783ac"), Color("#38d9a9"), Color("#fcc419")]
var note_players: Array[AudioStreamPlayer] = []
var note_spawn_counter := 0

const LEVEL_TARGETS   := [4,    6,    9,    12,   16  ]
const LEVEL_MAX_COWS  := [8,    9,    10,   10,   10  ]
const LEVEL_SPEED     := [25.0, 36.0, 50.0, 65.0, 82.0]
const LEVEL_DRAIN     := [25.0, 28.0, 32.0, 37.0, 44.0]
const LEVEL_SPAWN_MIN := [1.5,  1.2,  0.9,  0.7,  0.5 ]
const LEVEL_SPAWN_MAX := [3.0,  2.4,  1.8,  1.4,  1.1 ]
var level := 1
var level_captured := 0
var level_complete_timer := 0.0

var boss := {}
var boss_active := false
var boss_intro_timer := 0.0

func generate_tone(frequency: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var samples := int(sample_rate * 0.6)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(sample_rate)
		var envelope := minf(1.0, t * 30.0) * exp(-t * 3.5)
		var wave := sin(TAU * frequency * t) * 0.7 + sin(TAU * frequency * 2.0 * t) * 0.2 + sin(TAU * frequency * 3.0 * t) * 0.1
		data.encode_s16(i * 2, clampi(int(28000.0 * wave * envelope), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func setup_audio() -> void:
	for hz in PENTATONIC_HZ:
		var player := AudioStreamPlayer.new()
		player.stream = generate_tone(hz)
		player.volume_db = -8.0
		add_child(player)
		note_players.append(player)

func spawn_boss() -> void:
	boss = {
		"pos": Vector2(W * 0.88, GROUND_Y),
		"vel": Vector2.ZERO,
		"phase": 0.0,
		"dir": -1.0,
		"mouth_open": 0.0,
		"hunger": 0
	}
	boss_active = true
	boss_intro_timer = 3.5

func update_boss(delta: float) -> void:
	boss.phase = float(boss.phase) + delta * 4.5
	boss_intro_timer = maxf(0.0, boss_intro_timer - delta)
	var bpos: Vector2 = boss.pos
	var bdir: float = float(boss.dir)

	var nearest_dist := INF
	var target_x := bpos.x
	for cow in cows:
		var cpos: Vector2 = cow.pos
		var d := bpos.distance_to(cpos)
		if d < nearest_dist:
			nearest_dist = d
			target_x = cpos.x

	var speed := minf(210.0, 95.0 + float(boss.hunger) * 7.0)
	var dx := target_x - bpos.x
	if absf(dx) > 10:
		bdir = 1.0 if dx > 0 else -1.0
		boss.dir = bdir
	var new_vx := move_toward(float(boss.vel.x), bdir * speed, delta * 95.0)
	boss.vel = Vector2(new_vx, 0)
	boss.pos = Vector2(clampf(bpos.x + new_vx * delta, 85, W - 85), bpos.y)

	boss.mouth_open = minf(1.0, float(boss.mouth_open) + delta * (3.5 if nearest_dist < 170 else -2.2))
	boss.mouth_open = maxf(0.0, boss.mouth_open)

	var mouth_pos := Vector2(bpos.x + bdir * 72, bpos.y - 36)
	for i in range(cows.size() - 1, -1, -1):
		var cpos: Vector2 = cows[i].pos
		if mouth_pos.distance_to(cpos) < 58:
			for j in 16:
				add_particle(cpos + Vector2(rng.randf_range(-24, 24), rng.randf_range(-20, 8)), Color("#cc1133"), "burst")
			cows.remove_at(i)
			boss.hunger = int(boss.hunger) + 1
			boss.mouth_open = 1.0
			screen_shake = 6.0

func draw_boss() -> void:
	var bpos: Vector2 = boss.pos
	var bdir: float = float(boss.dir)
	var ph: float = float(boss.phase)
	var mo: float = float(boss.mouth_open)
	var swing := sin(ph) * 11.0
	var jaw := mo * 26.0

	draw_custom_ellipse(Vector2(bpos.x, bpos.y + 6), Vector2(82, 13), Color(0, 0, 0, 0.35))
	draw_set_transform(bpos, 0.0, Vector2(bdir, 1.0))

	# Back spikes
	for i in 6:
		var sx := float(-28 + i * 11)
		var tip_y := -98.0 - float(i % 3) * 9.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx - 7, -74), Vector2(sx + 1, tip_y), Vector2(sx + 9, -74)
		]), Color("#5a006a"))

	# Body
	draw_custom_ellipse(Vector2(0, -44), Vector2(54, 42), Color("#1a0828"))
	draw_custom_ellipse(Vector2(-12, -58), Vector2(26, 14), Color("#2e0d45", 0.5))

	# Legs
	draw_line(Vector2(-32, -20), Vector2(-35 + swing, 4), Color("#120518"), 10)
	draw_line(Vector2(-11, -16), Vector2(-11 - swing, 5), Color("#120518"), 10)
	draw_line(Vector2(11, -16), Vector2(13 + swing, 5), Color("#120518"), 10)
	draw_line(Vector2(32, -20), Vector2(35 - swing, 4), Color("#120518"), 10)
	for lx: float in [-35.0, -11.0, 13.0, 35.0]:
		draw_circle(Vector2(lx, 5), 7, Color("#120518"))

	# Head
	draw_circle(Vector2(55, -40), 40, Color("#250a3c"))

	# Jaws
	draw_custom_ellipse(Vector2(64, -52 - jaw * 0.5), Vector2(33, 17), Color("#3b1150"))
	draw_custom_ellipse(Vector2(64, -28 + jaw * 0.5), Vector2(31, 15), Color("#3b1150"))

	# Mouth interior
	if mo > 0.05:
		draw_custom_ellipse(Vector2(68, -40), Vector2(26.0 * mo + 3, 21.0 * mo + 3), Color("#7a0015"))
		if mo > 0.5:
			draw_custom_ellipse(Vector2(72, -32 + jaw * 0.35), Vector2(13, 8), Color("#cc1133"))

	# Teeth
	if mo > 0.2:
		for t in 4:
			var tx := 38.0 + float(t) * 12.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(tx - 4, -36 - jaw * 0.5),
				Vector2(tx + 2,  -20 - jaw * 0.5),
				Vector2(tx + 8, -36 - jaw * 0.5)
			]), Color(0.9, 0.88, 0.78))
		for t in 3:
			var tx := 44.0 + float(t) * 13.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(tx - 3, -44 + jaw * 0.5),
				Vector2(tx + 2,  -57 + jaw * 0.5),
				Vector2(tx + 7, -44 + jaw * 0.5)
			]), Color(0.88, 0.85, 0.72))

	# Eyes
	draw_circle(Vector2(42, -66), 17, Color(1.0, 0.1, 0.0, 0.35))
	draw_circle(Vector2(42, -66), 13, Color("#ff1800"))
	draw_circle(Vector2(42, -66), 8,  Color("#ff7200"))
	draw_circle(Vector2(45, -66), 5,  Color(0.04, 0.0, 0.04))
	draw_circle(Vector2(38, -71), 4,  Color(1.0, 0.9, 0.9, 0.45))

	draw_set_transform(Vector2.ZERO)

	# Name tag during intro
	if boss_intro_timer > 0:
		var alpha: float
		if boss_intro_timer > 3.0:
			alpha = (3.5 - boss_intro_timer) / 0.5
		elif boss_intro_timer < 1.2:
			alpha = boss_intro_timer / 1.2
		else:
			alpha = 1.0
		draw_centered("MOOCHER  AWAKENS", H * 0.28, 34, Color(1.0, 0.22, 0.08, alpha))
		draw_centered("PROTECT YOUR COWS", H * 0.28 + 44, 19, Color(1.0, 0.65, 0.3, alpha * 0.85))

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
	setup_audio()
	queue_redraw()

func start_game() -> void:
	level = 1
	score = 0
	combo = 0
	best_combo = 0
	captured = 0
	boss_active = false
	start_level()

func start_level() -> void:
	state = GameState.PLAYING
	ufo_pos = Vector2(W * 0.5, 155)
	ufo_vel = Vector2.ZERO
	cows.clear()
	particles.clear()
	level_captured = 0
	time_left = 45.0
	beam_energy = 100.0
	beam_on = false
	spawn_timer = 0.0
	note_spawn_counter = 0
	combo = 0
	boss_active = false
	for i in 8:
		spawn_cow(90.0 + i * 135.0 + rng.randf_range(-30, 30))
	if level == 5:
		spawn_boss()

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
		"size": rng.randf_range(0.88, 1.1),
		"note": note_spawn_counter % PENTATONIC_HZ.size()
	})
	note_spawn_counter += 1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			if state == GameState.LEVEL_COMPLETE:
				level_complete_timer = 0.0
				get_viewport().set_input_as_handled()
			elif state != GameState.PLAYING:
				start_game()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and state == GameState.PLAYING:
			state = GameState.TITLE
	if event is InputEventMouseButton and event.pressed:
		if state == GameState.LEVEL_COMPLETE:
			level_complete_timer = 0.0
		elif state != GameState.PLAYING:
			start_game()

func _process(delta: float) -> void:
	title_bob += delta
	for cloud in clouds:
		cloud.pos.x += cloud.speed * delta
		if cloud.pos.x > W + 140:
			cloud.pos.x = -140
	if state == GameState.PLAYING:
		update_game(delta)
	elif state == GameState.LEVEL_COMPLETE:
		level_complete_timer -= delta
		if level_complete_timer <= 0:
			level += 1
			if level > 5:
				state = GameState.GAME_OVER
			else:
				start_level()
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
		beam_energy = maxf(0, beam_energy - delta * LEVEL_DRAIN[level - 1])
	else:
		beam_energy = minf(100, beam_energy + delta * 18.0)

	spawn_timer -= delta
	if spawn_timer <= 0 and cows.size() < LEVEL_MAX_COWS[level - 1]:
		spawn_cow()
		spawn_timer = rng.randf_range(LEVEL_SPAWN_MIN[level - 1], LEVEL_SPAWN_MAX[level - 1])

	for cow in cows:
		update_cow(cow, delta)

	if boss_active:
		update_boss(delta)

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
			var wander: float = float(cow.dir) * LEVEL_SPEED[level - 1]
			if boss_active:
				var cpos: Vector2 = cow.pos
				var bpos: Vector2 = boss.pos
				if cpos.distance_to(bpos) < 210:
					cow.fear = minf(1.0, float(cow.fear) + delta * 3.5)
					wander = signf(cpos.x - bpos.x) * LEVEL_SPEED[level - 1] * 2.4
			cow.vel.x = move_toward(float(cow.vel.x), wander, delta * 35.0)
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
		if not note_players.is_empty():
			var ni := int(cow.note) % note_players.size()
			note_players[ni].stop()
			note_players[ni].play()
		captured += 1
		level_captured += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		var points := 100 * combo
		score += points
		time_left = minf(99.0, time_left + 2.0)
		beam_energy = minf(100, beam_energy + 22)
		screen_shake = 8.0
		flash = 0.35
		for j in 18:
			add_particle(ufo_pos + Vector2(rng.randf_range(-35, 35), 15), Color("#d7ff75"), "burst")
		if level_captured >= LEVEL_TARGETS[level - 1]:
			state = GameState.LEVEL_COMPLETE
			level_complete_timer = 2.5
			beam_on = false
	elif not in_beam and cow.airborne and cow.pos.y >= GROUND_Y - 17:
		combo = 0

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
	for cow in cows:
		draw_cow(cow)
	if boss_active:
		draw_boss()
	if state == GameState.PLAYING and beam_on:
		draw_beam()
	draw_ufo(ufo_pos, state == GameState.TITLE)
	for p in particles:
		draw_particle(p)
	draw_set_transform(Vector2.ZERO)
	if state == GameState.TITLE:
		draw_title()
	elif state == GameState.PLAYING:
		draw_hud()
	elif state == GameState.LEVEL_COMPLETE:
		draw_level_complete()
	else:
		draw_game_over()
	if flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(0.8, 1.0, 0.65, flash), true)

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
	var nc: Color = NOTE_COLORS[int(cow.note) % NOTE_COLORS.size()]
	var dot_r: float = 5.0 + float(cow.fear) * 3.0
	draw_circle(p + Vector2(0, -44), dot_r + 2.5, Color(nc, 0.25))
	draw_circle(p + Vector2(0, -44), dot_r, nc)

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
	draw_centered("CLEAR 5 LEVELS  •  ABDUCT THE HERD", 342, 20, Color.WHITE)
	draw_centered("ARROW KEYS / WASD  •  MOVE", 392, 18, Color("#b8c8cf"))
	draw_centered("HOLD SPACE OR LEFT CLICK  •  TRACTOR BEAM", 426, 18, Color("#b8c8cf"))
	var pulse := 0.78 + sin(title_bob * 4) * 0.22
	draw_centered("PRESS SPACE TO INVADE", 490, 24, Color(0.9, 1, 0.45, pulse))

func draw_hud() -> void:
	draw_panel(Rect2(25, 22, 340, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "COWS  %d/%d" % [level_captured, LEVEL_TARGETS[level - 1]], 21, Color("#dffb78"))
	draw_text(Vector2(210, 52), "SCORE  %06d" % score, 21, Color.WHITE)
	draw_text(Vector2(45, 80), "COMBO  x%d" % maxi(1, combo), 17, Color("#8fe8d1"))
	if level == 5:
		draw_centered("BOSS  STAGE", 46, 22, Color("#ff4422"))
	else:
		draw_centered("LEVEL  %d" % level, 46, 22, Color("#e8ff77"))
	draw_panel(Rect2(W - 260, 22, 235, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 240, 52), "TIME", 18, Color("#9eb4c0"))
	var time_color := Color("#ff6b69") if time_left < 10 else Color.WHITE
	draw_text(Vector2(W - 158, 56), "%02d" % ceili(time_left), 34, time_color)
	draw_text(Vector2(W - 240, 81), "BEAM", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 180, 69, 125, 12), Color("#20313b"), true)
	draw_rect(Rect2(W - 178, 71, 121 * beam_energy / 100.0, 8), Color("#caff63"), true)

func draw_level_complete() -> void:
	draw_panel(Rect2(326, 150, 500, 310), Color(0.025, 0.07, 0.14, 0.92))
	if level == 5:
		draw_centered("FINAL LEVEL CLEAR!", 228, 36, Color("#e8ff77"))
		draw_centered("THE HERD FLIES FREE", 276, 18, Color("#9ce8d5"))
	else:
		draw_centered("LEVEL %d COMPLETE" % level, 228, 36, Color("#e8ff77"))
		draw_centered("LEVEL %d  INCOMING" % (level + 1), 276, 18, Color("#9ce8d5"))
	draw_centered("%d COWS BEAMED" % level_captured, 318, 20, Color.WHITE)
	draw_centered("SCORE  %06d" % score, 358, 22, Color("#dffb78"))
	var pulse := 0.78 + sin(title_bob * 5) * 0.22
	draw_centered("GET READY...", 420, 20, Color(0.9, 1.0, 0.45, pulse))

func draw_game_over() -> void:
	draw_panel(Rect2(326, 104, 500, 425), Color(0.025, 0.07, 0.14, 0.9))
	if level > 5:
		draw_centered("ALL 5 LEVELS CLEAR!", 165, 34, Color("#e8ff77"))
		draw_centered("THE HERD IS FREE.", 208, 18, Color("#9ce8d5"))
	else:
		draw_centered("MISSION COMPLETE", 165, 38, Color("#e8ff77"))
		draw_centered("LEVEL %d  •  TIME'S UP" % level, 208, 18, Color("#9ce8d5"))
	draw_centered("%d" % captured, 290, 72, Color.WHITE)
	draw_centered("COWS LIBERATED", 330, 17, Color("#9eb4c0"))
	draw_centered("SCORE  %06d" % score, 385, 25, Color("#e8ff77"))
	draw_centered("BEST COMBO  x%d" % best_combo, 420, 18, Color("#9ce8d5"))
	draw_centered("PRESS SPACE TO RAID AGAIN", 490, 21, Color.WHITE)

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
