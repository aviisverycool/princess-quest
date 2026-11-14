extends Node2D
# PRINCESS QUEST: THE DARK CASTLE
# A tiny 8-bit top-down dungeon crawler with a horror twist. Everything is drawn in code.
# Level 1: light every torch to open the door (no weapon, avoid the ghosts!)
# Level 2: grab the sword, find the key, open the door
# Level 3: defeat the Dark King and rescue the princess...
#
# Legend: # wall  . floor  P start  T torch  e ghost  B boss  S sword  K key  D door  Q princess
 
const T := 16
const OFF_Y := 2

const LEVELS := [
	[
		"####################",
		"#P.......#........D#",
		"#.........#........#",
		"#...##.......##....#",
		"#T..##.......##...T#",
		"#..................#",
		"#.......O5..........#",
		"#...##.......##....#",
		"#...##.......##....#",
		"#.......T.....T....#",
		"####################",
	],
	[
		"####################",
		"#P.S....#.........K#",
		"#.......#.....e....#",
		"#..###.......###...#",
		"#..#...........#...#",
		"#....e.........e...#",
		"#..#...........#...#",
		"#..###.......###...#",
		"#..........e.......#",
		"#.......#.........D#",
		"####################",
	],
	[
		"####################",
		"#P................T#",
		"#..##.........##...#",
		"#..##.........##...#",
		"#..................#",
		"#.......e....B...Q.#",
		"#..................#",
		"#..##.........##...#",
		"#..##.....e...##...#",
		"#T.................#",
		"####################",
	],
]

const HINTS := ["Light all the torches.", "Find the sword. Find the key.", "Save the princess."]
const BASE_RADIUS := [46.0, 58.0, 64.0]
const BOUNCE := 1.5        # how hard you rebound (1.0 = same speed, higher = stronger)
const KNOCK_DECAY := 200.0 # how fast the bounce fades

var knock := Vector2.ZERO
var knock2 := Vector2.ZERO
var grid: Array = []
var torches: Array = []
var enemies: Array = []
var player := Vector2.ZERO
var face := Vector2(0, 1)
var sword_pos := Vector2(-100, -100)
var key_pos := Vector2(-100, -100)
var princess_pos := Vector2(-100, -100)
var door_tile := Vector2i(-1, -1)
var player2 := Vector2.ZERO
var face2 := Vector2(0, 1)
var dual := false
var portals: Array = []
var level := 1
var hp := 3
var inv := 0.0
var atk_t := 0.0
var atk_cd := 0.0
var has_sword := false
var has_key := false
var exit_open := false
var boss_dead := false
var state := "title"  # title, play, dead, win
var state_t := 0.0
var time := 0.0
var flicker := 0.0
var radius := 46.0
var shake_t := 0.0
var glitch_t := 0.0
var msg := ""
var msg_t := 0.0
var ui_font: Font

func _ready() -> void:
	randomize()
	# Clean serif font from the system (falls back automatically if one is missing)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "Times New Roman", "serif"])
	f.font_weight = 700
	ui_font = f
	load_level(1)

# Draws smooth text with a soft shadow so it stays readable on dark tiles
func txt(pos: Vector2, text: String, align: int, width: float, size: int, col: Color) -> void:
	draw_string(ui_font, pos + Vector2(0.7, 0.7), text, align, width, size, Color(0, 0, 0, 0.85))
	draw_string(ui_font, pos, text, align, width, size, col)

func say(text: String) -> void:
	msg = text
	msg_t = 2.5

func load_level(n: int) -> void:
	level = n
	grid.clear()
	torches.clear()
	enemies.clear()
	sword_pos = Vector2(-100, -100)
	key_pos = Vector2(-100, -100)
	princess_pos = Vector2(-100, -100)
	door_tile = Vector2i(-1, -1)
	has_sword = (n == 3)
	has_key = false
	exit_open = false
	boss_dead = false
	hp = 3
	inv = 0.0
	atk_t = 0.0
	atk_cd = 0.0
	radius = BASE_RADIUS[n - 1]
	var rows: Array = LEVELS[n - 1]
	for y in rows.size():
		var row: String = rows[y]
		var cells: Array = []
		for x in row.length():
			var c: String = row[x]
			var center := Vector2(x * T + T / 2.0, y * T + T / 2.0 + OFF_Y)
			match c:
				"P":
					player = center
					c = "."
				"T":
					torches.append({"pos": center, "lit": n == 3})
					c = "."
				"e":
					enemies.append(make_enemy(center, false))
					c = "."
				"B":
					enemies.append(make_enemy(center, true))
					c = "."
				"S":
					sword_pos = center
					c = "."
				"K":
					key_pos = center
					c = "."
				"Q":
					princess_pos = center
					c = "."
				"D":
					door_tile = Vector2i(x, y)
				"O":
					portals.append(center)
					c = "."
			cells.append(c)
		grid.append(cells)
	say(HINTS[n - 1])

