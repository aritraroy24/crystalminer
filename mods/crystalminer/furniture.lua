-- Furniture and sculptures for the museum: carpets, benches, plants, plinths, an information desk,
-- a plan of the building, and the sculptures of sculptures.lua.

local cm = crystalminer
local SG = cm.SG
local GROUND = cm.GROUND_Y
local SC = dofile(core.get_modpath(core.get_current_modname()) .. "/sculptures.lua")
local LAYOUT = dofile(core.get_modpath(core.get_current_modname()) .. "/gallery2_layout.lua")
cm.SCULPTURES = SC
cm.gallery2_layout = LAYOUT

local function node(name, desc, tiles, box, extra)
	local def = { description = desc, drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir",
		tiles = tiles, node_box = { type = "fixed", fixed = box }, groups = { not_in_creative_inventory = 1 },
		is_ground_content = false, sunlight_propagates = true, sounds = cm.node_sounds("hard") }
	for k, v in pairs(extra or {}) do def[k] = v end
	core.register_node("crystalminer:" .. name, def)
end

node("carpet", "Carpet", { "crystalminer_carpet.png" }, { -0.5, -0.5, -0.5, 0.5, -0.4375, 0.5 },
	{ sounds = cm.node_sounds("soft") })
node("bench", "Bench", { "crystalminer_planks.png" }, {
	{ -0.5, -0.06, -0.3, 0.5, 0.06, 0.3 },
	{ -0.45, -0.5, -0.25, -0.33, -0.06, 0.25 }, { 0.33, -0.5, -0.25, 0.45, -0.06, 0.25 },
}, { sounds = cm.node_sounds("wood") })
node("pot", "Plant pot", { "crystalminer_soil.png", "crystalminer_pot.png", "crystalminer_pot.png" },
	{ -0.3, -0.5, -0.3, 0.3, 0.2, 0.3 })
core.register_node("crystalminer:plant", {
	description = "Plant", drawtype = "plantlike", tiles = { "crystalminer_plant.png" }, visual_scale = 1.4,
	paramtype = "light", sunlight_propagates = true, walkable = false, use_texture_alpha = "clip",
	groups = { not_in_creative_inventory = 1 }, is_ground_content = false, sounds = cm.node_sounds("soft"),
})
core.register_node("crystalminer:marble", {
	description = "Marble", tiles = { "crystalminer_marble.png" }, groups = { not_in_creative_inventory = 1 },
	is_ground_content = false, sounds = cm.node_sounds("hard"),
})
node("post", "Brass post", { "crystalminer_brass.png" }, {
	{ -0.08, -0.5, -0.08, 0.08, 0.35, 0.08 }, { -0.14, 0.35, -0.14, 0.14, 0.5, 0.14 }, { -0.2, -0.5, -0.2, 0.2, -0.4, 0.2 },
})

local function set(x, y, z, name, p2) core.set_node({ x = x, y = y, z = z }, { name = name, param2 = p2 or 0 }) end

-- facedir for a bench whose sitter faces north (0), east (1), south (2) or west (3).
local FACE = { n = 0, e = 1, s = 2, w = 3 }

local function bench(x0, x1, z0, z1, face)
	for x = x0, x1 do for z = z0, z1 do set(x, GROUND + 1, z, "crystalminer:bench", FACE[face]) end end
end

local function plant(x, z)
	set(x, GROUND + 1, z, "crystalminer:pot")
	set(x, GROUND + 2, z, "crystalminer:plant")
end

local function carpet(x0, x1, z0, z1)
	for x = x0, x1 do
		for z = z0, z1 do
			if core.get_node({ x = x, y = GROUND + 1, z = z }).name == "air" then set(x, GROUND + 1, z, "crystalminer:carpet") end
		end
	end
end

--- A sculpture on a 3 x 3 marble plinth (or 5 x 5 for a wide one), with its plaque in front (south).
local function sculpture(s)
	local cx, cz = s.at[1], s.at[2]
	local r = 1
	for _, b in ipairs(s.blocks) do r = math.max(r, math.abs(b[1]), math.abs(b[3])) end
	r = math.min(r, 3)
	for x = cx - r, cx + r do for z = cz - r, cz + r do set(x, GROUND + 1, z, "crystalminer:marble") end end
	for _, b in ipairs(s.blocks) do set(cx + b[1], GROUND + 2 + b[2], cz + b[3], "crystalminer:" .. b[4]) end
	SG.place({ x = cx, y = GROUND + 1.25, z = cz - r - 1.1 }, "s", "plaque", s.plaque)
	-- Brass posts at the corners keep visitors at a respectful distance.
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		set(cx + c[1] * (r + 1), GROUND + 1, cz + c[2] * (r + 1), "crystalminer:post")
	end
