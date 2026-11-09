extends Control
const Face = preload("res://scripts/ui/card_face.gd")
const Audio = preload("res://scripts/ui/frontline_audio.gd")
const DrawCard = preload("res://scripts/ui/battle_draw_card.gd")
const HandLayout = preload("res://scripts/ui/battle_hand_layout.gd")
const DRAW_LIFT := 0.34
const DRAW_LAND := 0.34
## Visual playback of public events. Never writes to the authoritative snapshot.
signal finished
var elapsed := 0.0
var duration := 0.0
var jobs: Array = []
var motions: Array = []
var ghosts: Array = []
var ghost_origins: Dictionary = {}
var reveals: Array = []
var reveal_jobs: Array = []
var draw_jobs: Array = []
var running := false
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 70
	font = get_theme_default_font()

func play(events: Array, faces: Dictionary, previous: Dictionary, removed: Array, local_player: int, draw_context: Dictionary = {}) -> void:
	elapsed = 0.0
	duration = 0.0
	jobs.clear()
	motions.clear()
	draw_jobs.clear()
	var audio := Audio.service(self)
	var animate_draws: bool = draw_context.get("enabled",true) and (audio == null or audio.preferences.animations)
	var received: Array = []
	ghosts = removed
	ghost_origins.clear()
	for ghost in ghosts: ghost_origins[ghost.get_instance_id()] = ghost.position
	for key in faces:
		var node: Control = faces[key]
		var end: Vector2 = node.position
		var start: Vector2 = previous[key].position if previous.has(key) else end
		if not previous.has(key):
			if key.begins_with("h:"):
				if animate_draws: received.append(node)
				else: jobs.append({"kind":"sound","at":0.02,"sound":"draw","media":node.spec.get("media",{}),"cue":"draw"})
			elif key.begins_with("u:"):
				start = Vector2(size.x/2-Face.FIELD_BODY.x*0.6,-150 if node.enemy else size.y-95)
				if not node.enemy:
					for old_key in previous:
						if old_key.begins_with("h:") and not faces.has(old_key) and previous[old_key].name==str(node.spec.get("name","")):
							start = previous[old_key].position
							if previous[old_key].get("released",false):break
		var fresh: bool = not previous.has(key) and not key.begins_with("h:")
		motions.append({"node":node,"start":start,"end":end,"rotation":node.rotation,"start_rotation":float(previous.get(key,{}).get("rotation",node.rotation)),"start_scale":previous.get(key,{}).get("scale",Vector2.ONE*0.88 if fresh else Vector2.ONE),"fresh":fresh,"hp":node.current_health if node is CardFace else node.value})
		if not start.is_equal_approx(end) or fresh: duration = 0.24
		if previous.has(key):
			if node is CardFace: node.current_health = previous[key].hp
			else: node.value = previous[key].hp
	var cursor := 0.02
	var impact := cursor
	for event in events:
		var kind := str(event.kind)
		var key := "u:%d" % int(event.get("target_uid",event.get("uid",-999)))
		if event.has("target_owner") and int(event.get("target_uid",-999)) < 0: key = "hq:%d" % int(event.target_owner)
		if kind == "attack":
			var source_key := "u:%d" % int(event.get("source_uid",-999))
			if int(event.get("target_uid",0)) < 0: key = "hq:%d" % (1-int(event.owner))
			var source := _node(source_key,faces)
			var target := _node(key,faces)
			if is_instance_valid(source) and is_instance_valid(target):
				jobs.append({"kind":"attack","at":cursor,"sound":"attack","media":source.spec.get("media",{}),"cue":"attack","source":source,"target":target,"from":_visual_center(source),"to":_visual_center(target),"ranged":source is CardFace and source.spec.get("unit_class","") in ["artillery","fighter","bomber"]})
			impact = cursor + 0.12
			cursor += 0.28
		elif kind in ["damage","heal","death","destroy"]:
			if kind == "death": key = "u:%d" % int(event.get("uid",-999))
			var target := _node(key,faces)
			if is_instance_valid(target):
				jobs.append({"kind":kind,"at":impact,"sound":"death" if kind=="destroy" else kind,"media":target.spec.get("media",{}) if target is CardFace else {},"cue":"death" if kind=="destroy" else kind,"target":target,"position":_visual_center(target),"amount":int(event.get("amount",0)),"applied":false})
		elif kind in ["deploy","generated_deploy","summon","move"]:
			jobs.append({"kind":"sound","at":minf(cursor+0.18,2.0),"sound":"move" if kind=="move" else "deploy","media":event.get("media",{}),"cue":"move" if kind=="move" else "play"})
		elif kind=="veteran":
			jobs.append({"kind":"caption","at":cursor,"text":str(event.name)+" · 老兵"})
			jobs.append({"kind":"sound","at":cursor,"sound":"card","media":event.get("media",{}),"cue":"trigger"})
			cursor+=0.20
		elif kind=="trigger":
			if event.get("media",{}).get("sounds",{}).has("trigger"): jobs.append({"kind":"sound","at":cursor,"sound":"card","media":event.media,"cue":"trigger"})
		elif kind in ["counter_reveal","play","generated_play","turn_start"]:
			if kind in ["play","generated_play"] and event.get("card_kind") == "unit": continue
			var caption := str(event.get("name",""))
			if kind == "counter_reveal": caption = "反制 · " + caption
			if kind == "turn_start": caption = "你的回合" if int(event.owner)==local_player else "对手回合"
			jobs.append({"kind":"sound","at":cursor,"sound":"counter" if kind=="counter_reveal" else ("turn" if kind=="turn_start" else "order"),"media":event.get("media",{}),"cue":"play"})
			if event.has("display_card") and (event.get("card_kind") in ["order","field"] or kind=="counter_reveal"):
				var face:=Face.new()
				face.spec=event.display_card.definition.duplicate(true)
				face.art_id=str(event.display_card.get("art_id",""))
				face.use_tooltip=false
				face.mouse_filter=Control.MOUSE_FILTER_IGNORE
				face.focus_mode=Control.FOCUS_NONE
				face.custom_minimum_size=Face.full_size(_reveal_width())
				face.size=Face.full_size(_reveal_width())
				add_child(face)
				face.pivot_offset=face.size*0.5
				face.modulate.a=0.0
				reveals.append(face)
				jobs.append({"kind":"reveal","at":cursor,"face":face,"friendly":int(event.owner)==local_player})
				reveal_jobs.append({"face":face,"friendly":int(event.owner)==local_player,"age":-cursor})
				impact=cursor+0.16
				cursor+=0.24
			else:
				if not caption.is_empty(): jobs.append({"kind":"caption","at":cursor,"text":caption})
				cursor += 0.20
		# A long resolution remains bounded; the final snapshot is always authoritative.
		cursor = minf(cursor,2.0)
		impact = minf(impact,2.0)
	for job in jobs:
		var tail := 0.0
		match job.kind:
			"reveal": tail = 0.32
			"attack": tail = 0.32
			"damage", "heal": tail = 0.32
			"caption": tail = 0.38
			"death", "destroy": tail = 0.28
		duration = maxf(duration,float(job.at)+tail)
	var hand_removed := previous.keys().any(func(key):return str(key).begins_with("h:") and not faces.has(key))
	_prepare_draws(received,draw_context,hand_removed)
	# Playing/discarding a card closes the fan with the same gentle endpoints.
	for motion in motions:
		if motion.node is CardFace and motion.node.hand_mode and not motion.has("hand_steps"):
			var seconds := 0.30 if audio == null or audio.preferences.animations else 0.0
			if seconds == 0.0:
				motion.start = motion.end; motion.start_rotation = motion.rotation; motion.start_scale = Vector2.ONE
			motion["hand_steps"] = [{"at":0.0,"length":seconds,"from":{"position":motion.start,"rotation":motion.start_rotation,"scale":motion.start_scale},"to":{"position":motion.end,"rotation":motion.rotation,"scale":Vector2.ONE}}]
			if not motion.start.is_equal_approx(motion.end) or not is_equal_approx(motion.start_rotation,motion.rotation) or not motion.start_scale.is_equal_approx(Vector2.ONE): duration = maxf(duration,seconds)
	# The opponent's snapshot provides only card backs and a count. Never build
	# a reveal from opponent definitions, including partially revealed hands.
	for hidden in draw_context.get("hidden",[]):
		var node: Control = hidden.node
		motions.append({"node":node,"start":hidden.start,"end":node.position,"rotation":node.rotation,"start_rotation":hidden.rotation,"start_scale":Vector2.ONE,"fresh":hidden.fresh,"hp":node.value})
		if hidden.fresh or not node.position.is_equal_approx(hidden.start): duration = maxf(duration,0.24)
	for motion in motions:
		motion.node.position = motion.start
		motion.node.rotation = motion.start_rotation
		motion.node.scale = motion.start_scale
		if motion.fresh:
			motion.node.modulate.a = 0.0
			motion.node.scale = Vector2.ONE*0.88
		if motion.has("draw"):
			motion.node.modulate.a = 0.0
	running = true
	# Status-only snapshots do not invent an animation or block the next action.
	if duration <= 0.0: finish()

