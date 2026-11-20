class_name StatusIcons
extends RefCounted
## One line-icon set for unit classes, card kinds, keywords and unit states: a 24-unit grid, 2-unit round strokes,
## drawn white and tinted where they are used. Rendered from SVG at the size needed and cached.
## Colours: CYAN for what helps the unit (keywords), ORANGE for control and modifiers, WHITE for timings and layers,
## GOLD for armour and the headquarters.

const CYAN := Color("16a4e6")
const ORANGE := Color("ff7a1a")
const WHITE := Color("f1f1f1")
const GOLD := Color("ddba72")

const PATHS := {
	# Unit classes and card kinds
	"infantry": "M5 13a7 7 0 0 1 14 0v1H5z M3 14h18 M12 6V4",
	"tank": "M6 12h12a3 3 0 0 1 0 6H6a3 3 0 0 1 0-6z M7 12V9h7l2 3 M14 10h7",
	"artillery": "M11.5 16a3.5 3.5 0 1 1-7 0a3.5 3.5 0 1 1 7 0z M10 14 21 6 M11 17h8l2 3",
	"fighter": "M12 3v18 M12 9 4 14h16z M9 20h6",
	"bomber": "M12 4v16 M2 12h20l-10-3z M7 11v3 M17 11v3 M9 19h6",
	"order": "M5 6l7 6-7 6 M12 6l7 6-7 6",
	"counter": "M12 3 20 6v6c0 5-4 8-8 9-4-1-8-4-8-9V6z M9 11h6l-2-2 M15 14H9l2 2",
	"field": "M3 19 9 9l4 6 3-4 5 8z M15 4v5 M15 4h4l-1 1.5 1 1.5h-4",
	"hq": "M12 3 20 7.5v9L12 21l-8-4.5v-9z M9 15v-4h6v4 M12 11V8",
	# Keywords
	"guard": "M12 3 20 6v6c0 5-4 8-8 9-4-1-8-4-8-9V6z",
	"blitz": "M13 2 5 14h6l-1 8 8-12h-6z",
	"ambush": "M2 12s4-6 10-6 10 6 10 6 M5 15l-1 2 M12 17v2 M19 15l1 2",
	"fury": "M4 6l6 6-6 6 M13 6l6 6-6 6",
	"smokescreen": "M3 9c3-3 6 3 9 0s6 3 9 0 M3 14c3-3 6 3 9 0s6 3 9 0 M6 19c2-2 4 2 6 0s4 2 6 0",
	"shock": "M12 2v5 M12 17v5 M2 12h5 M17 12h5 M5 5l3.5 3.5 M15.5 15.5 19 19 M19 5l-3.5 3.5 M8.5 15.5 5 19",
	"mobilize": "M12 20V5 M6 11l6-6 6 6 M5 21h14",
	"alpine": "M2 20 9 7l4 7 3-4 6 10z",
	"salvage": "M20 12a8 8 0 1 1-3-6.2 M20 4v5h-5 M9 12h6 M12 9v6",
	"immune": "M12 3 20 7.5v9L12 21l-8-4.5v-9z M9 12l2 2 4-4",
	"armor": "M5 4h14v8c0 5-3 7-7 8-4-1-7-3-7-8z M5 9h14 M5 13h14",
	"revive": "M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z M12 10v5 M9.5 12.5h5",
	# States, modifiers and timings
	"pin": "M12 3v11 M8 10l4 4 4-4 M4 19h16",
	"suppress": "M20 12a8 8 0 1 1-16 0a8 8 0 1 1 16 0z M6.5 6.5l11 11",
	"damage": "M6 6l12 12 M18 6 6 18",
	"stats": "M12 5v14 M5 12h14",
	"attacks": "M5 19 16 8 M14 5l5 5 M4 15l5 5",
	"on_death": "M12 3v14 M8 7h8 M9 21h6",
	"own_turn_start": "M20 12a8 8 0 1 1-2.3-5.7 M20 4v5h-5",
	"own_turn_end": "M4 12a8 8 0 1 0 2.3-5.7 M4 4v5h5",
	"stack": "M12 4 21 9l-9 5-9-5z M3 14l9 5 9-5",
	"active": "M12 2v4 M12 18v4 M2 12h4 M18 12h4 M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0z",
	"liberated": "M7 11V7a5 5 0 0 1 9.6-2 M5 11h14v10H5z M12 15v2",
	"veteran": "M5 9l7-4 7 4 M5 14l7-4 7 4 M5 19l7-4 7 4",
}

## Which icon and colour each status badge id uses; ids not listed keep their text mark.
const BADGES := {
	"guard": ["guard", CYAN], "blitz": ["blitz", CYAN], "ambush": ["ambush", CYAN], "fury": ["fury", CYAN],
	"smokescreen": ["smokescreen", CYAN], "shock": ["shock", CYAN], "mobilize": ["mobilize", CYAN], "alpine": ["alpine", CYAN],
	"salvage": ["salvage", CYAN], "immune": ["immune", CYAN], "revive": ["revive", CYAN], "armor": ["armor", GOLD],
	"pin": ["pin", ORANGE], "suppress": ["suppress", ORANGE], "damage": ["damage", ORANGE], "stats": ["stats", ORANGE], "attacks": ["attacks", ORANGE],
	"on_death": ["on_death", WHITE], "own_turn_start": ["own_turn_start", WHITE], "own_turn_end": ["own_turn_end", WHITE],
	"active": ["active", WHITE], "liberated": ["liberated", CYAN], "veteran": ["veteran", GOLD],
}

static var _cache: Dictionary = {}

static func has(name: String) -> bool:
	return PATHS.has(name)

## A white icon rendered for a box of `pixels` on screen; tint it with the colour passed to draw_texture_rect.
static func texture(name: String, pixels: float) -> Texture2D:
	if not PATHS.has(name): return null
	# Render at twice the drawn size (rounded up to a step) so it stays sharp on high-DPI screens and in zoomed cards.
	var size := clampi(int(ceil(maxf(pixels, 8.0) * 2.0 / 16.0)) * 16, 16, 256)
	var key := "%s@%d" % [name, size]
	if _cache.has(key): return _cache[key]
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"24\" height=\"24\"><path d=\"%s\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>" % PATHS[name]
	var image := Image.new()
	if image.load_svg_from_string(svg, size / 24.0) != OK: return null
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result

## Draws the icon centred in rect on any CanvasItem.
static func draw(canvas: CanvasItem, name: String, rect: Rect2, color: Color) -> bool:
	var side := minf(rect.size.x, rect.size.y)
	var tex := texture(name, side)
	if tex == null: return false
	canvas.draw_texture_rect(tex, Rect2(rect.get_center() - Vector2(side, side) / 2.0, Vector2(side, side)), false, color)
	return true