func make_enemy(p: Vector2, boss: bool) -> Dictionary:
	return {"pos": p, "hp": 8 if boss else 1, "boss": boss, "dir": Vector2.ZERO, "t": 0.0, "flash": 0.0}

# ---------------------------------------------------------------- collision
func is_solid(tx: int, ty: int) -> bool:
	if ty < 0 or ty >= grid.size() or tx < 0 or tx >= grid[0].size():
		return true
	var c: String = grid[ty][tx]
	if c == "#":
		return true
	if c == "D" and not exit_open:
		return true
	return false

func can_stand(p: Vector2, half: float) -> bool:
	for ox in [-half, half]:
		for oy in [-half, half]:
			var tx := int(floor((p.x + ox) / T))
			var ty := int(floor((p.y + oy - OFF_Y) / T))
			if is_solid(tx, ty):
				return false
	return true

func move_body(p: Vector2, step: Vector2, half: float) -> Vector2:
	var np := p
	if step.x != 0.0 and can_stand(Vector2(p.x + step.x, p.y), half):
		np.x += step.x
	if step.y != 0.0 and can_stand(Vector2(np.x, p.y + step.y), half):
		np.y += step.y
	return np
func move_bounce(p: Vector2, walk: Vector2, knock_in: Vector2, delta: float, half: float) -> Array:
	var v := walk + knock_in
	var k := knock_in
	var np := p
	if v.x != 0.0:
		if can_stand(Vector2(np.x + v.x * delta, np.y), half):
			np.x += v.x * delta
		else:
			k.x = -v.x * BOUNCE
	if v.y != 0.0:
		if can_stand(Vector2(np.x, np.y + v.y * delta), half):
			np.y += v.y * delta
		else:
			k.y = -v.y * BOUNCE
	k = k.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	return [np, k]
func active_players() -> Array:
	return [player, player2] if dual else [player]

func near(p: Vector2, d: float) -> bool:
	for pl in active_players():
		if pl.distance_to(p) < d:
			return true
	return false

func nearest_index(p: Vector2) -> int:
	if dual and player2.distance_to(p) < player.distance_to(p):
		return 1
	return 0
# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_SPACE or k == KEY_ENTER:
			if state == "title":
				state = "play"
			elif state == "play":
				attack()
		elif k == KEY_R:
			if state == "dead":
				load_level(level)
				state = "play"
			elif state == "win":
				load_level(1)
				state = "play"

func attack() -> void:
	if not has_sword or atk_cd > 0.0:
		return
	atk_t = 0.18
	atk_cd = 0.35
	swing(player, face)
	if dual:
		swing(player2, face2)
func swing(pos: Vector2, f: Vector2) -> void:
	var hit_center := pos + f * 10.0

	var box := Rect2(hit_center - Vector2(8, 8), Vector2(16, 16))
	for e in enemies.duplicate():
		var ep: Vector2 = e["pos"]
		if box.has_point(ep) or ep.distance_to(hit_center) < 9.0:
			e["hp"] = int(e["hp"]) - 1
			e["flash"] = 0.15
			for i in 6:
				e["pos"] = move_body(e["pos"], face * 1.5, 3.0)
			if int(e["hp"]) <= 0:
				enemies.erase(e)
				if e["boss"]:
					boss_dead = true
					say("The Dark King falls.")
					shake_t = 0.5

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	time += delta
	state_t += delta
	if msg_t > 0.0:
		msg_t -= delta
	if shake_t > 0.0:
		shake_t -= delta
	if state == "play":
		update_play(delta)
	queue_redraw()

