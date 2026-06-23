extends Node2D

const W := 1152.0
const H := 648.0
const GROUND_Y := 535.0
const UFO_SPEED := 430.0
const BEAM_RANGE := 365.0

const STORE_ITEMS: Array = [
	{"id": "sparkles", "name": "SPARKLES",  "cost": 150, "desc": "Twinkling stars orbit your UFO"},
	{"id": "stars",    "name": "STAR TRIM", "cost": 250, "desc": "Gold stars line the saucer rim"},
	{"id": "ribbon",   "name": "RIBBON",    "cost": 350, "desc": "A rainbow ribbon trails behind"},
	{"id": "moons",    "name": "MOONS",     "cost": 500, "desc": "Crescent moons orbit your craft"},
	{"id": "planets",  "name": "PLANETS",   "cost": 750, "desc": "Tiny planets circle the UFO"},
]

enum GameState { TITLE, PLAYING, GAME_OVER, STORE }

var state := GameState.TITLE
var ufo_pos := Vector2(W * 0.5, 170.0)
var ufo_vel := Vector2.ZERO
var animals: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var stars: Array[Vector2] = []
var clouds: Array[Dictionary] = []
var score := 0
var combo := 0
var best_combo := 0
var time_left := 30.0
var beam_energy := 100.0
var beam_on := false
var screen_shake := 0.0
var flash := 0.0
var spawn_timer := 0.0
var captured := 0
var title_bob := 0.0
var rng := RandomNumberGenerator.new()

var coins := 0
var owned_decorations: Array[String] = []
var active_decorations: Array[String] = []
var store_cursor := 0
var ufo_trail: Array[Vector2] = []
var trail_timer := 0.0

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
	animals.clear()
	particles.clear()
	ufo_trail.clear()
	score = 0
	combo = 0
	best_combo = 0
	captured = 0
	time_left = 30.0
	beam_energy = 100.0
	spawn_timer = 0.0
	trail_timer = 0.0
	for i in 8:
		spawn_animal(90.0 + i * 135.0 + rng.randf_range(-30, 30))

func _animal_ground_offset(atype: String) -> float:
	match atype:
		"pig": return 14.0
		"sheep": return 14.0
		"chicken": return 10.0
	return 16.0

func spawn_animal(x := -1.0) -> void:
	if x < 0:
		x = rng.randf_range(65, W - 65)
	var roll := rng.randf()
	var atype: String
	if roll < 0.35:
		atype = "cow"
	elif roll < 0.58:
		atype = "pig"
	elif roll < 0.82:
		atype = "sheep"
	else:
		atype = "chicken"

	var base_sizes := {"cow": 1.0, "pig": 1.05, "sheep": 0.9, "chicken": 0.65}
	var walk_speeds := {"cow": 25.0, "pig": 18.0, "sheep": 30.0, "chicken": 48.0}
	var point_values := {"cow": 100, "pig": 150, "sheep": 75, "chicken": 200}
	var goff := _animal_ground_offset(atype)

	var animal: Dictionary = {
		"type": atype,
		"pos": Vector2(x, GROUND_Y - goff),
		"vel": Vector2(rng.randf_range(-24, 24), 0),
		"dir": -1.0 if rng.randf() < 0.5 else 1.0,
		"phase": rng.randf_range(0, TAU),
		"fear": 0.0,
		"airborne": false,
		"captured": false,
		"size": base_sizes[atype] * rng.randf_range(0.9, 1.1),
		"walk_speed": walk_speeds[atype],
		"point_value": point_values[atype],
		"ground_offset": goff,
	}

	match atype:
		"cow":
			var spots: Array[Vector2] = []
			var spot_radii: Array[float] = []
			for _i in rng.randi_range(2, 5):
				spots.append(Vector2(rng.randf_range(-22, 20), rng.randf_range(-10, 12)))
				spot_radii.append(rng.randf_range(3.5, 6.5))
			animal["variant"] = rng.randi_range(0, 3)
			animal["spots"] = spots
			animal["spot_radii"] = spot_radii
			animal["horns"] = rng.randi_range(0, 2)
		"pig":
			animal["pig_color"] = rng.randi_range(0, 2)
		"sheep":
			var blobs: Array[Vector2] = []
			for _i in 7:
				blobs.append(Vector2(rng.randf_range(-24, 16), rng.randf_range(-15, 6)))
			animal["wool_blobs"] = blobs
			animal["wool_color"] = rng.randi_range(0, 2)
		"chicken":
			animal["feather_color"] = rng.randi_range(0, 2)

	animals.append(animal)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state == GameState.STORE:
			match event.keycode:
				KEY_ESCAPE:
					state = GameState.TITLE
				KEY_UP, KEY_W:
					store_cursor = posmod(store_cursor - 1, STORE_ITEMS.size())
				KEY_DOWN, KEY_S:
					store_cursor = posmod(store_cursor + 1, STORE_ITEMS.size())
				KEY_SPACE, KEY_ENTER:
					_store_select()
		elif event.keycode in [KEY_ENTER, KEY_SPACE]:
			if state != GameState.PLAYING:
				start_game()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and state == GameState.PLAYING:
			state = GameState.TITLE
		elif event.keycode == KEY_S and state in [GameState.TITLE, GameState.GAME_OVER]:
			state = GameState.STORE
	if event is InputEventMouseButton and event.pressed:
		if state == GameState.TITLE or state == GameState.GAME_OVER:
			start_game()

