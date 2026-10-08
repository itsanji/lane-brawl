@tool
class_name SeasonPalette
extends RefCounted
## Colour scripts per season, Hollow Knight style: one dominant hue per area, foggy light
## backgrounds, near-black foreground silhouettes, and a few glowing accents.

const S := RiftLayout.Season

const PALETTES := {
	S.WINTER: {  # Japanese winter at dusk: indigo sky, moonlight, snow, vermilion torii, warm lanterns
		"sky_top": Color("1c2541"), "sky_bottom": Color("6a7ca3"), "fog": Color("9aaccb"),
		"far": Color("52658c"), "mid": Color("26304d"), "near": Color("090d18"),
		"foliage": [Color("22384a"), Color("2a4152"), Color("1d3242")],
		"accent": Color("eef3fb"), "accent2": Color("d3dff0"),
		"rock": Color("121827"), "rock_rim": Color("8fa3c6"), "cap": Color("edf2fa"), "cap2": Color("c8d5ea"),
		"glow": Color("ffc27a"), "moon": Color("eef2ff"), "shaft": Color(0.8, 0.88, 1.0, 0.03),
		"particle": Color(1, 1, 1, 0.9), "pad": Color("9fd8ff"),
		"torii": Color("c2362b"), "lamp": Color("ffb35c"), "camellia": Color("c8283a"),
	},
	S.SPRING: {
		"sky_top": Color("1c3a3e"), "sky_bottom": Color("4a7d6e"), "fog": Color("79a894"),
		"far": Color("5b8c7c"), "mid": Color("244a40"), "near": Color("0a1513"),
		"foliage": [Color("3f7d5c"), Color("4f9468"), Color("356c50")],
		"accent": Color("f4a9c6"), "accent2": Color("ffd9e7"),
		"rock": Color("101a18"), "rock_rim": Color("6fae8b"), "cap": Color("6fae7b"), "cap2": Color("94c98a"),
		"glow": Color("fff0d8"), "shaft": Color(1, 0.96, 0.85, 0.08), "particle": Color("ffc4da"),
		"pad": Color("ff9cc2"),
	},
	S.SUMMER: {
		"sky_top": Color("0a2723"), "sky_bottom": Color("1d4d3c"), "fog": Color("2f6e58"),
		"far": Color("2e6553"), "mid": Color("153a30"), "near": Color("050f0c"),
		"foliage": [Color("2f7a55"), Color("3f9a64"), Color("26624a")],
		"accent": Color("c8ff8a"), "accent2": Color("7fe0a8"),
		"rock": Color("0a1411"), "rock_rim": Color("3f8a6a"), "cap": Color("2f7a55"), "cap2": Color("4fae74"),
		"glow": Color("b8ffd8"), "shaft": Color(0.75, 1, 0.88, 0.07), "particle": Color("d8ff8a"),
		"pad": Color("7dffb0"),
	},
	S.FALL: {
		"sky_top": Color("3a2626"), "sky_bottom": Color("94532c"), "fog": Color("c07a46"),
		"far": Color("a5653c"), "mid": Color("4d2c1f"), "near": Color("120a07"),
		"foliage": [Color("c4571f"), Color("e08a2e"), Color("a83a1c")],
		"accent": Color("f2b14a"), "accent2": Color("e8662a"),
		"rock": Color("19110d"), "rock_rim": Color("b06a3e"), "cap": Color("c4571f"), "cap2": Color("e08a2e"),
		"glow": Color("ffd08a"), "shaft": Color(1, 0.85, 0.6, 0.09), "particle": Color("e8762e"),
		"pad": Color("ffb35c"),
	},
}


static func get_palette(season: RiftLayout.Season) -> Dictionary:
	return PALETTES[season]


static func for_band(b: int) -> Dictionary:
	return PALETTES[RiftLayout.BAND_SEASON[b]]