func _prepare_draws(received: Array, context: Dictionary, hand_removed := false) -> void:
	if received.is_empty(): return
	var at := duration + 0.03
	var hold := 0.56 if received.size()==1 else 0.22
	var origin: Rect2 = context.get("deck",Rect2(size-Vector2(208,179),Vector2(95,137)))
	for index in received.size():
		var node: CardFace = received[index]
		var display := DrawCard.new()
		add_child(display)
		display.configure(node,str(context.get("sin","")))
		display.visible = false
		var body := node.card_body_rect()
		var target_center := node.get_transform()*(node.size*0.5)
		var magnification := minf(264.0/node.size.x,(size.y-210.0)/node.size.y)
		var job := {"node":node,"display":display,"at":at,"hold":hold,"length":DRAW_LIFT+hold+DRAW_LAND,"from":origin.get_center(),"center":Vector2(size.x/2.0,size.y/2.0-24.0),"to":target_center,"from_scale":origin.size.x/body.size.x,"scale":magnification,"rotation":node.rotation,"landed":false}
		draw_jobs.append(job)
		for motion in motions:
			if motion.node == node: motion["draw"] = job
		jobs.append({"kind":"sound","at":at,"sound":"draw","media":node.spec.get("media",{}),"cue":"draw"})
		node.set_meta("draw_hidden",true)
		duration = maxf(duration,at+float(job.length))
		# The next card turns up as this one leaves the reading position.
		at += DRAW_LIFT+hold
	_prepare_hand_arrivals(received,hand_removed)

