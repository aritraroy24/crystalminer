-- Records the Museum of Crystals and Symmetry exactly as crystalminer builds it, for the web version: every block (name and param2) in the museum and the exhibit rooms, the metadata that drives behaviour (portal targets, clue crystals), the definition of every kind of block used, every sign and picture with its texture recipe, and the positions of the rooms, the Try-it Pad, Prism's billboard and the NPCs. Run by tools/export_museum.sh in a fresh world on a headless server; writes museum.json into the world folder and shuts the server down.
local cm = crystalminer
local SG = cm.SG

---------------------------------------------------------------------------- signs and pictures, as the build places them

-- Every sign and picture of the museum goes through SG.place or SG.place_picture (SG.on_wall calls SG.place), so wrapping the two records them all, whatever their entities do later.
local signs, pictures = {}, {}
local place, place_picture = SG.place, SG.place_picture
SG.place = function(pos, dir, format, text, opts)
	local tex, fits, w, h = SG.texture(format, text, opts)
	-- As in the game, a sign placed where one already is replaces it (the Gallery 2 hologram plaques are placed again once the museum is ready). holo: the pedestal whose plaque this is, which the web version re-letters for the room's current structure.
	local at = { pos.x, pos.y, pos.z }
	for i = #signs, 1, -1 do
		local q = signs[i].pos
		if math.abs(q[1] - at[1]) < 0.6 and math.abs(q[2] - at[2]) < 0.6 and math.abs(q[3] - at[3]) < 0.6 then table.remove(signs, i) end
	end
	signs[#signs + 1] = { pos = at, dir = dir, format = format, text = text, tier = opts and opts.tier, holo = opts and opts.holo_pedestal,
		texture = tex, fits = fits, w = w, h = h }
	return place(pos, dir, format, text, opts)
