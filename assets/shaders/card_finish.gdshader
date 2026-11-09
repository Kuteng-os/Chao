shader_type canvas_item;
render_mode unshaded;
uniform sampler2D surface_roughness : filter_linear_mipmap;
uniform vec2 face_size = vec2(252.0,354.0);
uniform vec4 artwork_rect = vec4(0.0);
uniform bool has_artwork = false;
varying vec2 face_position;
varying float face_angle;

void vertex() {
 face_position=VERTEX;
 face_angle=atan(MODEL_MATRIX[0].y,MODEL_MATRIX[0].x);
}

void fragment() {
 vec4 ink=COLOR;
 vec2 p=face_position/face_size;
 float inside=step(0.008,p.x)*step(p.x,0.992)*step(0.008,p.y)*step(p.y,0.992);
 float art=step(artwork_rect.x,face_position.x)*step(face_position.x,artwork_rect.z)*step(artwork_rect.y,face_position.y)*step(face_position.y,artwork_rect.w);
 float printed=smoothstep(0.28,0.64,max(ink.r,max(ink.g,ink.b)));
 float substrate=inside*(1.0-art*float(has_artwork))*(1.0-printed);
 // Soft reflected light and a darker reflected room distinguish coated
 // metal from a flat fill. No scrolling sheen or decorative hatch pattern.
 // Artwork and pale glyphs keep their original colors and contrast.
 vec2 reflection=p-vec2(0.12+sin(face_angle)*0.38,0.16);
 float softbox=exp(-dot(reflection*vec2(2.4,0.9),reflection*vec2(2.4,0.9)));
 float shoulder=exp(-pow((p.x-0.96)/0.10,2.0));
 float room=exp(-pow((p.x-0.66)/0.23,2.0));
	float wear=texture(surface_roughness,p).r-0.5;
	vec3 finish=ink.rgb*(0.78+softbox*0.32-room*0.12)
	 +vec3(0.96,0.98,1.0)*(softbox*0.14+shoulder*0.095+wear*0.015);
 COLOR=vec4(mix(ink.rgb,finish,substrate),ink.a);
}
