shader_type canvas_item;

// Drives a full-screen dissolve/wipe rather than a plain alpha cross-fade: `mask`'s own
// per-pixel brightness decides draw order, not a uniform fade. At `reveal == 0.0` every
// pixel is covered; at `reveal == 1.0` none is. In between, a pixel is covered exactly
// while its mask value is above `reveal` - so as `reveal` climbs from 0 to 1, black
// (0.0) areas of the mask are the first to stop being covered and white (1.0) areas the
// last, the "black fading first, then white" look the default gradient mask gives.
// `fade_overlay.gd` is the only writer of `reveal`/`mask`/`fade_color`, through a Tween.

uniform sampler2D mask : source_color;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float m = texture(mask, UV).r;
	// A soft edge rather than a hard cut, so the wipe reads as a dissolve instead of a
	// jagged line following the mask's own contours.
	float band = 0.03;
	float covered = smoothstep(reveal - band, reveal + band, m);
	COLOR = vec4(fade_color.rgb, covered);
}