func _prepare_hand_arrivals(received: Array, hand_removed := false) -> void:
	var hand: Array = motions.filter(func(m):return m.node is CardFace and m.node.hand_mode)
	if hand_removed:
		# Playing a draw order / replacing discarded cards must close the old
		# gap immediately, not freeze the fan until the reading display lands.
		var remaining: Array = hand.filter(func(m):return not m.node in received)
		for slot in remaining.size():
			var motion: Dictionary = remaining[slot]
			motion["hand_steps"] = [{"at":0.0,"length":0.30,"from":{"position":motion.start,"rotation":motion.start_rotation,"scale":motion.start_scale},"to":HandLayout.pose(slot,remaining.size(),size)}]
	for index in draw_jobs.size():
		var job: Dictionary = draw_jobs[index]
		var visible_hand: Array = hand.filter(func(m):return received.find(m.node)<=index)
		for slot in visible_hand.size():
			var motion: Dictionary = visible_hand[slot]
			var pose := HandLayout.pose(slot,visible_hand.size(),size)
			var steps: Array = motion.get_or_add("hand_steps",[])
			var before: Dictionary = {"position":motion.start,"rotation":motion.start_rotation,"scale":motion.start_scale} if steps.is_empty() else steps[-1].to
			if motion.node == job.node:
				# The new card lands in this arrival's fan, then moves with the
				# existing hand if more cards arrive later in the same batch.
				before = pose
				motion.start = pose.position
				motion.start_rotation = pose.rotation
				motion.start_scale = Vector2.ONE
				var half: Vector2 = motion.node.size*0.5
				var pivot: Vector2 = motion.node.pivot_offset
				job.to = pose.position+pivot+(half-pivot).rotated(pose.rotation)
				job.rotation = pose.rotation
			# Gently open the fan just before landing, with zero endpoint speed.
			# Both movements finish together, avoiding the old move-stop-land beat.
			steps.append({"at":job.at+DRAW_LIFT+job.hold-0.06,"length":DRAW_LAND+0.06,"from":before,"to":pose})

