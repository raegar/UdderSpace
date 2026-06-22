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
var rng := RandomNumberGenerator.new()

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
			if state != GameState.PLAYING:
				start_game()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and state == GameState.PLAYING:
			state = GameState.TITLE
	if event is InputEventMouseButton and event.pressed:
		if state != GameState.PLAYING:
			start_game()

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
		spawn_timer = rng.randf_range(1.5, 3.0)

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
			cow.vel.x = move_toward(cow.vel.x, cow.dir * 25.0, delta * 20.0)
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
		time_left = minf(99.0, time_left + 2.0)
		beam_energy = minf(100, beam_energy + 22)
		screen_shake = 8.0
		flash = 0.35
		for j in 18:
			add_particle(ufo_pos + Vector2(rng.randf_range(-35, 35), 15), Color("#d7ff75"), "burst")
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
