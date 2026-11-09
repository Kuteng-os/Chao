shader_type canvas_item;
varying vec4 icon_tint;
void vertex(){icon_tint=COLOR;}
void fragment(){
 vec4 pixel=texture(TEXTURE,UV);
 vec4 corner=texture(TEXTURE,vec2(0.005));
 vec4 opposite=texture(TEXTURE,vec2(0.995));
 float alpha=pixel.a;
 // Preserve uploaded transparency. Opaque flat backgrounds become a silhouette.
 if(corner.a>0.99 && opposite.a>0.99 && distance(corner.rgb,opposite.rgb)<0.025){
  alpha*=smoothstep(0.035,0.20,distance(pixel.rgb,corner.rgb));
 }
 COLOR=vec4(icon_tint.rgb,icon_tint.a*alpha);
}