func update_play(delta: float) -> void:
	inv = maxf(inv - delta, 0.0)
	atk_t = maxf(atk_t - delta, 0.0)
	atk_cd = maxf(atk_cd - delta, 0.0)
	for p in portals.duplicate():
		if not dual and player.distance_to(p) < 12.0:
			dual = true
			portals.erase(p)
			var spawn := Vector2(320.0 - player.x, player.y)
			player2 = spawn if can_stand(spawn, 3.0) else p
			say("Dual portal!")
	# movement
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
		if dir != Vector2.ZERO:
			if dir.x != 0.0:
				face = Vector2(signf(dir.x), 0)
		else:
			face = Vector2(0, signf(dir.y))

	var r1 := move_bounce(player, dir.normalized() * 60.0, knock, delta, 3.0)
	player = r1[0]
	knock = r1[1]

	if dual:
		var d2 := Vector2(-dir.x, dir.y)
		face2 = Vector2(-face.x, face.y)
		var r2 := move_bounce(player2, d2.normalized() * 60.0, knock2, delta, 3.0)
		player2 = r2[0]
		knock2 = r2[1]
	# light flicker
	if flicker > 0.0:
		flicker -= delta
	elif randf() < 0.5 * delta:
		flicker = randf_range(0.05, 0.2)
	if randf() < 0.15 * delta:
		glitch_t = 0.12
	glitch_t = maxf(glitch_t - delta, 0.0)

	# torches
	var lit := 0
	for t in torches:
		var tp: Vector2 = t["pos"]
		if not t["lit"] and near(tp, 12.0):
			t["lit"] = true
			say("The torch flares.")
		if t["lit"]:
			lit += 1
	if level == 1 and not exit_open and lit == torches.size():
		exit_open = true
		say("A door grinds open...")
		shake_t = 0.4

	# pickups
	if player.distance_to(sword_pos) < 10.0:
		sword_pos = Vector2(-100, -100)
		has_sword = true
		say("A sword. Press Space to swing.")
	if player.distance_to(key_pos) < 10.0:
		key_pos = Vector2(-100, -100)
		has_key = true
		exit_open = true
		say("The door unlocks...")

	# enemies
	for e in enemies:
		update_enemy(e, delta)

	# door -> next level
	if exit_open and door_tile.x >= 0:
		var dc := Vector2(door_tile.x * T + T / 2.0, door_tile.y * T + T / 2.0 + OFF_Y)
		if player.distance_to(dc) < 12.0 and level < 3:
			load_level(level + 1)
			return

	# princess
	if level == 3 and boss_dead and player.distance_to(princess_pos) < 10.0:
		state = "win"
		state_t = 0.0

func update_enemy(e: Dictionary, delta: float) -> void:
	var boss: bool = e["boss"]
	var ep: Vector2 = e["pos"]
	var to_p := player - ep
	var dist := to_p.length()
	var speed := 30.0 if boss else 14.0 + 7.0 * level
	var step := Vector2.ZERO
	if dist < (999.0 if boss else 75.0):
		step = to_p.normalized() * speed * delta
	else:
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2.ZERO]
			e["dir"] = dirs[randi() % dirs.size()]
			e["t"] = randf_range(0.8, 2.0)
		var d: Vector2 = e["dir"]
		step = d * speed * 0.5 * delta
	var half := 6.0 if boss else 3.0
	var np := move_body(ep, step, half)
	if np.distance_to(ep) < 0.01 and step != Vector2.ZERO:
		np = move_body(ep, Vector2(-step.y, step.x), half)
	e["pos"] = np
	e["flash"] = maxf(float(e["flash"]) - delta, 0.0)
	if dist < (9.0 if boss else 6.0) and inv <= 0.0:
		hurt_player(ep,9 )

func hurt_player(from: Vector2, idx: int) -> void:
	hp -= 1
	inv = 1.2
	shake_t = 0.3
	var target: Vector2 = player if idx == 0 else player2
	var away := (target - from).normalized()
	for i in 8:
		if idx == 0:
			player = move_body(player, away * 1.5, 3.0)
		else:
			player2 = move_body(player2, away * 1.5, 3.0)
	if hp <= 0:
		state = "dead"
		state_t = 0.0

# ---------------------------------------------------------------- drawing helpers
func light_term(d: float, r: float) -> float:
	return pow(clampf(1.0 - d / r, 0.0, 1.0), 1.5)

