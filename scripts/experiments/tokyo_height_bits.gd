extends RefCounted
## 逻辑分辨率仍2048；不展开索引，不更改任何接收高度码。
const SHADER_CODE := """
float agl_height_index(vec2 uv) {
 ivec2 pixel=clamp(ivec2(floor(uv*2048.0)),ivec2(0),ivec2(2047));
 int bit_position=pixel.x*5;
 int byte_x=bit_position/8;
 int shift=bit_position & 7;
 int lo=int(floor(texelFetch(baked_height,ivec2(byte_x,pixel.y),0).r*255.0+0.5));
 int hi=int(floor(texelFetch(baked_height,ivec2(min(byte_x+1,1279),pixel.y),0).r*255.0+0.5));
 return float(((lo | (hi << 8)) >> shift) & 31);
}
"""


static func storage_width(manifest: Dictionary) -> int:
	if manifest.get("height_encoding","")=="global_palette_r8":
		return 2048
	if manifest.get("height_encoding","")!="global_palette_r5_lsb" or manifest.get("height_size")!=2048 or manifest.get("height_bits")!=5 or manifest.get("height_row_bytes")!=1280:
		return 0
	var count: Variant = manifest.get("unique_height_codes")
	if not typeof(count) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(count)) or count!=int(count) or count<1 or count>32:
		return 0
	return 1280
