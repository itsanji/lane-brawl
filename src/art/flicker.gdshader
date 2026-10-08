shader_type canvas_item;
render_mode blend_add;
// Additive light that flickers gently; each lantern (different world x) flickers out of phase.

uniform float depth = 0.16;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float p = world_pos.x * 0.004;
	float f = 1.0 - depth + depth * (0.55 * sin(TIME * 6.3 + p * 7.0) + 0.3 * sin(TIME * 11.7 + p * 3.0) + 0.15 * sin(TIME * 2.1 + p));
	COLOR *= f;
}
