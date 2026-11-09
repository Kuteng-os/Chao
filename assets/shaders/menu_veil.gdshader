shader_type canvas_item;
uniform float strength=0.08;
void fragment(){
 float side=mix(0.91,0.12,pow(UV.x,0.6));
 float bottom=smoothstep(0.65,1.0,UV.y)*0.45;
 float top=(1.0-smoothstep(0.0,0.15,UV.y))*0.3;
 COLOR=vec4(0.015,0.028,0.04,1.0-(1.0-max(side,strength))*(1.0-bottom)*(1.0-top));
}
