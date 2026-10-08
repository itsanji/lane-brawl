shader_type canvas_item;
// Dark screen-edge vignette, a big part of the Hollow Knight look.

uniform float strength = 0.62;
uniform float inner = 0.36;
uniform float outer = 0.86;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.82));
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(inner, outer, d) * strength);
}
