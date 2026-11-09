shader_type spatial;
render_mode fog_disabled;
uniform vec4 surface_color : source_color;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
void fragment() {
 ALBEDO=surface_color.rgb*0.75;
 METALLIC=0.45;
 EMISSION=surface_color.rgb*0.30;
 // The scanned surface only varies the reflection. No visible tiled albedo pattern.
 ROUGHNESS=0.38+(texture(roughness_texture,UV).r-0.5)*0.12;
 SPECULAR=0.36;
 NORMAL_MAP=mix(vec3(0.5,0.5,1.0),texture(normal_texture,UV).rgb,0.06);
 NORMAL_MAP_DEPTH=0.16;
}
