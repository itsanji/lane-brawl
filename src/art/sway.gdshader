shader_type canvas_item;
// Wind sway for foliage. Gusts come and go: the amplitude swells and fades over ~20 s.

uniform float amplitude = 3.0;
uniform float speed = 1.1;

void vertex() {
	float gust = 0.55 + 0.45 * sin(TIME * 0.27) * sin(TIME * 0.61 + 1.3);
	VERTEX.x += sin(TIME * speed + VERTEX.y * 0.035 + VERTEX.x * 0.004) * amplitude * gust;
}
