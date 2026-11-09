class_name BattleStage3D
extends Control
## A real lit world under the existing input layer. Screen-to-plane projection
## keeps hit targets, safe areas and authoritative game state independent of art.
const Face=preload("res://scripts/ui/card_face.gd")
const Prop=preload("res://scripts/ui/battle_props.gd")
const SurfaceShader=preload("res://assets/shaders/card_surface.gdshader")
const NormalMap=preload("res://assets/vendor/polyhaven/metal_plate_02_nor_gl_1k.jpg")
const RoughMap=preload("res://assets/vendor/polyhaven/metal_plate_02_rough_1k.jpg")
const MetalMap=preload("res://assets/vendor/polyhaven/metal_plate_02_diff_1k.jpg")
var menu_mode := false
var scene_id := ""
var viewport: SubViewport
var display: TextureRect
var world_root: Node3D
var scenery: Node3D
var camera: Camera3D
var environment: Environment
var light: DirectionalLight3D
var fill: OmniLight3D
var source_board: Control
var cards: Dictionary = {}
var capture_pool: Array = []
const CAPTURE_POOL_LIMIT := 8
var field_background: Texture2D
var field_material: StandardMaterial3D
var field_mesh: MeshInstance3D
var background_id := ""
var field_rect := Rect2(210,325,1020,215)
var front_owner := -1
var markers: Control
var elapsed := 0.0
var preset_data: Dictionary = {}
var _dirty := true
var _rendering := true
var _ambient: Node3D
var _sky_path := ""

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.transparent_bg=false
	viewport.handle_input_locally=false
	viewport.gui_disable_input=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size=1024
	add_child(viewport)
	display=TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter=Control.MOUSE_FILTER_IGNORE
	display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	display.texture=viewport.get_texture()
	add_child(display)
	world_root=Node3D.new();viewport.add_child(world_root)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.near=0.1;camera.far=260;camera.keep_aspect=Camera3D.KEEP_HEIGHT
	world_root.add_child(camera);camera.current=true
	var world_env:=WorldEnvironment.new();environment=Environment.new();world_env.environment=environment;world_root.add_child(world_env)
	light=DirectionalLight3D.new();world_root.add_child(light)
	light.shadow_enabled=BattleSceneCatalog.quality!="low"
	light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance=70
	# Thin card solids and a shallow tabletop need enough bias to avoid self-shadow hatching.
	light.shadow_bias=0.12;light.shadow_normal_bias=1.2
	fill=OmniLight3D.new();world_root.add_child(fill);fill.omni_range=50;fill.position=Vector3(12,11,-3)
	set_scene(scene_id)
	resized.connect(_resize)
	_resize()
	_rendering=DisplayServer.get_name()!="headless"
	# Keep texture painting in the process phase, before canvas draw commands flush.
	process_priority=100
	RenderingServer.frame_pre_draw.connect(_sync_transforms)
	RenderingServer.frame_post_draw.connect(_captures_drawn)

func set_scene(id: String) -> void:
	scene_id=str(BattleSceneCatalog.preset(id).id)
	if not is_instance_valid(viewport): return
	viewport.msaa_3d=Viewport.MSAA_8X if BattleSceneCatalog.quality=="high" else Viewport.MSAA_4X if BattleSceneCatalog.quality=="balanced" else Viewport.MSAA_2X
	light.shadow_enabled=BattleSceneCatalog.quality!="low"
	preset_data=BattleSceneCatalog.preset(scene_id)
	if is_instance_valid(scenery): world_root.remove_child(scenery);scenery.queue_free()
	scenery=Node3D.new();world_root.add_child(scenery)
	if environment.sky==null or _sky_path!=str(preset_data.hdri):
		var sky:=Sky.new()
		var panorama:=PanoramaSkyMaterial.new()
		panorama.panorama=load(preset_data.hdri)
		sky.sky_material=panorama;sky.radiance_size=Sky.RADIANCE_SIZE_256
		environment.sky=sky;_sky_path=str(preset_data.hdri)
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(preset_data.sky)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy=float(preset_data.ambient_energy)*(0.7 if menu_mode else 0.36)
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure=1.0
	environment.fog_enabled=menu_mode;environment.fog_light_color=Color(preset_data.horizon)
	environment.fog_light_energy=0.65;environment.fog_density=0.0025 if preset_data.room else 0.004
	light.light_color=Color(preset_data.key);light.light_energy=float(preset_data.key_energy)
	light.rotation_degrees=Vector3(-54,-24,0)
	fill.light_color=Color(preset_data.fill);fill.light_energy=0.8 if preset_data.room else 0.55
	camera.position=Vector3(16,14,30) if menu_mode else _v3(preset_data.camera)
	camera.look_at(Vector3(0,1,-14) if menu_mode else _v3(preset_data.camera_target))
	camera.size=35 if menu_mode else float(preset_data.camera_size)
	_build_world()
	_dirty=true

