shader_type canvas_item;
render_mode unshaded;

const int MAX_BOARDS = 32;

uniform int board_count = 0;
uniform vec4 board_rects[MAX_BOARDS];
uniform float board_alphas[MAX_BOARDS];

varying vec2 local_position;


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	for (int index = 0; index < MAX_BOARDS; index++) {
		if (index >= board_count) {
			break;
		}
		vec4 board = board_rects[index];
		if (local_position.x >= board.x && local_position.x <= board.z
				&& local_position.y >= board.y && local_position.y <= board.w) {
			COLOR.a *= board_alphas[index];
		}
	}
}