end
SG.place_picture = function(pos, dir, texture, w, h)
	pictures[#pictures + 1] = { pos = { pos.x, pos.y, pos.z }, dir = dir, texture = texture, w = w, h = h }
	return place_picture(pos, dir, texture, w, h)
end

---------------------------------------------------------------------------- helpers

local function tile_name(t)
	if type(t) == "table" then t = t.name or t.image end
	return type(t) == "string" and t or nil
end

-- What the web needs to draw a kind of block and to know whether it can be walked through.
local function definition(name)
	local d = core.registered_nodes[name]
	if not d then return { unknown = true } end
	local tiles = {}
	for i, t in ipairs(d.tiles or {}) do tiles[i] = tile_name(t) end
	local box = d.node_box and d.node_box.type == "fixed" and d.node_box.fixed or nil
	if box and type(box[1]) == "number" then box = { box } end
	return {
		drawtype = d.drawtype or "normal", tiles = tiles, node_box = box, visual_scale = d.visual_scale,
		walkable = d.walkable ~= false, light_source = d.light_source, paramtype2 = d.paramtype2,
		alpha = d.use_texture_alpha, mesh = d.mesh, description = d.description,
	}
end

local function read_box(min, max, palette, index, nodes)
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(min, max)
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data, p2 = vm:get_data(), vm:get_param2_data()
	local air = core.get_content_id("air")
	local ignore = core.get_content_id("ignore")
	local missing = 0
	for z = min.z, max.z do
		for y = min.y, max.y do
			for x = min.x, max.x do
				local i = area:index(x, y, z)
				local id = data[i]
				if id == ignore then
					missing = missing + 1
				elseif id ~= air then
					local name = core.get_name_from_content_id(id)
					if not index[name] then
						palette[#palette + 1] = name
						index[name] = #palette
					end
					local n = #nodes
					nodes[n + 1], nodes[n + 2], nodes[n + 3], nodes[n + 4], nodes[n + 5] = x, y, z, index[name] - 1, p2[i]
				end
			end
		end
	end
	return missing
end

---------------------------------------------------------------------------- the dump

-- From the floor (y = 0) up: the dirt below it is never seen.
local MUSEUM = { min = { x = -60, y = 0, z = -51 }, max = { x = 60, y = 21, z = 90 } }

local function dump()
	local L = cm.lobby
	local palette, index, nodes = {}, {}, {}
	local boxes = { { id = "museum", min = MUSEUM.min, max = MUSEUM.max } }
	for _, room in ipairs(cm.exhibit_rooms or {}) do
		boxes[#boxes + 1] = { id = room.id, min = { x = room.min[1], y = math.max(0, room.min[2]), z = room.min[3] },
			max = { x = room.min[1] + room.size[1] - 1, y = room.min[2] + room.size[2] - 1, z = room.min[3] + room.size[3] - 1 } }
	end
	local missing = 0
	for _, b in ipairs(boxes) do missing = missing + read_box(b.min, b.max, palette, index, nodes) end

	local meta = {}
	for _, b in ipairs(boxes) do
		for _, pos in ipairs(core.find_nodes_with_meta(b.min, b.max)) do
			local m = core.get_meta(pos)
			local e = { pos = { pos.x, pos.y, pos.z }, target = m:get_string("target"), exhibit = m:get_string("exhibit"), infotext = m:get_string("infotext") }
			for k, v in pairs(e) do if v == "" then e[k] = nil end end
			meta[#meta + 1] = e
		end
	end
	table.sort(meta, function(a, b)
		for i = 1, 3 do
			if a.pos[i] ~= b.pos[i] then return a.pos[i] < b.pos[i] end
		end
		return false
	end)

	-- The build also places the signs of the symmetry worlds; only those in these boxes belong to the museum.
	local function inside(p)
		for _, b in ipairs(boxes) do
			if p[1] >= b.min.x - 1 and p[1] <= b.max.x + 1 and p[3] >= b.min.z - 1 and p[3] <= b.max.z + 1 then return true end
		end
		return false
	end
	local kept_signs, kept_pictures = {}, {}
	for _, sgn in ipairs(signs) do if inside(sgn.pos) then kept_signs[#kept_signs + 1] = sgn end end
	for _, pic in ipairs(pictures) do if inside(pic.pos) then kept_pictures[#kept_pictures + 1] = pic end end
	signs, pictures = kept_signs, kept_pictures

	local defs = {}
	for _, name in ipairs(palette) do defs[name] = definition(name) end

	-- Rooms, between the inner walls of lobby.lua (L.WALLS): the south band (foyer, Workshop, Visitor information) up to the wall at z = -30, Gallery 1 up to z = -4, Galleries 2 and 3 up to z = 60 (split at x = -16), the Portal Hall beyond.
	local rooms = {
		{ id = "foyer", name = "Foyer", min = { -20, -49 }, max = { 20, -31 } },
		{ id = "workshop", name = "Workshop: the Try-it Pad", min = { L.X0 + 1, -49 }, max = { -22, -31 } },
		{ id = "information", name = "Visitor information", min = { 22, -49 }, max = { L.X1 - 1, -31 } },
		{ id = "gallery1", name = "Gallery 1: Four kinds of symmetry", min = { L.X0 + 1, -29 }, max = { L.X1 - 1, -5 } },
		{ id = "gallery2", name = "Gallery 2: A history of crystallography", min = { L.X0 + 1, -3 }, max = { -17, 59 } },
		{ id = "gallery3", name = "Gallery 3: Crystals at the atomic scale", min = { -15, -3 }, max = { L.X1 - 1, 59 } },
		{ id = "portal_hall", name = "Portal Hall", min = { L.X0 + 1, 61 }, max = { L.X1 - 1, L.Z1 - 1 } },
	}

	local npcs = {}
	for i, p in ipairs(cm.npc_places or {}) do
		local kind = i == 1 and "crystalminer:guide_npc" or "crystalminer:museum_visitor"
		local e = core.registered_entities[kind]
		local props = e and e.initial_properties or {}
		npcs[#npcs + 1] = { kind = i == 1 and "desk" or "visitor", pos = { p.x, p.y, p.z }, message = p.message,
			textures = props.textures, visual_size = props.visual_size }
	end

	local levers = {}
	for i, l in ipairs(cm.LEVERS or {}) do levers[i] = { letter = l.letter, x = l.x, z = cm.LEVER_Z, op = l.op, text = l.text, does = l.does, w = l.w } end

	local B = cm.BILLBOARD
	local d = SG.DIR[B.AT.dir]
	local out = {
		generated_by = "tools/export_museum.sh (tools/cmdump)", world_version = cm.WORLD_VERSION,
		boxes = boxes, palette = palette, nodes = nodes, meta = meta, defs = defs,
		signs = signs, pictures = pictures, rooms = rooms,
		spawn = { pos = { cm.content.lobby.spawn.x, cm.content.lobby.spawn.y, cm.content.lobby.spawn.z }, facing = "n" },
		-- lobby.lua's on_teleport puts a player arriving in the Portal Hall here, facing north.
		portal_hall = { pos = { 0, 1, 70 }, facing = "n" },
		pad = { build = cm.PAD_BUILD, result = cm.PAD_RESULT, levers = levers },
		billboard = { pos = { B.AT.wall.x + d.x * 0.52, B.AT.wall.y + (B.AT.dy or 0), B.AT.wall.z + d.z * 0.52 }, facing = B.AT.dir, size = B.SIZE },
		exhibit_rooms = cm.exhibit_rooms, npcs = npcs,
		checks = { missing = missing, emerge_late = cm.emerge_stats and cm.emerge_stats.late or 0, emerge_gave_up = cm.emerge_stats and cm.emerge_stats.gave_up or 0 },
	}
	local f = assert(io.open(core.get_worldpath() .. "/museum.json", "wb"))
	f:write(core.write_json(out))
	f:close()
	-- Every texture file the museum draws (block tiles, possibly with modifiers, pictures, NPCs), one per line, for the export script to copy. The sign glyphs are copied as a whole set.
	local seen, list = {}, {}
	local function take(s)
		for name in tostring(s or ""):gmatch("[%w_%-]+%.png") do
			if not seen[name] then seen[name] = true; list[#list + 1] = name end
		end
	end
	for _, def in pairs(defs) do for _, t in ipairs(def.tiles or {}) do take(t) end end
	for _, p in ipairs(pictures) do take(p.texture) end
	for _, n in ipairs(npcs) do for _, t in ipairs(n.textures or {}) do take(t) end end
	take("crystalminer_sign_back.png")
	table.sort(list)
	local t = assert(io.open(core.get_worldpath() .. "/museum_textures.txt", "wb"))
	t:write(table.concat(list, "\n") .. "\n")
	t:close()
	core.log("action", string.format("[cmdump] %d kinds of block, %d blocks, %d with metadata, %d signs, %d pictures, %d unread",
		#palette, #nodes / 5, #meta, #signs, #pictures, missing))
	core.request_shutdown()
end

-- cm.when_ready runs right after the build (after every on_build). The exhibit rooms of an existing world come later (cm.when_exhibits_ready); in the fresh world used here they are built with everything else.
cm.when_ready(function() core.after(1, dump) end)