func _animate_hand_arrival(motion: Dictionary) -> void:
	for step in motion.hand_steps:
		if elapsed < float(step.at): break
		var t := 1.0 if step.length<=0 else clampf((elapsed-float(step.at))/float(step.length),0.0,1.0)
		var eased := t*t*(3.0-2.0*t)
		motion.node.position = step.from.position.lerp(step.to.position,eased)
		motion.node.rotation = lerp_angle(step.from.rotation,step.to.rotation,eased)
		motion.node.scale = step.from.scale.lerp(step.to.scale,eased)

func _animate_draws() -> void:
	for job in draw_jobs:
		var node: CardFace = job.node
		var display: Control = job.display
		if not is_instance_valid(node) or not is_instance_valid(display): continue
		var age: float = elapsed-job.at
		if age >= float(job.length):
			display.hide()
			node.modulate.a = 1.0
			node.set_meta("draw_hidden",false)
			job.landed = true
			continue
		node.modulate.a = 0.0
		display.visible = age >= 0.0
		if age < 0.0: continue
		display.sync_art(node)
		if age < DRAW_LIFT:
			var t := clampf(age/DRAW_LIFT,0,1)
			var eased := 1.0-pow(1.0-t,3)
			var center: Vector2 = job.from.lerp(job.center,eased)+Vector2(0,-38*sin(PI*t))
			display.pose(center,lerpf(job.from_scale,job.scale,eased),lerpf(-0.22,0.0,eased),t)
		elif age < DRAW_LIFT+float(job.hold):
			display.pose(job.center,job.scale,0.0,1.0)
		else:
			var t := clampf((age-DRAW_LIFT-float(job.hold))/DRAW_LAND,0,1)
			var eased := t*t*(3-2*t)
			display.pose(job.center.lerp(job.to,eased),lerpf(job.scale,1.0,eased),lerp_angle(0.0,job.rotation,eased),1.0)

func _clear_draws() -> void:
	for job in draw_jobs:
		if is_instance_valid(job.node):
			job.node.modulate.a = 1.0
			job.node.set_meta("draw_hidden",false)
		if is_instance_valid(job.display):
			job.display.hide()
			job.display.queue_free()
	draw_jobs.clear()

func _reveal_width() -> float:
	# Five 192px unit slots leave 244px at the left edge on the base board.
	# Taller reveals would cover the counter area / end-turn controls.
	return clampf(220.0+(size.x-1440.0)*0.25,180.0,232.0)

func _visual_center(node: Control) -> Vector2:
	return node.card_center_in_parent() if node is CardFace else node.get_transform()*(node.size*0.5)

func _node(key: String, faces: Dictionary) -> Control:
	if faces.has(key): return faces[key]
	for ghost in ghosts:
		if is_instance_valid(ghost) and ghost.get_meta("visual_key","")==key: return ghost
	return null