end

local function furnish()
	-- Foyer: a red carpet from the front door to Gallery 1, plants by both doors, two sculptures.
	carpet(-1, 0, -49, -31)
	for _, p in ipairs({ { -3, -49 }, { 2, -49 }, { -3, -31 }, { 2, -31 }, { -20, -49 }, { 20, -49 } }) do plant(p[1], p[2]) end
	bench(-17, -15, -46, -46, "n")
	bench(15, 17, -46, -46, "n")
	-- Workshop: plants in the corners, benches behind the levers.
	for _, p in ipairs({ { -59, -49 }, { -22, -49 }, { -59, -31 }, { -22, -31 } }) do plant(p[1], p[2]) end
	bench(-33, -31, -33, -33, "s")
	bench(-57, -55, -33, -33, "s")
	-- Visitor information: a desk and plants. Prism, the AI tutor, sits on the desk (tutor_window.lua), with its billboard high on the wall behind (billboard.lua); the banner is on the desk's front, below Prism's screen.
	for x = 36, 44 do
		set(x, GROUND + 1, -45, "crystalminer:planks")
		set(x, GROUND + 2, -45, "crystalminer:marble")
	end
	SG.place({ x = 40, y = GROUND + 1.5, z = -45 + 0.52 }, "n", "banner", cm.content.tutor.desk)
	for _, p in ipairs({ { 22, -49 }, { 59, -49 }, { 59, -31 } }) do plant(p[1], p[2]) end
	bench(26, 28, -36, -36, "n")
	-- Gallery 1: benches facing the displays, plants in the corners.
	-- (between the lines of sight to the displays, which run north from x = -21, -7, 7 and 21)
	bench(-16, -12, -9, -9, "s")
	bench(-2, 2, -9, -9, "s")
	bench(12, 16, -9, -9, "s")
	for _, p in ipairs({ { -59, -29 }, { 59, -29 }, { -59, -5 }, { 59, -5 } }) do plant(p[1], p[2]) end
	-- Gallery 2: a carpet along the timeline, benches facing the panels, plants.
	carpet(LAYOUT.carpet.x0, LAYOUT.carpet.x1, LAYOUT.carpet.z0, LAYOUT.carpet.z1)
	for _, b in ipairs(LAYOUT.benches) do bench(b.x0, b.x1, b.z0, b.z1, b.face) end
	for _, p in ipairs({ { -59, -3 }, { -17, -3 }, { -59, 59 }, { -17, 59 } }) do plant(p[1], p[2]) end
	-- Gallery 3: plants in the corners (the models fill the room).
	for _, p in ipairs({ { -15, -3 }, { -15, 59 } }) do plant(p[1], p[2]) end
	-- Portal Hall: benches, a carpet along the portals, plants.
	carpet(-57, 57, 84, 85)
	for x = -45, 45, 30 do bench(x - 2, x + 2, 72, 72, "n") end
	for _, p in ipairs({ { -59, 61 }, { 59, 61 } }) do plant(p[1], p[2]) end
	for _, s in ipairs(SC.list) do sculpture(s) end
	-- The plan of the museum, at eye level in the foyer just east of the front door, where its small lettering can be read (tools/make_figures.py marks "you are here" there).
	SG.place_picture({ x = 7, y = GROUND + 2.6, z = cm.lobby.Z0 + 0.52 }, "n", "crystalminer_art_plan.png", 4, 3)
	-- Framed pictures: the four kinds of symmetry, in the foyer opposite the welcome board.
	SG.place_picture({ x = 8, y = GROUND + 4.5, z = -30 - 0.52 }, "s", "crystalminer_art_four.png", 4.4, 4.4)
end
cm.furnish = furnish

local function migrate_gallery2()
	cm.load_region({ min = { -61, 0, -5 }, size = { 47, 5, 67 } })
	for _, x in ipairs({ -50, -26 }) do
		for _, z0 in ipairs({ 7, 39 }) do
			for z = z0, z0 + 2 do set(x, GROUND + 1, z, "air") end
		end
	end
	carpet(LAYOUT.carpet.x0, LAYOUT.carpet.x1, LAYOUT.carpet.z0, LAYOUT.carpet.z1)
	for _, b in ipairs(LAYOUT.benches) do bench(b.x0, b.x1, b.z0, b.z1, b.face) end
	cm.storage:set_string("gallery2_layout", "1")
end

table.insert(cm.on_build, function()
	furnish()
	cm.storage:set_string("gallery2_layout", "1")
end)
cm.when_ready(function()
	if cm.storage:get_string("gallery2_layout") ~= "1" then migrate_gallery2() end
end)
