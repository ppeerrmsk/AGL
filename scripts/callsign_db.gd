class_name CallsignDB

## 代号数据库 — 800 个随机英文单词代号
## 沙盒模式：随机分配不重复代号
## 生存模式：玩家固定 "Ultra"，敌机随机分配

# ── 已使用的代号集合（局内去重）──
static var _used: Dictionary = {}  # callsign -> true

## 重置（重启/返回主菜单时调用）
static func reset() -> void:
	_used.clear()

## 分配一个随机不重复的代号
static func allocate() -> String:
	var pool := CALLSIGNS
	# 尝试随机抽取
	for i in 100:
		var cs: String = pool[randi() % pool.size()]
		if not _used.has(cs):
			_used[cs] = true
			return cs
	# 如果太多重复就顺序查找
	for cs in pool:
		if not _used.has(cs):
			_used[cs] = true
			return cs
	# 全部用完，返回带编号的
	return "Unit%03d" % _used.size()

## 回收代号（单位死亡时调用，允许后续复用）
static func recycle(cs: String) -> void:
	_used.erase(cs)

## 标记某个代号为已使用（固定代号场景）
static func reserve(cs: String) -> void:
	_used[cs] = true

# ── 800 个代号 ──
const CALLSIGNS: PackedStringArray = [
	# --- A ---
	"Ace", "Adder", "Admiral", "Aegis", "Aero", "Afterburn", "Agile", "Albatross",
	"Alchemy", "Alert", "Alpha", "Amber", "Anchor", "Angel", "Anthem", "Anvil",
	"Apache", "Apex", "Apollo", "Archer", "Arctic", "Arena", "Argon", "Aria",
	"Arrow", "Ash", "Astra", "Atlas", "Aurora", "Avalon", "Avenger", "Axle",
	# --- B ---
	"Badger", "Ballad", "Bandit", "Banshee", "Barrage", "Baron", "Basalt", "Basilisk",
	"Beacon", "Bear", "Beast", "Beetle", "Bishop", "Blade", "Blaze", "Blitz",
	"Bloom", "Bolt", "Bomber", "Bone", "Boomer", "Bounty", "Bravo", "Breaker",
	"Breeze", "Brick", "Bridge", "Bristle", "Bronze", "Brook", "Brute", "Bullet",
	"Burn", "Burner", "Burst", "Buzz", "Bypass",
	# --- C ---
	"Cabal", "Cadence", "Caliber", "Callisto", "Calm", "Camel", "Cannon", "Canyon",
	"Carbon", "Cardinal", "Cargo", "Cascade", "Caster", "Catalyst", "Cedar", "Celsius",
	"Centurion", "Chaos", "Charge", "Chariot", "Chase", "Checkmate", "Cherry", "Chimera",
	"Chrome", "Cipher", "Circuit", "Citadel", "Clad", "Clash", "Claw", "Cliff",
	"Climber", "Clock", "Cloud", "Cluster", "Coalt", "Cobra", "Comet", "Compass",
	"Condor", "Coral", "Core", "Corona", "Corsair", "Cosmos", "Cougar", "Cowboy",
	"Crafter", "Crater", "Creed", "Crest", "Cricket", "Crimson", "Cross", "Crown",
	"Cruise", "Crush", "Crystal", "Cube", "Cyclone", "Cypress",
	# --- D ---
	"Dagger", "Dancer", "Dare", "Dart", "Dawn", "Dealer", "Decoy", "Delta",
	"Demon", "Depth", "Derby", "Desert", "Devil", "Dew", "Diamond", "Diesel",
	"Dingo", "Dirge", "Disco", "Dispatch", "Diver", "Dock", "Dodge", "Dollar",
	"Dolphin", "Doom", "Dragon", "Drake", "Dream", "Drift", "Drill", "Driver",
	"Drone", "Duel", "Duke", "Dune", "Dusk", "Dust", "Dynamo",
	# --- E ---
	"Eagle", "Echo", "Eclipse", "Edge", "Elder", "Ember", "Empire", "Enigma",
	"Epoch", "Equinox", "Ergo", "Escape", "Ethos", "Everest", "Exile", "Exodus",
	"Express", "Extent", "Eye",
	# --- F ---
	"Fable", "Falcon", "Fang", "Fare", "Faze", "Fenrir", "Fern", "Ferret",
	"Ferry", "Fever", "Fiber", "Fiddler", "Fierce", "Finch", "Fire", "Fission",
	"Fjord", "Flag", "Flame", "Flank", "Flare", "Flash", "Fleet", "Flicker",
	"Flight", "Flinch", "Flint", "Flood", "Flora", "Flow", "Flux", "Focus",
	"Fog", "Forge", "Fork", "Fortress", "Fossil", "Fox", "Fracture", "Freight",
	"Frost", "Fuel", "Fury", "Fusion", "Fuse",
	# --- G ---
	"Gale", "Gallop", "Gambit", "Gamma", "Garnet", "Gate", "Gauge", "Gazer",
	"Gear", "Gemini", "Genesis", "Ghost", "Giant", "Glacier", "Glade", "Glare",
	"Glass", "Gleam", "Glider", "Globe", "Glow", "Goblin", "Gold", "Goliath",
	"Gorge", "Grain", "Granite", "Graph", "Grasp", "Gravel", "Gravity", "Grid",
	"Griffin", "Grim", "Grind", "Grip", "Grizzly", "Grove", "Guard", "Guide",
	"Gulf", "Gust", "Gypsy",
	# --- H ---
	"Hail", "Halo", "Hammer", "Harbor", "Harpoon", "Harvest", "Hasty", "Haven",
	"Hawk", "Haze", "Helix", "Herald", "Hex", "Horizon", "Hornet", "Howl",
	"Hudson", "Hulk", "Hunter", "Hustle", "Hydra", "Hymn",
	# --- I ---
	"Iceberg", "Icon", "Ignite", "Impact", "Impulse", "Index", "Indie", "Inferno",
	"Ink", "Instinct", "Intake", "Ion", "Iron", "Isle", "Ivory", "Ivy",
	# --- J ---
	"Jackal", "Jade", "Jaguar", "Javelin", "Jazz", "Jester", "Jet", "Jigsaw",
	"Jinx", "Joker", "Jolt", "Judge", "Juice", "Jump", "Jungle", "Jupiter",
	# --- K ---
	"Karma", "Keen", "Keeper", "Kelvin", "Kernel", "Kestrel", "Khan", "Kindle",
	"King", "Kite", "Klaxon", "Knight", "Knot", "Kodiak", "Kraken", "Krypton",
	# --- L ---
	"Lancer", "Lantern", "Lark", "Laser", "Latch", "Lava", "Lead", "Legend",
	"Legion", "Lens", "Leopard", "Level", "Lever", "Liberty", "Light", "Lime",
	"Linden", "Link", "Lion", "Litmus", "Lock", "Locus", "Lodge", "Logic",
	"Lone", "Lotus", "Luck", "Lunar", "Lynx",
	# --- M ---
	"Mace", "Magma", "Magnet", "Maiden", "Major", "Mamba", "Mammoth", "Mantle",
	"Maple", "Marble", "March", "Margin", "Marlin", "Mars", "Marshal", "Mason",
	"Mast", "Matrix", "Maverick", "Meadow", "Medic", "Mercury", "Mesa", "Meteor",
	"Metro", "Mica", "Might", "Mirage", "Mirror", "Mist", "Moat", "Monarch",
	"Monsoon", "Moon", "Mortar", "Moth", "Motor", "Mustang", "Mystic",
	# --- N ---
	"Nebula", "Nectar", "Needle", "Neon", "Neptune", "Nerve", "Nest", "Nexus",
	"Night", "Nimbus", "Noble", "Node", "Nomad", "Nordic", "North", "Nova",
	"Null", "Nymph",
	# --- O ---
	"Oak", "Oasis", "Obsidian", "Ocean", "Octane", "Omega", "Onyx", "Opal",
	"Orbit", "Orca", "Ore", "Origin", "Orion", "Osprey", "Outlaw", "Outpost",
	"Oxide", "Ozone",
	# --- P ---
	"Pace", "Panda", "Panther", "Paragon", "Patch", "Patriot", "Peak", "Pebble",
	"Pelican", "Penny", "Pepper", "Phantom", "Phoenix", "Pike", "Pilot", "Pine",
	"Pioneer", "Piston", "Pivot", "Plasma", "Pluto", "Point", "Polar", "Polaris",
	"Portal", "Praxis", "Predator", "Presto", "Prism", "Probe", "Prophet", "Prowl",
	"Pulse", "Puma", "Punk", "Pyro",
	# --- Q ---
	"Quake", "Quantum", "Quarry", "Quartz", "Quest", "Quick", "Quill", "Quirk",
	# --- R ---
	"Radar", "Radiant", "Rage", "Raider", "Rain", "Rally", "Ram", "Rampart",
	"Range", "Ranger", "Rapier", "Raptor", "Rascal", "Raven", "Razor", "Rebel",
	"Recon", "Reed", "Reef", "Reflex", "Relay", "Relic", "Render", "Rex",
	"Ridge", "Rifle", "Rift", "Riot", "Ripple", "Rising", "River", "Rivet",
	"Roam", "Robin", "Rocket", "Rogue", "Root", "Rotor", "Rover", "Royal",
	"Rubble", "Ruby", "Rumble", "Rune", "Runner", "Rush", "Rustic", "Rye",
	# --- S ---
	"Saber", "Sage", "Sail", "Salem", "Salt", "Salvo", "Sand", "Sapphire",
	"Saturn", "Savage", "Scale", "Scar", "Scout", "Scribe", "Seal", "Sector",
	"Seed", "Sentinel", "Serpent", "Shadow", "Shard", "Shark", "Shell", "Shield",
	"Shimmer", "Shore", "Shroud", "Siege", "Sierra", "Signal", "Silk", "Silver",
	"Siren", "Sketch", "Skull", "Slate", "Sledge", "Sleet", "Slice", "Slide",
	"Sling", "Slope", "Smoke", "Snap", "Snare", "Snow", "Solar", "Solstice",
	"Sonic", "Soot", "Sorcerer", "Spark", "Sparrow", "Spear", "Specter", "Sphere",
	"Sphinx", "Spike", "Spiral", "Spirit", "Splash", "Spore", "Spring", "Spruce",
	"Spur", "Squad", "Squall", "Stag", "Stake", "Stalker", "Stampede", "Star",
	"Static", "Steam", "Steel", "Steppe", "Sterling", "Sting", "Stoic", "Stone",
	"Storm", "Stout", "Strand", "Strike", "Strobe", "Stryker", "Stump", "Summit",
	"Sun", "Surge", "Swallow", "Swan", "Swarm", "Swift", "Sword",
	# --- T ---
	"Tactic", "Talon", "Tank", "Tango", "Taper", "Tarn", "Tempest", "Temple",
	"Tender", "Terra", "Tether", "Thermal", "Thorn", "Thunder", "Tide", "Tiger",
	"Timber", "Titan", "Token", "Tomb", "Torch", "Torque", "Tower", "Trace",
	"Trail", "Trap", "Tremor", "Trident", "Trigger", "Trinity", "Trojan", "Tundra",
	"Turbine", "Tusk", "Twilight", "Twister", "Typhoon",
	# --- U ---
	"Umbra", "Union", "Unity", "Uplift", "Uranium", "Urchin", "Utopia",
	# --- V ---
	"Vagabond", "Vale", "Valor", "Valve", "Vandal", "Vanguard", "Vapor", "Vector",
	"Veil", "Velvet", "Venom", "Venture", "Verdict", "Verge", "Vertex", "Vestal",
	"Vex", "Vibe", "Vigor", "Vine", "Viper", "Virtue", "Vision", "Vivid",
	"Void", "Volt", "Vortex", "Voyage", "Vulcan", "Vulture",
	# --- W ---
	"Wander", "Warden", "Warrant", "Wasp", "Watch", "Wave", "Wedge", "Whisper",
	"Widow", "Wild", "Willow", "Wind", "Wing", "Winter", "Wire", "Wizard",
	"Wolf", "Wonder", "Wraith", "Wren",
	# --- X ---
	"Xenon", "Xerxes",
	# --- Y ---
	"Yak", "Yard", "Yawn", "Yeti", "Yield", "Yoke",
	# --- Z ---
	"Zeal", "Zenith", "Zephyr", "Zero", "Zinc", "Zone", "Zodiac",
	# --- 补充（凑满 800）---
	"Alloy", "Azure", "Bastion", "Blizzard", "Brawler", "Buffer", "Bulwark", "Cadet",
	"Calibre", "Cinder", "Claymore", "Clipper", "Cobalt", "Coda", "Concord", "Cooper",
	"Draco", "Elixir", "Fractal", "Gallant", "Gauntlet", "Glint", "Harrier", "Helm",
	"Ibex", "Ingot", "Kaolin", "Lance", "Mantra", "Marsh", "Nimble", "Ocelot",
	"Paladin", "Peregrine", "Pinnacle", "Rambler", "Rapture", "Ridgeback", "Rime",
	"Roost", "Sandstorm", "Scarab", "Scud", "Shoal", "Spade", "Strider", "Taiga",
	"Templar", "Tigress", "Torrent", "Traverse", "Vista", "Wyvern",
]