func lum(p: Vector2) -> float:
	var r := radius * (250.0 if flicker > 0.0 else 250.0)
	var best := light_term(p.distance_to(player), r)
	if dual:
		best = maxf(best, light_term(p.distance_to(player2), r))
	for t in torches:
		if t["lit"]:
			var tp: Vector2 = t["pos"]
			best = maxf(best, light_term(p.distance_to(tp), 40.0))
	return best

func draw_ghost(p: Vector2, flash: float) -> void:
	var j := 1.0 if int(time * 6.0) % 2 == 0 else 0.0
	var col := Color(1, 1, 1) if flash > 0.0 else Color(0.78, 0.8, 0.9)
	draw_rect(Rect2(p.x - 4, p.y - 5 - j, 8, 9), col)
	draw_rect(Rect2(p.x - 4, p.y + 4 - j, 2, 2), col)
	draw_rect(Rect2(p.x, p.y + 4 - j, 2, 2), col)
	draw_rect(Rect2(p.x + 3, p.y + 4 - j, 1, 2), col)
	draw_rect(Rect2(p.x - 3, p.y - 3 - j, 2, 3), Color(0.8, 0, 0))
	draw_rect(Rect2(p.x + 1, p.y - 3 - j, 2, 3), Color(0.8, 0, 0))

func draw_boss(p: Vector2, flash: float, hp_left: int) -> void:
	var col := Color(1, 1, 1) if flash > 0.0 else Color(0.18, 0.05, 0.25)
	draw_rect(Rect2(p.x - 7, p.y - 7, 14, 15), col)
	draw_rect(Rect2(p.x - 8, p.y + 2, 2, 7), col)
	draw_rect(Rect2(p.x + 6, p.y + 2, 2, 7), col)
	draw_rect(Rect2(p.x - 7, p.y - 11, 14, 4), Color(0.9, 0.75, 0.1))  # crown
	draw_rect(Rect2(p.x - 7, p.y - 13, 2, 2), Color(0.9, 0.75, 0.1))
	draw_rect(Rect2(p.x - 1, p.y - 13, 2, 2), Color(0.9, 0.75, 0.1))
	draw_rect(Rect2(p.x + 5, p.y - 13, 2, 2), Color(0.9, 0.75, 0.1))
	draw_rect(Rect2(p.x - 5, p.y - 4, 3, 3), Color(1, 0.1, 0.1))
	draw_rect(Rect2(p.x + 2, p.y - 4, 3, 3), Color(1, 0.1, 0.1))
	for i in 5:
		draw_rect(Rect2(p.x - 5 + i * 2, p.y + 2, 1, 3), Color(0.9, 0.9, 0.9))
	draw_rect(Rect2(p.x - 8, p.y - 17, 16, 2), Color(0.3, 0, 0))
	draw_rect(Rect2(p.x - 8, p.y - 17, 16.0 * hp_left / 8.0, 2), Color(0.9, 0.1, 0.1))

func draw_princess(p: Vector2, red_eyes: bool) -> void:
	draw_rect(Rect2(p.x - 3, p.y - 1, 6, 6), Color(0.95, 0.5, 0.75))  # dress
	draw_rect(Rect2(p.x - 2, p.y - 5, 4, 4), Color(0.95, 0.8, 0.7))  # face
	draw_rect(Rect2(p.x - 3, p.y - 6, 1, 5), Color(0.9, 0.7, 0.2))  # hair
	draw_rect(Rect2(p.x + 2, p.y - 6, 1, 5), Color(0.9, 0.7, 0.2))
	draw_rect(Rect2(p.x - 2, p.y - 7, 4, 2), Color(1, 0.9, 0.2))  # crown
	var eye := Color(1, 0, 0) if red_eyes else Color.BLACK
	draw_rect(Rect2(p.x - 1, p.y - 3, 1, 1), eye)
	draw_rect(Rect2(p.x + 1, p.y - 3, 1, 1), eye)