func _store_select() -> void:
	var item: Dictionary = STORE_ITEMS[store_cursor]
	var id: String = item.id
	if id in owned_decorations:
		if id in active_decorations:
			active_decorations.erase(id)
		else:
			active_decorations.append(id)
	elif coins >= item.cost:
		coins -= item.cost
		owned_decorations.append(id)
		active_decorations.append(id)

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

	if "ribbon" in active_decorations:
		trail_timer += delta
		if trail_timer >= 0.04:
			trail_timer = 0.0
			ufo_trail.push_front(ufo_pos)
			if ufo_trail.size() > 48:
				ufo_trail.pop_back()

	beam_on = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	beam_on = beam_on and beam_energy > 0.5
	if beam_on:
		beam_energy = maxf(0, beam_energy - delta * 25.0)
	else:
		beam_energy = minf(100, beam_energy + delta * 18.0)

	spawn_timer -= delta
	if spawn_timer <= 0 and animals.size() < 10:
		spawn_animal()
		spawn_timer = rng.randf_range(1.5, 3.0)

	for animal in animals:
		update_animal(animal, delta)

	for i in range(animals.size() - 1, -1, -1):
		if animals[i].captured:
			animals.remove_at(i)

func update_animal(animal: Dictionary, delta: float) -> void:
	var dir_change_rate := 1.2 if animal.type == "chicken" else 0.25
	animal.phase += delta * 5.0
	var offset: Vector2 = animal.pos - ufo_pos
	var in_beam: bool = beam_on and animal.pos.y > ufo_pos.y and absf(offset.x) < beam_width_at(animal.pos.y) and animal.pos.y < ufo_pos.y + BEAM_RANGE

	if in_beam:
		animal.airborne = true
		animal.fear = minf(1.0, animal.fear + delta * 4.0)
		var pull := Vector2((ufo_pos.x - animal.pos.x) * 4.3, -245.0)
		animal.vel = animal.vel.lerp(pull, 1.0 - exp(-delta * 3.4))
		animal.vel.y -= delta * 100.0
		if rng.randf() < delta * 8.0:
			add_particle(animal.pos + Vector2(rng.randf_range(-15, 15), 10), Color("#caff70"), "spark")
	else:
		animal.fear = maxf(0.0, animal.fear - delta * 2.0)
		if animal.airborne:
			animal.vel.y += 420.0 * delta
		else:
			animal.vel.x = move_toward(animal.vel.x, animal.dir * animal.walk_speed, delta * 20.0)
			if rng.randf() < delta * dir_change_rate:
				animal.dir *= -1.0

	var ground_y: float = GROUND_Y - float(animal.ground_offset)
	animal.pos += animal.vel * delta
	if animal.pos.y >= ground_y:
		if animal.airborne and animal.vel.y > 170:
			for _j in 5:
				add_particle(animal.pos + Vector2(rng.randf_range(-18, 18), 12), Color("#b69568"), "dust")
		animal.pos.y = ground_y
		animal.vel.y = 0
		animal.airborne = false
	if animal.pos.x < 35:
		animal.pos.x = 35
		animal.dir = 1.0
	if animal.pos.x > W - 35:
		animal.pos.x = W - 35
		animal.dir = -1.0

	if animal.pos.distance_to(ufo_pos) < 48:
		animal.captured = true
		captured += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		score += animal.point_value * combo
		coins += maxi(1, animal.point_value / 10)
		time_left = minf(99.0, time_left + 2.0)
		beam_energy = minf(100, beam_energy + 22)
		screen_shake = 8.0
		flash = 0.35
		for _j in 18:
			add_particle(ufo_pos + Vector2(rng.randf_range(-35, 35), 15), Color("#d7ff75"), "burst")
	elif not in_beam and animal.airborne and animal.pos.y >= ground_y - 1:
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
	for animal in animals:
		draw_animal(animal)

	var display_ufo_pos := ufo_pos
	if state != GameState.PLAYING:
		display_ufo_pos = Vector2(W * 0.5, 224 + sin(title_bob * 2.0) * 8)

	if "ribbon" in active_decorations and ufo_trail.size() > 1:
		_draw_ribbon()

	if state == GameState.PLAYING and beam_on:
		draw_beam()

	draw_ufo_decorations_back(display_ufo_pos)
	draw_ufo(ufo_pos, state != GameState.PLAYING)
	draw_ufo_decorations_front(display_ufo_pos)

	for p in particles:
		draw_particle(p)
	draw_set_transform(Vector2.ZERO)
	if state == GameState.TITLE:
		draw_title()
	elif state == GameState.PLAYING:
		draw_hud()
	elif state == GameState.STORE:
		draw_store()
	else:
		draw_game_over()
	if flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(0.8, 1.0, 0.65, flash), true)