func _v3(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])
func _material(color: Color, metal := 0.0, rough := 0.75) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.metallic=metal;m.roughness=rough;return m
func _box(position: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=dimensions
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.position=position;scenery.add_child(node);return node
func _emission(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m:=_material(color,0.1,0.4);m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=energy;return m

func _build_world() -> void:
	var floor_mat:=ShaderMaterial.new();floor_mat.shader=preload("res://assets/shaders/table_surface.gdshader")
	floor_mat.set_shader_parameter("surface_color",Color(preset_data.table))
	floor_mat.set_shader_parameter("normal_texture",NormalMap);floor_mat.set_shader_parameter("roughness_texture",RoughMap)
	_box(Vector3(0,-1,0),Vector3(70,1,60),_material(Color("0d171e"),0.2))
	# The board is a raised physical metal surface, with a visible bevel/edge.
	_box(Vector3(0,-0.3,0),Vector3(38,0.5,33),_material(Color("101a22"),0.75,0.35))
	var tabletop:=_box(Vector3(0,-0.025,0),Vector3(37.7,0.05,32.7),floor_mat)
	tabletop.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim:=_material(Color("263c46"),0.52,0.52)
	# Tiny corner screws carry real highlights; keep the playable area quiet.
	for x in [-18.4,18.4]:
		for z in [-15.8,15.8]:
			var screw:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=0.08;cylinder.bottom_radius=0.08;cylinder.height=0.035;cylinder.radial_segments=12
			screw.mesh=cylinder;screw.material_override=rim;screw.position=Vector3(x,0.02,z);scenery.add_child(screw)
	_build_city()
	if bool(preset_data.room):
		var frame:=_material(Color("263641"),0.8,0.4)
		for x in [-27.0,-9.0,9.0,27.0]: _box(Vector3(x,9,-30),Vector3(0.24,23,0.3),frame)
		for y in [2.0,14.0,20.0]: _box(Vector3(0,y,-30),Vector3(74,0.18,0.3),frame)
		_box(Vector3(-24,12,-12),Vector3(0.1,0.06,28),_emission(Color("c7deea"),1.4))
	else:
		var rail:=_material(Color("314550"),0.7,0.5)
		for x in [-32.0,-24.0,-16.0,-8.0,0.0,8.0,16.0,24.0,32.0]: _box(Vector3(x,1.2,-24),Vector3(0.13,3,0.13),rail)
		_box(Vector3(0,2.6,-24),Vector3(74,0.13,0.13),rail)
		var rain:=CPUParticles3D.new()
		rain.amount=100 if BattleSceneCatalog.quality=="low" else 280
		rain.lifetime=1.8;rain.preprocess=1.8
		rain.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX;rain.emission_box_extents=Vector3(32,10,4)
		rain.direction=Vector3(-0.12,-1,0);rain.spread=4
		rain.initial_velocity_min=14;rain.initial_velocity_max=19;rain.gravity=Vector3(0,-4,0)
		var streak:=QuadMesh.new();streak.size=Vector2(0.012,0.7)
		var rain_material:=_material(Color(0.65,0.8,0.85,0.22))
		rain_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		rain_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
		rain_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		streak.material=rain_material;rain.mesh=streak;rain.position=Vector3(0,12,-25);scenery.add_child(rain)
	# An optional scene can furnish the same table without changing battle code.
	if preset_data.get("scene") is String and ResourceLoader.exists(preset_data.scene):
		var extra: Node=load(preset_data.scene).instantiate();scenery.add_child(extra)
	field_material=StandardMaterial3D.new();field_material.roughness=0.8
	field_mesh=_box(Vector3(0,0.012,0),Vector3(37.6,0.006,32.6),field_material)
	field_mesh.visible=field_background!=null
	if field_background!=null:field_material.albedo_texture=field_background

func _build_city() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=int(preset_data.city_seed)
	var model_names: Array=["building-skyscraper-a","building-skyscraper-b","building-skyscraper-c","building-skyscraper-d","building-skyscraper-e","building-f","building-h","building-j"]
	var instances:=Node3D.new();scenery.add_child(instances)
	for row in 3:
		for column in 11:
			if BattleSceneCatalog.quality=="low" and row>0:continue
			var path: String="res://assets/vendor/kenney-city/%s.glb"%model_names[(column+row*3)%model_names.size()]
			if not ResourceLoader.exists(path):continue
			var model: Node3D=load(path).instantiate();instances.add_child(model)
			var height:=rng.randf_range(4.8,9.5)
			model.scale=Vector3.ONE*height
			model.position=Vector3((column-5)*12.5+rng.randf_range(-2,2),-8,-45-row*22)
			model.rotation.y=PI if column%2 else 0.0
			_tint_building(model)
			# Window ribbons remain inexpensive emissive geometry, not dozens of lights.
			if not preset_data.room:
				var window:=_emission(Color("8dbac8") if column%3 else Color("d8b98f"),0.45)
				_box(Vector3(model.position.x+0.5,1.3+row*0.8,model.position.z+height*0.48),Vector3(height*0.65,0.07,0.03),window)

func _tint_building(node: Node) -> void:
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var original: Material=node.mesh.surface_get_material(index)
			if original is StandardMaterial3D:
				var material: StandardMaterial3D=original.duplicate()
				material.albedo_color=Color("98acb6") if preset_data.room else Color("4c6779")
				material.roughness=0.83
				node.set_surface_override_material(index,material)
	for child in node.get_children():_tint_building(child)

func _resize() -> void:
	if not is_instance_valid(viewport):return
	var pixels:=_render_pixel_size()
	if viewport.size==pixels:return
	viewport.size=pixels
	_dirty=true

func _render_pixel_size() -> Vector2i:
	# A 1440x900 canvas may be displayed at 2560x1600. Render the world at
	# the final window density instead of enlarging a low-resolution framebuffer.
	var screen:=get_viewport().get_screen_transform()*get_global_transform_with_canvas()
	var pixels:=size*Vector2(screen.x.length(),screen.y.length())
	var density:=0.75 if BattleSceneCatalog.quality=="low" else 1.12 if BattleSceneCatalog.quality=="high" else 1.0
	pixels*=density
	var limit:=6144.0 if BattleSceneCatalog.quality=="high" else 4096.0
	pixels*=minf(1.0,limit/maxf(1.0,maxf(pixels.x,pixels.y)))
	return Vector2i(pixels.ceil().max(Vector2(64,64)))

func bind_board(board: Control) -> void:
	if source_board==board:return
	source_board=board
	_dirty=true

func set_background(id: String) -> void:
	if id==background_id:return
	background_id=id;field_background=null
	if is_instance_valid(field_mesh):field_mesh.visible=false
	if not CardArtCache.valid_id(id):return
	var texture:=await CardArtCache.load_art(id,get_tree())
	if id!=background_id:return
	field_background=texture
	if is_instance_valid(field_mesh):field_material.albedo_texture=texture;field_mesh.visible=texture!=null

func world_point(pixel: Vector2, elevation: float) -> Vector3:
	var point:=pixel*Vector2(viewport.size)/size.max(Vector2.ONE)
	var origin:=camera.project_ray_origin(point)
	var direction:=camera.project_ray_normal(point)
	return origin+direction*((elevation-origin.y)/direction.y)

func _process(delta: float) -> void:
	if not is_instance_valid(viewport):return
	var should_render:=is_visible_in_tree()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if should_render else SubViewport.UPDATE_DISABLED
	if not should_render:return
	_resize()
	elapsed+=delta
	if menu_mode:
		# Slow parallax without oscillating text or moving interactive controls.
		camera.position.x=16+sin(elapsed*0.075)*0.6
		camera.look_at(Vector3(0,1,-14))
		return
	_sync_board()

func _sync_board() -> void:
	if not is_processing() or not is_visible_in_tree() or menu_mode:return
	if not is_instance_valid(source_board) or not _rendering:return
	var seen: Dictionary={}
	for source in source_board.get_children():
		if not source is Face and not (source is Prop and source.kind in ["hq","deck","back"]):continue
		# Enlarged inspection belongs above the HUD, with neutral light for reading.
		if source.get_meta("screen_space",false):continue
		if source.size.x<1 or source.size.y<1:continue
		var id:=source.get_instance_id();seen[id]=true
		if not cards.has(id):cards[id]=_new_card(source)
		_sync_card(source,cards[id])
	for id in cards.keys():
		if seen.has(id):continue
		_retire_card(cards[id]);cards.erase(id)
	_dirty=false

func _new_card(source: Control) -> Dictionary:
	for index in capture_pool.size():
		var item: Dictionary = capture_pool[index]
		if item.paint.get_script() != source.get_script(): continue
		capture_pool.remove_at(index)
		item.source = source
		item.signature = []
		item.size = Vector2.ZERO
		item.ready = false
		item.pending = false
		item.paint.theme.default_font = source.get_theme_default_font()
		source.self_modulate.a = 0.0
		return item
	var texture_view:=SubViewport.new();texture_view.disable_3d=true;texture_view.transparent_bg=true
	texture_view.gui_disable_input=true;texture_view.handle_input_locally=false
	texture_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	# A child capture renders before the world that samples it.
	viewport.add_child(texture_view)
	var paint: Control=source.get_script().new()
	var theme_copy:=Theme.new();theme_copy.default_font=source.get_theme_default_font();theme_copy.default_font_size=source.get_theme_default_font_size();paint.theme=theme_copy
	paint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_view.add_child(paint)
	paint.set_process(false);paint.set_process_input(false)
	var quad:=MeshInstance3D.new();quad.mesh=QuadMesh.new()
	var material:=ShaderMaterial.new();material.shader=SurfaceShader
	material.set_shader_parameter("face_texture",texture_view.get_texture());material.set_shader_parameter("normal_texture",NormalMap)
	material.set_shader_parameter("roughness_texture",RoughMap)
	quad.material_override=material;quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;quad.visible=false
	world_root.add_child(quad)
	var solid:=MeshInstance3D.new();solid.mesh=BoxMesh.new()
	solid.material_override=_material(Color("44464a"),0.9,0.24);solid.visible=false;world_root.add_child(solid)
	source.self_modulate.a=0.0
	return {"source":source,"paint":paint,"viewport":texture_view,"quad":quad,"solid":solid,"material":material,"signature":[],"size":Vector2.ZERO,"ready":false,"pending":false}

func _sync_card(source: Control, item: Dictionary) -> void:
	source.self_modulate.a=0.0
	var paint: Control=item.paint
	if source is Face and is_instance_valid(source.watermark): source.watermark.self_modulate.a=0
	var properties: Array=["value","maximum","kind","active","title","friendly","sin_id","back_color","back_icon","hq_art","hq_art_id"]
	if source is Face:
		properties=["compact","choice_mode","hand_mode","highlighted","enemy","current_attack","current_health","current_operation_cost","current_armor","can_act","is_target","base_attack","base_health","max_health","disabled","artwork","faction_icon","subtitle","caption","art_id"]
	var signature: Array=[]
	for property in properties:signature.append(source.get(property))
	if source is Face:signature.append_array([source.spec,source.field_effects,source.current_custom_stacks])
	signature.append(source.is_hovered())
	if _dirty or signature!=item.signature or item.size!=source.size:
		for property in properties:paint.set(property,source.get(property))
		if source is Face:
			paint.spec=source.spec;paint.field_effects=source.field_effects;paint.current_custom_stacks=source.current_custom_stacks
			paint.use_tooltip=false
			paint.highlighted=source.highlighted or source.is_hovered()
			item.material.set_shader_parameter("compact_card",source.compact)
			var print_area: Rect2=source._print_rect()
			var design:=Face.FIELD_SIZE if source.compact else Face.FULL_CARD_SIZE
			var art_area: Rect2=source.printed_art_rect()
			item.material.set_shader_parameter("face_rect",Vector4(print_area.position.x/source.size.x,print_area.position.y/source.size.y,print_area.size.x/source.size.x,print_area.size.y/source.size.y))
			item.material.set_shader_parameter("art_rect",Vector4(art_area.position.x/design.x,art_area.position.y/design.y,art_area.end.x/design.x,art_area.end.y/design.y))
			item.material.set_shader_parameter("has_art",source.artwork!=null)
		# Reserve hover/lift headroom from the stable board density. Animated card
		# scale must not repeatedly resize and clear its render target.
		var screen:=get_viewport().get_screen_transform()*source_board.get_global_transform_with_canvas()
		var sampling:=clampf(ceilf(maxf(2.0,maxf(screen.x.length(),screen.y.length())*1.8)*2.0)/2.0,2.0,4.0)
		var pixels:=Vector2i((source.size*sampling).ceil())
		if item.viewport.size!=pixels:item.viewport.size=pixels
		paint.custom_minimum_size=Vector2.ZERO;paint.size=source.size;paint.pivot_offset=Vector2.ZERO;paint.scale=Vector2.ONE*sampling
		paint.queue_redraw();item.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		item.pending=true
		item.signature=signature.duplicate(true);item.size=source.size
	_sync_card_transform(source,item)

func _captures_drawn() -> void:
	# Do not expose an unpainted texture or its opaque body during creation.
	for item in cards.values():
		if item.pending:
			item.ready=true;item.pending=false

func _sync_transforms() -> void:
	if not is_processing() or not is_visible_in_tree() or menu_mode:return
	# Geometry can follow late tweens without touching the viewport's canvas.
	for item in cards.values():
		if is_instance_valid(item.source):_sync_card_transform(item.source,item)

func _sync_card_transform(source: Control, item: Dictionary) -> void:
	# A return tween can restore the source after _process. Keep the input
	# surface hidden right through drawing so it cannot flash over its 3D copy.
	source.self_modulate.a=0.0
	var transform_2d: Transform2D=get_global_transform().affine_inverse()*source.get_global_transform()
	var height:=0.22
	if source is Face and source.hand_mode:height=1.7+maxi(source.z_index,0)*0.025
	elif source is Prop and source.kind=="back":height=1.8+source.get_index()*0.006
	elif source is Prop and source.kind=="deck":height=0.42
	else:height+=maxi(source.z_index,0)*0.006
	if source.z_index>=50:height=6+source.z_index*0.01
	_set_quad(item.quad,transform_2d,Rect2(Vector2.ZERO,source.size),height)
	var body: Rect2=source.card_body_rect() if source is Face else Rect2(Vector2.ZERO,source.size)
	_set_solid(item.solid,transform_2d,body,height-0.047)
	var color: Color=source.modulate
	item.material.set_shader_parameter("tint",color)
	item.quad.visible=item.ready and source.is_visible_in_tree() and color.a>0.02 and not source.get_meta("drag_hidden",false) and not source.get_meta("draw_hidden",false)
	item.solid.visible=item.quad.visible and color.a>0.8

func _set_quad(node: MeshInstance3D, t: Transform2D, rect: Rect2, height: float) -> void:
	var a:=world_point(t*rect.position,height)
	var b:=world_point(t*Vector2(rect.end.x,rect.position.y),height)
	var d:=world_point(t*Vector2(rect.position.x,rect.end.y),height)
	var x:=b-a;var y:=a-d
	node.transform=Transform3D(Basis(x,y,x.cross(y).normalized()),(b+d)*0.5)

func _set_solid(node: MeshInstance3D,t: Transform2D,rect: Rect2,height: float) -> void:
	var a:=world_point(t*rect.position,height)
	var b:=world_point(t*Vector2(rect.end.x,rect.position.y),height)
	var d:=world_point(t*Vector2(rect.position.x,rect.end.y),height)
	node.transform=Transform3D(Basis(b-a,Vector3(0,0.07,0),d-a),(b+d)*0.5)

func _retire_card(item: Dictionary) -> void:
	if is_instance_valid(item.source):item.source.self_modulate.a=1.0
	if is_instance_valid(item.source) and item.source is Face and is_instance_valid(item.source.watermark):item.source.watermark.self_modulate.a=1.0
	# Render-target destruction can synchronize the GPU exactly as the hand
	# closes. Keep a bounded pool; reused captures stay hidden until repainted.
	item.source = null
	item.quad.visible = false
	item.solid.visible = false
	item.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if capture_pool.size() < CAPTURE_POOL_LIMIT:
		capture_pool.append(item)
		return
	for key in ["viewport","quad","solid"]:
		if is_instance_valid(item[key]):item[key].queue_free()

func _exit_tree() -> void:
	for item in cards.values():
		if is_instance_valid(item.source):item.source.self_modulate.a=1.0
		if is_instance_valid(item.source) and item.source is Face and is_instance_valid(item.source.watermark):item.source.watermark.self_modulate.a=1.0