func draw_hero(p: Vector2, f: Vector2, tunic: Color) -> void:
	if inv > 0.0 and int(time * 20.0) % 2 == 0:
		return
	draw_rect(Rect2(p.x - 3, p.y - 3, 6, 7), Color(0.3, 0.45, 0.95))  # tunic
	draw_rect(Rect2(p.x - 3, p.y - 6, 6, 4), Color(0.95, 0.8, 0.65))  # face
	draw_rect(Rect2(p.x - 3, p.y - 7, 6, 2), Color(0.7, 0.7, 0.75))  # helmet
	draw_rect(Rect2(p.x - 2, p.y - 4, 1, 1), Color.BLACK)
	draw_rect(Rect2(p.x + 1, p.y - 4, 1, 1), Color.BLACK)
	draw_rect(Rect2(p.x - 3, p.y + 4, 2, 1), Color(0.3, 0.2, 0.1))
	draw_rect(Rect2(p.x + 1, p.y + 4, 2, 1), Color(0.3, 0.2, 0.1))
	if atk_t > 0.0:
		var tip := p + face * 11.0
		var a := Vector2(minf(p.x + face.x * 4.0, tip.x), minf(p.y + face.y * 4.0, tip.y))
		var sz := Vector2(maxf(absf(tip.x - p.x) - 4.0, 2.0), maxf(absf(tip.y - p.y) - 4.0, 2.0))
		draw_rect(Rect2(a, sz), Color(0.9, 0.95, 1.0))
	elif has_sword:
		draw_rect(Rect2(p.x + 4, p.y - 1, 1, 5), Color(0.8, 0.85, 0.95))

