extends RefCounted
## 可选地表高度索引：保持原float32层高，两个4bit编号装入一个字节。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func valid_texture(row: Dictionary) -> bool:
	return row.get("kind")=="ground_height_4bit" and row.get("format")==Image.FORMAT_RGBA8 \
		and row.get("mipmaps") == false and Contract.integer(row.get("width"),1,16384) \
		and Contract.integer(row.get("height"),1,16384) \
		and row.get("mip_bytes")==int(row.width)*int(row.height)*4

static func descriptor(value: Variant, color_size: Vector2i) -> Dictionary:
	if not Contract.binding(value) or not valid_texture(value): return {}
	if int(value.width)!=(color_size.x+7)/8 or int(value.height)!=color_size.y \
		or value.get("charge")!=int(value.mip_bytes)*3+4096: return {}
	var result: Dictionary=value.duplicate()
	for field: String in ["width","height","format","mip_bytes","charge"]: result[field]=int(result[field])
	return result

static func shader_code() -> String:
	var code := preload("res://scripts/rendering/tokyo_hlod_surface.gd").textured_code()
	code=code.replace("shader_type spatial;","shader_type spatial;\nuniform sampler2D height_source : filter_nearest, repeat_disable;\nuniform float plane_y;\nuniform vec2 height_size;\nuniform float height_levels[16];")
	return code.replace("void fragment() {", """void fragment() {
	ivec2 pixel=clamp(ivec2(UV*height_size),ivec2(0),ivec2(height_size)-ivec2(1));
	vec4 packed=texelFetch(height_source,ivec2(pixel.x/8,pixel.y),0)*255.0;
	int byte_value=int(round(packed[(pixel.x%8)/2]));
	int height_id=(pixel.x%2)==0 ? (byte_value&15) : (byte_value>>4);
	vec3 up_view=(VIEW_MATRIX*MODEL_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz;
	vec4 source_clip=PROJECTION_MATRIX*vec4(VERTEX+up_view*(height_levels[height_id]-plane_y),1.0);
	DEPTH=source_clip.z/source_clip.w*0.5+0.5;
""")