func finish() -> void:
	if not running: return
	running = false
	_clear_draws()
	for motion in motions:
		var node: Control = motion.node
		if not is_instance_valid(node): continue
		node.position = motion.end
		node.rotation = motion.rotation
		node.scale = Vector2.ONE
		node.modulate = Color.WHITE
		if node is CardFace: node.current_health = motion.hp
		else: node.value = motion.hp
		node.queue_redraw()
	for ghost in ghosts:
		if is_instance_valid(ghost):
			if ghost.get_parent()!=null: ghost.get_parent().remove_child(ghost)
			ghost.queue_free()
	ghosts.clear()
	ghost_origins.clear()
	jobs.clear()
	motions.clear()
	queue_redraw()
	finished.emit()

func _process(delta: float) -> void:
	_animate_reveals(delta)
	if not running: return
	elapsed += delta
	for motion in motions:
		var node: Control = motion.node
		if not is_instance_valid(node): continue
		if motion.has("hand_steps"):
			_animate_hand_arrival(motion)
			continue
		var t := clampf((elapsed-float(motion.get("at",0.0)))/0.24,0,1)
		node.position = motion.start.lerp(motion.end,1-pow(1-t,3))
		node.rotation=lerp_angle(motion.start_rotation,motion.rotation,1-pow(1-t,3))
		node.scale=motion.start_scale.lerp(Vector2.ONE,1-pow(1-t,3))
		if motion.fresh and node is CardFace and not node.hand_mode:
			node.scale*=1.0+0.022*sin(PI*clampf((elapsed-0.10)/0.14,0,1))
		node.modulate = Color(1,1,1,t if motion.fresh else 1.0)
	# Dead units also need a stable baseline; otherwise per-frame offsets accumulate.
	for ghost in ghosts:
		if is_instance_valid(ghost):
			ghost.position = ghost_origins[ghost.get_instance_id()]
			ghost.modulate = Color.WHITE
	for job in jobs:
		var age: float = elapsed-job.at
		if age < 0: continue
		if job.has("sound") and not job.get("sounded",false):
			job["sounded"] = true
			Audio.card_cue(self,job.get("cue",job.sound),job.get("media",{}),job.sound)
		if job.kind == "attack" and age < 0.32:
			var node: Control = job.source
			if is_instance_valid(node):
				var strength := _strike_envelope(age)
				var direction: Vector2 = (job.to-job.from).normalized()
				node.position += direction * strength * (-12.0 if job.ranged else minf(96.0,job.from.distance_to(job.to)*0.34))
		elif job.kind in ["damage","heal","death","destroy"]:
			var node: Control = job.target
			if not is_instance_valid(node): continue
			if not job.applied:
				job.applied = true
				if job.kind in ["damage","heal"]:
					var amount: int = job.amount * (1 if job.kind=="heal" else -1)
					if node is CardFace: node.current_health = maxi(0,node.current_health+amount)
					else: node.value = maxi(0,node.value+amount)
					node.queue_redraw()
			if job.kind in ["death","destroy"]:
				node.modulate.a = 1-clampf(age/0.28,0,1)
			elif age < 0.22:
				node.modulate = Color(1.55,0.82,0.68,1) if job.kind=="damage" else Color(0.75,1.4,0.8,1)
				node.position.x += sin(age*90)*5*(1-age/0.22)
	_animate_draws()
	for ghost in ghosts:
		if is_instance_valid(ghost): ghost.modulate.a = minf(ghost.modulate.a,1-clampf((elapsed-duration+0.25)/0.25,0,1))
	queue_redraw()
	if elapsed >= duration: finish()