# ---------------------------------------------------------------- main draw
func _draw() -> void:
	if state == "title":
		draw_rect(Rect2(0, 0, 320, 180), Color.BLACK)
		txt(Vector2(0, 50), "Princess Quest", HORIZONTAL_ALIGNMENT_CENTER, 320, 22, Color(1, 0.8, 0.3))
		txt(Vector2(0, 66), "The Dark Castle", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color(0.8, 0.2, 0.3))
		draw_princess(Vector2(160, 98), false)
		txt(Vector2(0, 125), "WASD or arrow keys to move   ·   Space to swing your sword", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color(0.6, 0.6, 0.6))
		if int(time * 2) % 2 == 0:
			txt(Vector2(0, 150), "Press Space to begin", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color.WHITE)
		return

	if state == "win":
		draw_win()
		return

	var shake := Vector2.ZERO
	if shake_t > 0.0:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 2.0
	draw_set_transform(shake, 0.0, Vector2.ONE)

	# tiles
	for y in grid.size():
		for x in grid[y].size():
			var r := Rect2(x * T, y * T + OFF_Y, T, T)
			var l := lum(r.position + Vector2(T / 2.0, T / 2.0))
			if l <= 0.0:
				continue
			var c: String = grid[y][x]
			var col: Color
			if c == "#":
				col = Color(0.5, 0.42, 0.5)
			elif c == "D":
				col = Color(0.95, 0.8, 0.2) if exit_open else Color(0.45, 0.22, 0.12)
			else:
				col = Color(0.3, 0.3, 0.36) if (x + y) % 2 == 0 else Color(0.25, 0.25, 0.31)
			draw_rect(r, Color(col.r * l, col.g * l, col.b * l))
			if c == "#":
				draw_rect(Rect2(r.position.x, r.position.y + 7, T, 1), Color(0, 0, 0, 0.4 * l))
				draw_rect(Rect2(r.position.x + 7, r.position.y, 1, 7), Color(0, 0, 0, 0.4 * l))
			elif c == "D":
				draw_rect(Rect2(r.position.x + 7, r.position.y, 2, T), Color(0, 0, 0, 0.4 * l))

	# torches
	for t in torches:
		var tp: Vector2 = t["pos"]
		draw_rect(Rect2(tp.x - 1, tp.y, 2, 6), Color(0.4, 0.25, 0.1))
		if t["lit"]:
			var f := 1.0 + 0.3 * sin(time * 14.0 + tp.x)
			draw_rect(Rect2(tp.x - 2, tp.y - 5, 4, 5), Color(1.0, 0.55 * f, 0.1))
			draw_rect(Rect2(tp.x - 1, tp.y - 3, 2, 3), Color(1.0, 0.95, 0.5))
		else:
			draw_rect(Rect2(tp.x - 2, tp.y - 4, 4, 4), Color(0.25, 0.25, 0.25) * maxf(lum(tp), 0.4))

	# pickups (dimly visible from afar)
	if sword_pos.x > 0:
		var g := maxf(lum(sword_pos), 0.5)
		draw_rect(Rect2(sword_pos.x - 1, sword_pos.y - 6, 2, 9), Color(0.8, 0.9, 1.0) * g)
		draw_rect(Rect2(sword_pos.x - 3, sword_pos.y + 2, 6, 2), Color(0.8, 0.6, 0.2) * g)
	if key_pos.x > 0:
		var g2 := maxf(lum(key_pos), 0.5)
		draw_rect(Rect2(key_pos.x - 3, key_pos.y - 3, 4, 4), Color(1, 0.85, 0.2) * g2)
		draw_rect(Rect2(key_pos.x, key_pos.y, 2, 5), Color(1, 0.85, 0.2) * g2)

	# princess (level 3)
	if princess_pos.x > 0:
		draw_princess(princess_pos, false)

	# enemies: seen in the light, only blinking red eyes in the dark
	for e in enemies:
		var ep: Vector2 = e["pos"]
		if lum(ep) > 0.04:
			if e["boss"]:
				draw_boss(ep, float(e["flash"]), int(e["hp"]))
			else:
				draw_ghost(ep, float(e["flash"]))
		elif int(time * 3.0) % 5 != 0:
			draw_rect(Rect2(ep.x - 3, ep.y - 3, 1, 1), Color(1, 0.1, 0.1))
			draw_rect(Rect2(ep.x + 2, ep.y - 3, 1, 1), Color(1, 0.1, 0.1))

	if state != "dead":
		draw_hero(player, face, Color(0.3, 0.45, 0.95))
	if dual:
		draw_hero(player2, face2, Color(0.95, 0.35, 0.35))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# scanlines + glitch
	for y in range(0, 180, 2):
		draw_rect(Rect2(0, y, 320, 1), Color(0, 0, 0, 0.18))
	if glitch_t > 0.0:
		for i in 3:
			draw_rect(Rect2(randf_range(-8, 8), randf_range(0, 180), 320, randf_range(1, 4)), Color(1, 0, 0.2, 0.25))

	# HUD
	for i in 3:
		var hc := Color(0.9, 0.1, 0.2) if i < hp else Color(0.25, 0.05, 0.08)
		draw_rect(Rect2(4 + i * 10, 4, 7, 6), hc)
	var info := ""
	if level == 1:
		var lit := 0
		for t in torches:
			if t["lit"]:
				lit += 1
		info = "Torches %d/%d" % [lit, torches.size()]
	elif level == 2:
		info = "Key: " + ("Yes" if has_key else "No")
	else:
		info = "The Dark King" if not boss_dead else "Go to her..."
	txt(Vector2(0, 10), "Level %d   ·   %s" % [level, info], HORIZONTAL_ALIGNMENT_RIGHT, 316, 10, Color(1, 0.8, 0.3))
	if msg_t > 0.0 and state == "play":
		txt(Vector2(0, 176), msg, HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color(0.9, 0.3, 0.3))

	if state == "dead":
		draw_rect(Rect2(0, 0, 320, 180), Color(0.1, 0, 0, 0.88))
		draw_rect(Rect2(128, 40, 12, 12), Color(1, 0.1, 0.1))
		draw_rect(Rect2(180, 40, 12, 12), Color(1, 0.1, 0.1))
		txt(Vector2(0, 110), "The darkness takes you.", HORIZONTAL_ALIGNMENT_CENTER, 320, 22, Color(0.9, 0.1, 0.1))
		txt(Vector2(0, 140), "Press R to try again", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color.WHITE)

func draw_win() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color.BLACK)
	var twist := state_t > 3.0
	for y in range(0, 180, 2):
		draw_rect(Rect2(0, y, 320, 1), Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2(160, 70), 0.0, Vector2(6, 6))
	draw_princess(Vector2.ZERO, twist)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not twist:
		txt(Vector2(0, 140), "You saved the princess!", HORIZONTAL_ALIGNMENT_CENTER, 320, 22, Color(1, 0.85, 0.3))
	else:
		txt(Vector2(0, 135), "She smiles.", HORIZONTAL_ALIGNMENT_CENTER, 320, 22, Color(0.9, 0.1, 0.1))
		txt(Vector2(0, 150), "Something is wrong.", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color(0.7, 0.7, 0.7))
		txt(Vector2(0, 170), "Press R to play again", HORIZONTAL_ALIGNMENT_CENTER, 320, 10, Color.WHITE)
