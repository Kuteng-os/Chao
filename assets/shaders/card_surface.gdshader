shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage, fog_disabled;
uniform sampler2D face_texture : source_color, filter_linear;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_texture : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 face_rect = vec4(0.0,0.0,1.0,1.0);
uniform vec4 art_rect = vec4(0.0,0.0,1.0,1.0);
uniform bool has_art = false;
uniform bool compact_card = false;
void fragment() {
 vec4 face=texture(face_texture,UV);
 vec2 p=(UV-face_rect.xy)/face_rect.zw;
 float art=step(art_rect.x,p.x)*step(p.x,art_rect.z)*step(art_rect.y,p.y)*step(p.y,art_rect.w);
 float ink=smoothstep(0.32,0.70,max(face.r,max(face.g,face.b)));
 float foil=(1.0-art*float(has_art))*(1.0-ink);
 vec3 color=face.rgb*tint.rgb;
 // Keep printed artwork and glyphs at their original exposure. Only the
 // colored substrate receives scene lighting and the reflection of the sky.
 ALBEDO=color*foil*0.82;
 ALPHA=face.a*tint.a;
 ALPHA_SCISSOR_THRESHOLD=0.2;
 ALPHA_ANTIALIASING_EDGE=0.18;
 ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(face_texture,0));
 METALLIC=foil*0.94;
 float wear=texture(roughness_texture,p).r-0.5;
 ROUGHNESS=mix(0.84,0.20+wear*0.19,foil);
 SPECULAR=0.65*foil;
 vec3 micro=texture(normal_texture,p).rgb-vec3(0.5,0.5,1.0);
 // A shallow rolled surface catches the environment; keep scanned normals
 // small enough that text and edges never look embossed or scratched.
 NORMAL_MAP=vec3(0.5,0.5,1.0)+foil*(micro*0.12+vec3((p.x-0.5)*0.16,(p.y-0.5)*0.036,0.0));
 NORMAL_MAP_DEPTH=0.65;
 EMISSION=color*(1.0-foil*0.42);
}