func _draw_ribbon() -> void:
	for i in ufo_trail.size() - 1:
		var t := float(i) / float(ufo_trail.size())
		var hue := fmod(title_bob * 0.5 + float(i) * 0.04, 1.0)
		var c := Color.from_hsv(hue, 0.88, 1.0, (1.0 - t) * 0.72)
		draw_line(ufo_trail[i], ufo_trail[i + 1], c, maxf(1.0, 4.5 * (1.0 - t)))

# Decorations drawn behind the UFO (ribbon already done, nothing else needs to go behind)
func draw_ufo_decorations_back(_pos: Vector2) -> void:
	pass

# Decorations drawn in front of the UFO
func draw_ufo_decorations_front(pos: Vector2) -> void:
	if "planets" in active_decorations:
		var planet_defs := [
			[Color("#4a8fd4"), Color("#a0c8ff")],
			[Color("#c05030"), Color("#ff9060")],
		]
		for i in 2:
			var a := title_bob * 0.38 + i * PI + 0.9
			var pp := pos + Vector2(cos(a) * 112, sin(a) * 42 - 5)
			draw_mini_planet(pp, 11, planet_defs[i][0], planet_defs[i][1])

	if "moons" in active_decorations:
		for i in 3:
			var a := title_bob * 0.52 + i * TAU / 3
			var mp := pos + Vector2(cos(a) * 96, sin(a) * 34 - 4)
			draw_crescent_moon(mp, 9, a + PI * 0.6, Color("#f0e8c0"))

	if "sparkles" in active_decorations:
		for i in 6:
			var a := title_bob * 1.15 + i * TAU / 6
			var sp := pos + Vector2(cos(a) * 82, sin(a) * 26 - 4)
			var brightness := 0.65 + sin(title_bob * 5.0 + i * 1.4) * 0.35
			draw_4star(sp, 5.5, Color(1.0, 0.95, 0.5, brightness))

	if "stars" in active_decorations:
		for i in 8:
			var a := float(i) * TAU / 8
			var sp := pos + Vector2(cos(a) * 58, sin(a) * 9 + 4)
			draw_4star(sp, 6.5, Color("#ffd740"))

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
	# Alien inside dome
	var ac := p + Vector2(0, -13)
	draw_custom_ellipse(ac + Vector2(0, 8), Vector2(7, 9), Color("#6abf8a"))
	draw_circle(ac + Vector2(0, -4), 11, Color("#7dd6a0"))
	draw_custom_ellipse(ac + Vector2(-5, -5), Vector2(4, 5), Color("#0a1020"))
	draw_custom_ellipse(ac + Vector2(5, -5), Vector2(4, 5), Color("#0a1020"))
	draw_circle(ac + Vector2(-4, -6), 1.5, Color(1, 1, 1, 0.7))
	draw_circle(ac + Vector2(6, -6), 1.5, Color(1, 1, 1, 0.7))
	draw_line(ac + Vector2(-5, -14), ac + Vector2(-9, -22), Color("#6abf8a"), 2)
	draw_circle(ac + Vector2(-9, -22), 2.5, Color("#caff70"))
	draw_line(ac + Vector2(5, -14), ac + Vector2(9, -22), Color("#6abf8a"), 2)
	draw_circle(ac + Vector2(9, -22), 2.5, Color("#caff70"))
	draw_line(ac + Vector2(-7, 2), ac + Vector2(-14, 6), Color("#6abf8a"), 2)
	draw_line(ac + Vector2(7, 2), ac + Vector2(14, 6), Color("#6abf8a"), 2)
	draw_arc(p + Vector2(0, -13), 29, PI, TAU, 30, Color("#d1fff2"), 3)
	draw_circle(p + Vector2(-9, -18), 6, Color(1, 1, 1, 0.28))
	for i in 5:
		var lx := -40 + i * 20
		var lc := Color("#dfff58") if (int(title_bob * 8) + i) % 2 == 0 else Color("#ffcb4f")
		draw_circle(p + Vector2(lx, 10), 4.5, lc)
	draw_line(p + Vector2(-26, 22), p + Vector2(26, 22), Color("#c9ff6a"), 4)

