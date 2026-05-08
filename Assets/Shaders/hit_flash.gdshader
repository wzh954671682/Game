shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(0.878, 0.878, 0.878, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec4 flash = flash_color * tex_color.a;
	COLOR = mix(tex_color, flash, flash_amount);
}
