shader_type canvas_item;

// Removes the solid magenta background from player.png so the ship
// renders with transparency without editing the PNG.
uniform vec3 key_color : source_color = vec3(1.0, 0.0, 1.0);
uniform float threshold : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float dist = distance(c.rgb, key_color);
    // Soft edge: fade out near-key pixels to avoid jagged borders.
    float alpha = smoothstep(threshold * 0.55, threshold, dist);
    COLOR = vec4(c.rgb, c.a * alpha);
}