func draw_animal(animal: Dictionary) -> void:
	var p: Vector2 = animal.pos
	var s: float = animal.size
	var angle := clampf(animal.vel.x / 500.0, -0.35, 0.35)
	if animal.airborne:
		angle += sin(animal.phase) * 0.12
	draw_set_transform(p, angle, Vector2(s, s))
	match animal.type:
		"cow": _draw_cow(animal)
		"pig": _draw_pig(animal)
		"sheep": _draw_sheep(animal)
		"chicken": _draw_chicken(animal)
	draw_set_transform(Vector2.ZERO)

func _draw_cow(animal: Dictionary) -> void:
	var body: Color; var spot: Color; var nose: Color
	match animal.variant:
		0: body = Color("#f4eee2"); spot = Color("#252733"); nose = Color("#e7b7a8")
		1: body = Color("#a0622a"); spot = Color("#c8843d"); nose = Color("#e2a070")
		2: body = Color("#2a2b38"); spot = Color("#4d5068"); nose = Color("#b07060")
		3: body = Color("#d4aa6e"); spot = Color("#6b3c1a"); nose = Color("#e8b890")
		_: body = Color("#f4eee2"); spot = Color("#252733"); nose = Color("#e7b7a8")
	var dark := spot if animal.variant == 0 else body.darkened(0.55)
	draw_custom_ellipse(Vector2.ZERO, Vector2(27, 16), body)
	draw_circle(Vector2(25, -5), 12, body)
	for i in animal.spots.size():
		draw_circle(animal.spots[i], animal.spot_radii[i], spot)
	draw_circle(Vector2(31, -4), 5, nose)
	match animal.horns:
		0:
			draw_colored_polygon(PackedVector2Array([Vector2(17, -14), Vector2(12, -22), Vector2(22, -17)]), dark)
			draw_colored_polygon(PackedVector2Array([Vector2(31, -14), Vector2(36, -21), Vector2(37, -12)]), dark)
		1:
			draw_line(Vector2(16, -15), Vector2(10, -28), dark, 4)
			draw_line(Vector2(32, -15), Vector2(40, -27), dark, 4)
		2:
			draw_circle(Vector2(13, -16), 4, body)
			draw_circle(Vector2(33, -15), 4, body)
	draw_custom_ellipse(Vector2(-10, -5), Vector2(9, 7), dark)
	draw_custom_ellipse(Vector2(9, 7), Vector2(7, 6), dark)
	var leg_kick: float = sin(animal.phase) * (7.0 if animal.airborne else 2.0)
	draw_line(Vector2(-15, 12), Vector2(-16 + leg_kick, 27), dark, 5)
	draw_line(Vector2(13, 12), Vector2(14 - leg_kick, 27), dark, 5)
	draw_line(Vector2(-26, -4), Vector2(-34, -14 + sin(animal.phase) * 4), dark, 3)
	draw_circle(Vector2(28, -8), 2.3, Color("#10151d") if animal.variant != 2 else Color("#8090a0"))
	if animal.fear > 0.2:
		draw_circle(Vector2(28, -8), 5, Color.WHITE, false, 1.5)

