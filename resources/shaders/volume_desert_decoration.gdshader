shader_type spatial;
render_mode depth_draw_opaque, cull_back, ambient_light_disabled, specular_disabled;
#define VOLUME_DECORATION
#include "volume_satellite_surface.gdshaderinc"