func _draw() -> void:
	if not running or font == null: return
	for job in jobs:
		var age: float = elapsed-job.at
		if age < 0: continue
		if job.kind == "attack" and age < 0.18 and job.ranged:
			var t := clampf((age-0.03)/0.11,0,1)
			if t<=0: continue
			var head: Vector2 = job.from.lerp(job.to,t)
			var tail: Vector2 = job.from.lerp(job.to,maxf(0,t-0.18))
			draw_line(tail,head,Color(1,0.77,0.38,0.2),12,true)
			draw_line(tail,head,Color("ffe1a2"),3,true)
		elif job.kind in ["damage","heal","death","destroy"] and age < 0.32:
			var p: Vector2 = job.position
			var fade := 1-clampf((age-0.16)/0.16,0,1)
			var color := Color("96c987") if job.kind=="heal" else Color("eaa665")
			if age < 0.25:
				draw_circle(p,12+age*130,Color(color,0.18*(1-age/0.25)))
				for i in 10:
					var ray := Vector2.RIGHT.rotated(i*TAU/10+0.2)
					draw_line(p+ray*(8+age*75),p+ray*(20+age*170),Color(color,1-age/0.25),2,true)
			if job.kind in ["damage","heal"]:
				p.y -= 15+age*48
				var shield := PackedVector2Array([p+Vector2(-28,-25),p+Vector2(28,-25),p+Vector2(28,18),p+Vector2(0,33),p+Vector2(-28,18)])
				draw_colored_polygon(shield,Color(Color("527849") if job.kind=="heal" else Color("a83728"),fade))
				draw_polyline(PackedVector2Array([shield[0],shield[1],shield[2],shield[3],shield[4],shield[0]]),Color(0.95,0.84,0.63,fade),2,true)
				var value := ("+" if job.kind=="heal" else "−")+str(job.amount)
				var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
				draw_string(font,p+Vector2(-width/2,12),value,HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color(1,0.96,0.83,fade))
		elif job.kind=="caption" and age < 0.38:
			var alpha := minf(age/0.06,1)*minf((0.38-age)/0.12,1)
			var p := Vector2(size.x/2,size.y/2)
			draw_rect(Rect2(p-Vector2(300,39),Vector2(600,78)),Color(0.07,0.07,0.07,alpha*0.72))
			draw_line(p+Vector2(-280,-38),p+Vector2(280,-38),Color(0.7,0.7,0.7,alpha),1)
			var label: String = job.text
			var fs := 30
			while font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x>555 and fs>17: fs-=1
			var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
			draw_string(font,p+Vector2(-width/2,fs*0.35),label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color(0.95,0.95,0.95,alpha))

func _strike_envelope(age: float) -> float:
	# A short anticipation, decisive contact at 120 ms, then a soft return.
	if age<0.035:return -0.10*sin(age/0.035*PI*0.5)
	if age<0.12:return lerpf(-0.10,1.0,pow((age-0.035)/0.085,2))
	return pow(1.0-clampf((age-0.12)/0.18,0,1),3)

func _discard_reveal(job: Dictionary) -> void:
	reveal_jobs.erase(job)
	reveals.erase(job.face)
	if is_instance_valid(job.face):
		job.face.hide()
		job.face.queue_free()

func _animate_reveals(delta: float) -> void:
	# Side displays are cosmetic: reading them never holds up the next action.
	for job in reveal_jobs.duplicate():
		if not job in reveal_jobs:continue
		var before:float=job.age
		job.age+=delta
		if job.age<0:continue
		if before<0:
			for older in reveal_jobs.duplicate():
				if older!=job and older.age>=0 and older.friendly==job.friendly:_discard_reveal(older)
		var face:Control=job.face
		if not is_instance_valid(face) or job.age>=1.05:
			_discard_reveal(job);continue
		var age:float=job.age
		var enter:=1.0-pow(1.0-clampf(age/0.16,0,1),3)
		var leave:=clampf((age-0.80)/0.25,0,1)
		var width:=_reveal_width()
		face.custom_minimum_size=Face.full_size(width);face.size=Face.full_size(width)
		face.pivot_offset=face.size*0.5
		var direction:float=-1.0 if job.friendly else 1.0
		var side_x:float=16.0 if job.friendly else size.x-16.0-face.size.x
		face.position=Vector2(side_x,214.0+(size.y-900.0)*0.5)+Vector2(direction*((1-enter)*12+leave*12),0)
		face.scale=Vector2.ONE*lerpf(0.94,1.0,enter)
		face.modulate.a=enter*(1-leave)