func _draw_pig(animal: Dictionary) -> void:
	var body: Color; var dark: Color; var nose: Color
	match animal.pig_color:
		0: body = Color("#f0a8b0"); dark = Color("#c06878"); nose = Color("#e87888")
		1: body = Color("#e8c8a0"); dark = Color("#8a5030"); nose = Color("#d09070")
		2: body = Color("#504048"); dark = Color("#302030"); nose = Color("#806070")
		_: body = Color("#f0a8b0"); dark = Color("#c06878"); nose = Color("#e87888")
	draw_circle(Vector2(0, 20), 26, Color(0, 0, 0, 0.18))
	draw_custom_ellipse(Vector2.ZERO, Vector2(30, 18), body)
	draw_circle(Vector2(28, -3), 14, body)
	draw_circle(Vector2(39, 1), 7, nose)
	draw_circle(Vector2(37, 0), 2.2, dark)
	draw_circle(Vector2(42, 0), 2.2, dark)
	draw_colored_polygon(PackedVector2Array([Vector2(18, -15), Vector2(13, -26), Vector2(25, -20)]), dark)
	draw_colored_polygon(PackedVector2Array([Vector2(31, -14), Vector2(34, -25), Vector2(38, -17)]), dark)
	if animal.pig_color == 1:
		draw_circle(Vector2(-8, -4), 7, dark)
		draw_circle(Vector2(10, 8), 5, dark)
	draw_arc(Vector2(-32, -3), 6, 0, PI * 1.5, 12, dark, 3)
	draw_arc(Vector2(-29, 2), 3, PI * 0.5, PI * 2.0, 8, dark, 2)
	var kick: float = sin(animal.phase) * (6.0 if animal.airborne else 2.0)
	draw_line(Vector2(-14, 13), Vector2(-15 + kick, 26), dark, 5)
	draw_line(Vector2(6, 14), Vector2(7 - kick, 27), dark, 5)
	draw_line(Vector2(16, 12), Vector2(17 + kick, 25), dark, 4)
	draw_line(Vector2(-4, 14), Vector2(-3 - kick, 27), dark, 4)
	draw_circle(Vector2(32, -6), 2.5, Color("#10151d"))
	if animal.fear > 0.2:
		draw_circle(Vector2(32, -6), 5, Color.WHITE, false, 1.5)

func _draw_sheep(animal: Dictionary) -> void:
	var wool: Color; var face: Color
	match animal.wool_color:
		0: wool = Color("#eeeae0"); face = Color("#2a2018")
		1: wool = Color("#d4c89a"); face = Color("#1e1808")
		2: wool = Color("#909090"); face = Color("#202020")
		_: wool = Color("#eeeae0"); face = Color("#2a2018")
	var leg_dark := face
	draw_circle(Vector2(0, 18), 24, Color(0, 0, 0, 0.15))
	for bv in animal.wool_blobs:
		draw_circle(bv, 12.0, wool)
	draw_circle(Vector2(26, -4), 11, face)
	draw_custom_ellipse(Vector2(19, 5), Vector2(4, 7), face.lightened(0.2))
	draw_custom_ellipse(Vector2(34, 5), Vector2(4, 7), face.lightened(0.2))
	draw_circle(Vector2(33, -1), 4, face.lightened(0.25))
	draw_circle(Vector2(31, -1), 1.5, Color("#10151d"))
	draw_circle(Vector2(35, -1), 1.5, Color("#10151d"))
	draw_circle(Vector2(30, -7), 2.2, Color("#f8f0d0"))
	draw_circle(Vector2(30, -7), 1.2, Color("#10151d"))
	if animal.fear > 0.2:
		draw_circle(Vector2(30, -7), 5, Color.WHITE, false, 1.5)
	var kick: float = sin(animal.phase) * (5.0 if animal.airborne else 1.5)
	draw_line(Vector2(-12, 12), Vector2(-12 + kick, 26), leg_dark, 4)
	draw_line(Vector2(4, 13), Vector2(4 - kick, 27), leg_dark, 4)
	draw_line(Vector2(14, 12), Vector2(14 + kick, 26), leg_dark, 4)
	draw_line(Vector2(-2, 13), Vector2(-2 - kick, 27), leg_dark, 4)
	draw_circle(Vector2(-4, -16), 4, wool)
	draw_circle(Vector2(8, -17), 4, wool)

