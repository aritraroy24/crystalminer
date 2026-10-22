-- The Museum of Crystals and Symmetry: the building everyone starts in, after the central hall of
-- MolCraft (University of Hull). Purely exhibits to walk through, read and explore:
--
--   Foyer (spawn)      | Workshop (Try-it Pad, west) | Visitor information (east)
--   Gallery 1: Four kinds of symmetry (the Gate's Displays A-D)
--   Gallery 2: A history of crystallography (west) | Gallery 3: Crystals at the atomic scale (museum.lua)
--   Portal Hall: one portal to every symmetry world
--
-- Positions are here; every word on the signs is in content.lua (content.lobby).

local cm = crystalminer
local content, G = cm.content, cm.G
local SG = cm.SG
local LB = content.lobby
local GROUND = cm.GROUND_Y

local X0, X1, Z0, Z1 = -60, 60, -50, 90       -- outer walls
local TOP = 19                                 -- top of the outer walls; the roof is at TOP + 1
local INNER = 9                                -- height of the walls between rooms
local L = { X0 = X0, X1 = X1, Z0 = Z0, Z1 = Z1, TOP = TOP }
cm.lobby = L

-- Walls between rooms: { fixed coordinate axis, value, from, to, doorways = { first of 2 } }.
L.WALLS = {
	{ "z", -30, X0 + 1, X1 - 1, { -1, -41, 39 } },   -- foyer, workshop, information | Gallery 1
	{ "x", -21, Z0 + 1, -31, { -41 } },              -- workshop | foyer
	{ "x", 21, Z0 + 1, -31, { -41 } },               -- foyer | information
	{ "z", -4, X0 + 1, X1 - 1, { -41, 21 } },        -- Gallery 1 | Galleries 2 and 3
	{ "x", -16, -3, 59, { 20 } },                    -- Gallery 2 | Gallery 3
	{ "z", 60, X0 + 1, X1 - 1, { -41, 21 } },        -- Galleries 2 and 3 | Portal Hall
}
L.ENTRANCE = { -1, 0 }                             -- x of the double front door in the south wall
L.PORTAL_Z = 87

cm.extra_boxes[#cm.extra_boxes + 1] = { min = { X0 - 2, GROUND - 1, Z0 - 6 }, size = { X1 - X0 + 5, TOP + 6, Z1 - Z0 + 9 } }

local function set(x, y, z, name) core.set_node({ x = x, y = y, z = z }, { name = name }) end

local function is_doorway(w, t)
	for _, d in ipairs(w[5]) do
		if t == d then return "first" end
		if t == d + 1 then return "second" end
	end
	return false
end

---------------------------------------------------------------------------- the building

local function floor_and_roof()
	for x = X0, X1 do
		for z = Z0, Z1 do
			-- Keep the floors of the displays and the Try-it Pad, which were built first.
			local cur = core.get_node({ x = x, y = GROUND, z = z }).name
			if cur ~= "crystalminer:floor" then set(x, GROUND, z, "crystalminer:plaza") end
			local beam = (x - X0) % 6 == 0 or (z - Z0) % 6 == 0
			set(x, TOP + 1, z, beam and "crystalminer:stone_brick" or "crystalminer:roof_glass")
		end
	end
end

local function outer_walls()
	for x = X0, X1 do
		for z = Z0, Z1 do
			if x == X0 or x == X1 or z == Z0 or z == Z1 then
				local along = (z == Z0 or z == Z1) and x or z
				local corner = (x == X0 or x == X1) and (z == Z0 or z == Z1)
				for y = GROUND + 1, TOP do
					local name = "crystalminer:stone_brick"
					if not corner and along % 10 == 0 then
						name = "crystalminer:pillar"
					elseif not corner and along % 5 ~= 0 and y >= 4 and y <= 8 and along % 10 ~= 5 then
						name = "crystalminer:roof_glass"   -- windows
					elseif y == TOP then
						name = "crystalminer:brick"
					end
					set(x, y, z, name)
				end
			end
		end
	end
	-- The front door: a double door under a stone lintel.
	for _, x in ipairs(L.ENTRANCE) do
		for y = GROUND + 1, GROUND + 3 do set(x, y, Z0, "air") end
		cm.place_door({ x = x, y = GROUND + 1, z = Z0 }, "x", false, x == L.ENTRANCE[2])
	end
	for y = GROUND + 1, GROUND + 4 do
		set(L.ENTRANCE[1] - 1, y, Z0, "crystalminer:pillar")
		set(L.ENTRANCE[2] + 1, y, Z0, "crystalminer:pillar")
	end
end

local function inner_walls()
	for _, w in ipairs(L.WALLS) do
		local axis, v, a, b = w[1], w[2], w[3], w[4]
		for t = a, b do
			local x, z = axis == "z" and t or v, axis == "z" and v or t
			local door = is_doorway(w, t)
			for y = GROUND + 1, GROUND + INNER do
				local name = y == GROUND + INNER and "crystalminer:stone_brick" or "crystalminer:brick"
				-- Doorways are 3 high (the door leaves 2): room overhead for a visitor who is flying.
				if door and y <= GROUND + 3 then name = "air" end
				if door and y == GROUND + 4 then name = "crystalminer:stone_brick" end
				set(x, y, z, name)
			end
			-- A wall at fixed z runs along x, and so does its doorway.
			if door then
				cm.place_door({ x = x, y = GROUND + 1, z = z }, axis == "z" and "x" or "z", true, door == "second")
			end
		end
	end
end

-- Haüy's idea, in blocks: identical cubes stacked so that they make an octahedron with stepped
-- faces (|x| + |y| + |z| <= 4).
local function hauy_model(cx, cz)
	for x = -4, 4 do
		for y = -4, 4 do
			for z = -4, 4 do
				if math.abs(x) + math.abs(y) + math.abs(z) <= 4 then set(cx + x, GROUND + 6 + y, cz + z, "crystalminer:light_grey") end
			end
		end
	end
	for y = GROUND + 1, GROUND + 1 do
		for x = cx - 1, cx + 1 do
			for z = cz - 1, cz + 1 do set(x, y, z, "crystalminer:stone_brick") end
		end
	end
end
L.HAUY = { x = -38, z = 20 }

---------------------------------------------------------------------------- portals

--- Regions in the order the Portal Hall shows them: by tier, then as listed in content.lua.
local function portal_order()
	local list = {}
	for i, live in ipairs(cm.regions) do list[#list + 1] = { live = live, i = i } end
	table.sort(list, function(a, b)
		if a.live.area.tier ~= b.live.area.tier then return a.live.area.tier < b.live.area.tier end
		return a.i < b.i
	end)
	return list
end

--- One portal per region along the north wall: { x, live }.
local function portals()
	local out = {}
	for k, e in ipairs(portal_order()) do out[#out + 1] = { x = X0 + 5 + (k - 1) * 5, live = e.live } end
	return out
end
L.portals = portals

local function short_idea(area)
	local lines = (area.explain or {})[area.tier] or {}
	return lines[1] or ""
end

function L.portal_text(live)
	local a = live.area
	return "# " .. a.name .. "\n## Symmetry " .. live.symbol .. " · tier " .. a.tier .. "\n" .. short_idea(a)
end

local function build_portals()
	for _, p in ipairs(portals()) do
		local x, z = p.x, L.PORTAL_Z
		-- An alcove: two pillars, a lintel, a tier-coloured step and the portal pad.
		for y = GROUND + 1, GROUND + 4 do
			set(x - 2, y, z + 1, "crystalminer:pillar")
			set(x + 2, y, z + 1, "crystalminer:pillar")
		end
		for xx = x - 2, x + 2 do set(xx, GROUND + 5, z + 1, "crystalminer:stone_brick") end
		set(x, GROUND, z, "crystalminer:border_" .. math.min(p.live.area.tier, 4))
		set(x, GROUND + 1, z, "crystalminer:teleporter")
		local meta = core.get_meta({ x = x, y = GROUND + 1, z = z })
		meta:set_string("target", p.live.area.id)
		meta:set_string("infotext", "Portal to " .. p.live.area.name .. " (punch it)")
		-- The plaque hangs between the alcove's pillars, flush with their front, so that the
		-- pillars frame it instead of hiding its edges.
		SG.on_wall({ x = x, y = GROUND + 3, z = z + 1 }, "s", "plaque", L.portal_text(p.live), nil,
			{ tier = p.live.area.tier })
	end
end

---------------------------------------------------------------------------- signs

local function build_signs()
	-- Outside, over the front door.
	SG.on_wall({ x = -0.5, y = GROUND + 6, z = Z0 }, "s", "banner", "# MUSEUM OF CRYSTALS AND SYMMETRY\nWelcome. The doors open with a click.")
	-- Foyer.
	SG.on_wall({ x = -8, y = GROUND + 4, z = -30 }, "s", "board", LB.welcome)
	SG.on_wall({ x = -0.5, y = GROUND + 5.5, z = -30 }, "s", "banner", "# GALLERY 1\nFour kinds of symmetry")
	SG.on_wall({ x = -21, y = GROUND + 5.5, z = -40.5 }, "e", "banner", "# WORKSHOP\nThe Try-it Pad")
	SG.on_wall({ x = 21, y = GROUND + 5.5, z = -40.5 }, "w", "banner", "# VISITOR INFORMATION\nHow to explore · Ask Prism, the AI tutor")
	-- Workshop and information room.
	local GD = cm.GUIDES
	SG.on_wall({ x = -50, y = GROUND + 4, z = -30 }, "s", "board", GD.board_text(GD.tryit_pad))
	-- At the Try-it Pad itself: a board beside the boxes, facing a player at the levers, a sign above
	-- each box and a label above each lever.
	-- A board on its own wall beside the pad, to the left of a player at the levers.
	for x = -34, -28 do
		for y = GROUND + 1, GROUND + 6 do core.set_node({ x = x, y = y, z = -44 }, { name = "crystalminer:stone_brick" }) end
	end
	SG.on_wall({ x = -31, y = GROUND + 3.6, z = -44 }, "n", "board", GD.board_text(GD.tryit_pad))
	local B, R = cm.PAD_BUILD, cm.PAD_RESULT
	SG.place({ x = B.x + 2, y = GROUND + 7.4, z = B.z + 2 }, "n", "plaque", "# YOUR SHAPE\nBuild your shape in this box.")
	SG.place({ x = R.x + 2, y = GROUND + 7.4, z = R.z + 2 }, "n", "plaque", "# COPY\nThe lever's copy appears here.")
	for _, lever in ipairs(cm.LEVERS) do
		local word = lever.text:match("^%a: (.*)$")
		SG.place({ x = lever.x, y = GROUND + 2.2, z = cm.LEVER_Z }, "n", "label", "# " .. lever.letter .. "\n" .. word)
	end
	SG.on_wall({ x = 30, y = GROUND + 4, z = -30 }, "s", "board", LB.information)
	local words = { "# Words to know" }
	for i = 1, 9 do words[#words + 1] = content.glossary[i] end
	SG.on_wall({ x = 50, y = GROUND + 4, z = -30 }, "s", "board", table.concat(words, "\n"))
	-- Gallery 1: the introduction on the north wall, a plaque above each display, doorway banners.
	SG.on_wall({ x = 0, y = GROUND + 4, z = -4 }, "s", "board", GD.board_text(GD.symmetry_gate))
	for _, d in ipairs(G.displays(content.gate.at)) do
		SG.on_wall({ x = d.look_at.x, y = GROUND + 7.5, z = -30 }, "n", "plaque", string.format(LB.display, d.letter))
	end
	SG.on_wall({ x = -40.5, y = GROUND + 5.5, z = -4 }, "s", "banner", "# GALLERY 2\nA history of crystallography")
	SG.on_wall({ x = 21.5, y = GROUND + 5.5, z = -4 }, "s", "banner", "# GALLERY 3\nCrystals at the atomic scale")
	SG.on_wall({ x = -40.5, y = GROUND + 5.5, z = -30 }, "n", "banner", "# WORKSHOP\nThe Try-it Pad")
	SG.on_wall({ x = -0.5, y = GROUND + 5.5, z = -30 }, "n", "banner", "# FOYER\nWay out, welcome and map")
	SG.on_wall({ x = 39.5, y = GROUND + 5.5, z = -30 }, "n", "banner", "# VISITOR INFORMATION\nHow to explore · Ask Prism, the AI tutor")
	-- Gallery 2: the introduction at the far end, then the timeline, alternating west and east.
	SG.on_wall({ x = -32, y = GROUND + 4, z = 60 }, "s", "board", LB.gallery2)
	local slots = { 4, 12, 28, 36, 44, 52 }
	for i, h in ipairs(LB.history) do
		local k = math.floor((i - 1) / 2) + 1
		local west = i % 2 == 1
		SG.on_wall({ x = west and X0 or -16, y = GROUND + 3, z = slots[k] }, west and "e" or "w", "panel",
			"# " .. h.year .. "  " .. h.who .. "\n" .. h.text)
		-- Above each panel, a diagram of the idea.
		local d = west and 1 or -1
		SG.place_picture({ x = (west and X0 or -16) + d * 0.52, y = GROUND + 6.3, z = slots[k] }, west and "e" or "w",
			"crystalminer_hist_" .. h.year .. ".png", 3.6, 2.7)
	end
	SG.on_wall({ x = L.HAUY.x, y = GROUND + 2, z = L.HAUY.z - 2 }, "s", "plaque",
		"# Haüy's idea, in blocks\nIdentical cubes, stacked, make an octahedron with stepped faces. From far away the steps vanish and the faces look flat.")
	-- Gallery 3 and the Portal Hall.
	SG.on_wall({ x = 40, y = GROUND + 4, z = -4 }, "n", "board", LB.gallery3)
	SG.on_wall({ x = -10, y = GROUND + 4, z = 60 }, "n", "board", LB.portals)
	SG.on_wall({ x = -40.5, y = GROUND + 5.5, z = 60 }, "s", "banner", "# PORTAL HALL\nTo the symmetry worlds")
	SG.on_wall({ x = 21.5, y = GROUND + 5.5, z = 60 }, "s", "banner", "# PORTAL HALL\nTo the symmetry worlds")
end

-- Clear the whole volume first: in a world made by an earlier version, regions stood here.
table.insert(cm.on_clear, function()
	cm.fill_fast(X0, X1, GROUND + 1, TOP + 2, Z0, Z1, "air")
	for _, obj in ipairs(core.get_objects_inside_radius({ x = 0, y = 10, z = 20 }, 110)) do
		local e = obj:get_luaentity()
		if e and (e.name == "crystalminer:sign" or e.name == "crystalminer:label") then obj:remove() end
	end
end)

table.insert(cm.before_build, function()
	cm.load_region({ min = { X0, GROUND - 1, Z0 }, size = { X1 - X0 + 1, TOP + 3, Z1 - Z0 + 1 } })
	floor_and_roof()
	outer_walls()
	inner_walls()
	hauy_model(L.HAUY.x, L.HAUY.z)
end)

table.insert(cm.on_build, function()
	build_portals()
	build_signs()
end)

-- The museum is for looking at: only teachers can change its walls and exhibits. The Try-it Pad's
-- boxes stay open to everyone.
local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if name ~= "" and pos.x >= X0 and pos.x <= X1 and pos.z >= Z0 and pos.z <= Z1 and pos.y <= TOP + 1
		and not cm.in_pad(pos) and not core.check_player_privs(name, { teacher = true }) then
		return true
	end
	return old_is_protected(pos, name)
end

table.insert(cm.on_teleport, function(name, id, player)
	if id == "portal_hall" then
		player:set_pos({ x = 0, y = GROUND + 1, z = 70 })
		player:set_look_horizontal(0)
		player:set_look_vertical(0)
		return true
	end
	if id == "foyer" then
		player:set_pos(LB.spawn)
		player:set_look_horizontal(0)
		return true
	end
end)
