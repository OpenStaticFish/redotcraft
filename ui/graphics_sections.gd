class_name GraphicsSections
extends RefCounted

## Single source for the graphics fine-tune rows. The Advanced hub lists one
## button per section; GraphicsSectionPanel renders the rows for its section.

const SECTIONS := [
	{"title": "LIGHTING", "rows": [
		{"type": "check", "key": "ssao_ssil", "label": "Ambient Occlusion / SSIL"},
		{"type": "check", "key": "ssr", "label": "Screen-Space Reflections"},
		{"type": "check", "key": "sdfgi", "label": "SDFGI", "tooltip": "Stutters while the day/night cycle moves the sun."},
	]},
	{"title": "SHADOWS", "rows": [
		{"type": "check", "key": "soft_shadows", "label": "Soft Shadows", "tooltip": "Shadow edges vibrate without TAA or FSR2."},
		{"type": "check", "key": "solid_leaf_shadows", "label": "Solid Leaf Shadows", "tooltip": "Leaves cast a solid canopy shadow instead of a dappled one, which stops the leaf-shadow edge from crawling."},
		{"type": "slider", "key": "shadow_max_distance", "label": "Shadow Distance", "min": 64.0, "max": 512.0, "step": 8.0, "format": "%d m"},
		{"type": "slider", "key": "shadow_opacity", "label": "Shadow Opacity", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "shadow_blur", "label": "Shadow Blur", "min": 0.0, "max": 4.0, "step": 0.1, "format": "%.1f"},
	]},
	{"title": "SKY & ATMOSPHERE", "rows": [
		{"type": "check", "key": "volumetric_fog", "label": "Volumetric Fog"},
		{"type": "slider", "key": "volumetric_fog_density", "label": "Volumetric Density", "min": 0.0, "max": 0.03, "step": 0.001, "format": "%.3f"},
		{"type": "slider", "key": "volumetric_fog_length", "label": "Volumetric Length", "min": 32.0, "max": 256.0, "step": 8.0, "format": "%d m"},
		{"type": "slider", "key": "fog_density", "label": "Distance Fog", "min": 0.0, "max": 0.003, "step": 0.0001, "format": "%.4f"},
	]},
	{"title": "POST-PROCESSING", "rows": [
		{"type": "option", "key": "tonemap", "label": "Tonemapper", "options": ["Linear", "Reinhardt", "Filmic", "ACES", "AgX"]},
		{"type": "slider", "key": "tonemap_exposure", "label": "Exposure", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "saturation", "label": "Saturation", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "contrast", "label": "Contrast", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "glow_intensity", "label": "Glow Intensity", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%.2f"},
	]},
	{"title": "PERFORMANCE", "rows": [
		{"type": "option", "key": "msaa", "label": "MSAA", "options": ["Off", "2x", "4x", "8x"]},
		{"type": "check", "key": "taa", "label": "Temporal AA (TAA)"},
		{"type": "slider", "key": "fsr_scale", "label": "Render Scale", "tooltip": "Below 100% uses FSR2 upscaling.", "min": 0.5, "max": 1.0, "step": 0.01, "format": "%d%%", "display_scale": 100.0},
	]},
]


static func rows_for(section_title: String) -> Array:
	for section in SECTIONS:
		if String(section["title"]) == section_title:
			return section["rows"]
	return []