func _draw_chicken(animal: Dictionary) -> void:
	var feathers: Color; var dark: Color
	match animal.feather_color:
		0: feathers = Color("#f0ede0"); dark = Color("#c8c0a0")
		1: feathers = Color("#c87830"); dark = Color("#804818")
		2: feathers = Color("#282828"); dark = Color("#101010")
		_: feathers = Color("#f0ede0"); dark = Color("#c8c0a0")
	var orange := Color("#e87820")
	var red := Color("#d02020")
	draw_circle(Vector2(0, 12), 16, Color(0, 0, 0, 0.15))
	draw_line(Vector2(-18, -2), Vector2(-28, -14), dark, 3)
	draw_line(Vector2(-18, 0), Vector2(-30, -6), dark, 3)
	draw_line(Vector2(-18, 3), Vector2(-28, 6), dark, 2)
	draw_custom_ellipse(Vector2.ZERO, Vector2(18, 11), feathers)
	draw_custom_ellipse(Vector2(-4, 2), Vector2(12, 7), dark)
	draw_circle(Vector2(18, -9), 9, feathers)
	draw_circle(Vector2(15, -18), 4, red)
	draw_circle(Vector2(19, -20), 4, red)
	draw_circle(Vector2(23, -18), 3.5, red)
	draw_circle(Vector2(22, -5), 3, red)
	draw_colored_polygon(PackedVector2Array([Vector2(24, -10), Vector2(32, -8), Vector2(24, -6)]), orange)
	draw_circle(Vector2(21, -11), 2.5, Color("#10151d"))
	draw_circle(Vector2(22, -12), 1.0, Color(1, 1, 1, 0.6))
	if animal.fear > 0.2:
		draw_circle(Vector2(21, -11), 5, Color.WHITE, false, 1.5)
	var kick: float = sin(animal.phase) * (5.0 if animal.airborne else 2.0)
	draw_line(Vector2(4, 9), Vector2(2 + kick, 20), orange, 3)
	draw_line(Vector2(10, 9), Vector2(12 - kick, 20), orange, 3)
	draw_line(Vector2(2 + kick, 20), Vector2(-2 + kick, 25), orange, 2)
	draw_line(Vector2(2 + kick, 20), Vector2(6 + kick, 25), orange, 2)
	draw_line(Vector2(12 - kick, 20), Vector2(8 - kick, 25), orange, 2)
	draw_line(Vector2(12 - kick, 20), Vector2(16 - kick, 25), orange, 2)

func draw_custom_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)

func draw_4star(center: Vector2, size: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := i * TAU / 8 - PI / 2
		var r := size if i % 2 == 0 else size * 0.38
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)

func draw_crescent_moon(center: Vector2, size: float, tilt: float, color: Color) -> void:
	draw_circle(center, size, color)
	draw_circle(center + Vector2(cos(tilt), sin(tilt)) * size * 0.58, size * 0.8, Color("#060e1c"))

func draw_mini_planet(center: Vector2, size: float, col: Color, ring_col: Color) -> void:
	draw_circle(center, size, col)
	draw_circle(center + Vector2(-size * 0.3, -size * 0.3), size * 0.38, col.lightened(0.35))
	var ring_pts := PackedVector2Array()
	for i in 28:
		var a := i * TAU / 28
		ring_pts.append(center + Vector2(cos(a) * size * 1.95, sin(a) * size * 0.42))
	ring_pts.append(ring_pts[0])
	draw_polyline(ring_pts, ring_col, 1.8)

func draw_particle(p: Dictionary) -> void:
	var alpha: float = clampf(p.life / p.max_life, 0, 1)
	var radius := 3.0 if p.kind == "dust" else 4.0
	draw_circle(p.pos, radius * alpha + 1, Color(p.color, alpha))

func draw_title() -> void:
	draw_panel(Rect2(286, 75, 580, 470), Color(0.025, 0.07, 0.14, 0.78))
	draw_centered("UDDER SPACE", 132, 54, Color("#e8ff77"))
	draw_centered("A CLOSE ENCOUNTER OF THE HERD KIND", 184, 18, Color("#9ce8d5"))
	draw_centered("ABDUCT AS MANY ANIMALS AS YOU CAN", 342, 22, Color.WHITE)
	draw_centered("ARROW KEYS / WASD  •  MOVE", 390, 18, Color("#b8c8cf"))
	draw_centered("HOLD SPACE OR LEFT CLICK  •  TRACTOR BEAM", 424, 18, Color("#b8c8cf"))
	draw_centered("CHICKEN 200  PIG 150  COW 100  SHEEP 75", 458, 15, Color("#9ce8d5"))
	var pulse := 0.78 + sin(title_bob * 4) * 0.22
	draw_centered("PRESS SPACE TO INVADE", 494, 24, Color(0.9, 1, 0.45, pulse))
	draw_centered("PRESS S FOR UFO SHOP  •  COINS: %d" % coins, 524, 16, Color("#ffd740"))

func draw_hud() -> void:
	draw_panel(Rect2(25, 22, 315, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(45, 52), "ABDUCTED  %02d" % captured, 21, Color("#dffb78"))
	draw_text(Vector2(45, 80), "COMBO  x%d" % maxi(1, combo), 17, Color("#8fe8d1"))
	draw_text(Vector2(220, 80), "SCORE  %06d" % score, 17, Color.WHITE)
	draw_panel(Rect2(W - 260, 22, 235, 72), Color(0.02, 0.06, 0.12, 0.78))
	draw_text(Vector2(W - 240, 52), "TIME", 18, Color("#9eb4c0"))
	var time_color := Color("#ff6b69") if time_left < 10 else Color.WHITE
	draw_text(Vector2(W - 158, 56), "%02d" % ceili(time_left), 34, time_color)
	draw_text(Vector2(W - 240, 81), "BEAM", 15, Color("#9eb4c0"))
	draw_rect(Rect2(W - 180, 69, 125, 12), Color("#20313b"), true)
	draw_rect(Rect2(W - 178, 71, 121 * beam_energy / 100.0, 8), Color("#caff63"), true)
	draw_text(Vector2(W - 240, 20), "COINS  %d" % coins, 14, Color("#ffd740"))

func draw_game_over() -> void:
	draw_panel(Rect2(306, 90, 540, 460), Color(0.025, 0.07, 0.14, 0.9))
	draw_centered("MISSION COMPLETE", 152, 38, Color("#e8ff77"))
	draw_centered("THE FARMERS ARE VERY CONFUSED.", 196, 18, Color("#9ce8d5"))
	draw_centered("%d" % captured, 290, 72, Color.WHITE)
	draw_centered("ANIMALS LIBERATED", 328, 17, Color("#9eb4c0"))
	draw_centered("SCORE  %06d" % score, 376, 25, Color("#e8ff77"))
	draw_centered("BEST COMBO  x%d" % best_combo, 412, 18, Color("#9ce8d5"))
	draw_centered("COINS  %d  ★" % coins, 448, 20, Color("#ffd740"))
	draw_centered("PRESS SPACE TO RAID AGAIN", 490, 21, Color.WHITE)
	draw_centered("PRESS S FOR UFO SHOP", 518, 17, Color("#ffd740"))

func draw_store() -> void:
	draw_panel(Rect2(260, 300, 632, 318), Color(0.02, 0.05, 0.13, 0.96))
	draw_centered("UFO UPGRADE SHOP", 336, 28, Color("#e8ff77"))
	draw_centered("COINS  %d  ★" % coins, 368, 18, Color("#ffd740"))

	for i in STORE_ITEMS.size():
		var item: Dictionary = STORE_ITEMS[i]
		var row_y := 398 + i * 46
		var is_selected := i == store_cursor
		var is_owned: bool = item.id in owned_decorations
		var is_active: bool = item.id in active_decorations

		if is_selected:
			draw_rect(Rect2(268, row_y - 22, 616, 42), Color(0.08, 0.25, 0.14, 0.55), true)
			draw_rect(Rect2(268, row_y - 22, 616, 42), Color("#caff63", 0.35), false, 1.5)

		var name_color := Color("#e8ff77") if is_selected else Color("#d0e8e0")
		draw_text(Vector2(300, row_y), item.name, 20, name_color)
		draw_text(Vector2(300, row_y + 16), item.desc, 13, Color("#607888"))

		if is_active:
			draw_text(Vector2(790, row_y + 4), "EQUIPPED", 17, Color("#caff63"))
		elif is_owned:
			draw_text(Vector2(790, row_y + 4), "EQUIP", 17, Color("#9ce8d5"))
		else:
			var can_afford: bool = coins >= int(item.cost)
			var cost_color := Color("#ffd740") if can_afford else Color("#886644")
			draw_text(Vector2(790, row_y + 4), "%d ★" % item.cost, 18, cost_color)

	draw_centered("UP/DOWN: SELECT     SPACE: BUY / EQUIP     ESC: BACK", 604, 15, Color("#506878"))

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
