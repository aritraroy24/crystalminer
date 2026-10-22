-- Gallery 2 holograms for the current records in the six exhibit rooms.

local cm = crystalminer
local modpath = core.get_modpath("crystalminer")
local layout = dofile(modpath .. "/gallery2_layout.lua")
local logic = loadfile(modpath .. "/hologram_logic.lua")(cm.exhibit_elements or dofile(modpath .. "/exhibit_elements.lua"), layout)
local E = cm.E
local rooms = cm.exhibit_rooms
local records = cm.exhibit_dynamic_records
cm.hologram_logic = logic
cm.hologram_generations = {}

-- A plaque carries the generation it was made in; one from an older generation removes itself when
-- it wakes up (signs.lua). The generations are kept in mod storage across restarts.
local function save_generations()
	cm.storage:set_string("hologram_generations", core.serialize(cm.hologram_generations))
end
do
	local ok, saved = pcall(core.deserialize, cm.storage:get_string("hologram_generations"))
	for n = 1, 6 do cm.hologram_generations[n] = ok and type(saved) == "table" and tonumber(saved[n]) or 1 end
end

local CENTRES = layout.pedestals.centres
local OLD_CENTRES = {
	{ x = -45, z = 28 }, { x = -31, z = 28 },
	{ x = -45, z = 40 }, { x = -31, z = 40 },
	{ x = -45, z = 52 }, { x = -31, z = 52 },
}
cm.hologram_centres = CENTRES
cm.gallery2_layout = layout

local function plaque_text(n, record)
	if not record then return "# Exhibit " .. n .. "\nNo structure yet. Visit exhibit room " .. n .. "." end
	local l = record.lattice
	return string.format("# Exhibit %d: %s\ncell %.2f / %.2f / %.2f A\n%d atoms\nMaterials Project record %s\nScale 1:%.1f",
		n, record.name or record.formula or "Crystal structure", l.a, l.b, l.c, record.sites or #record.atoms, record.id:sub(1, 8),
		1 / logic.scale(record))
end

local function clear_plaque(n)
	local c = CENTRES[n]
	for _, object in ipairs(core.get_objects_inside_radius({ x = c.x, y = 2, z = c.z - 2 }, 4)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "crystalminer:sign" and entity.data and entity.data.opts
			and entity.data.opts.holo_pedestal == n then object:remove() end
	end
end

local function refresh_plaque(n, record)
	local c = CENTRES[n]
	clear_plaque(n)
	core.set_node({ x = c.x, y = 2, z = c.z - 2 }, { name = "crystalminer:stone_brick" })
	cm.SG.on_wall({ x = c.x, y = 2, z = c.z - 2 }, "s", "plaque", plaque_text(n, record), nil,
		{ holo_pedestal = n, holo_gen = cm.hologram_generations[n] })
end

local function build_pedestal(n)
	local c = CENTRES[n]
	local box = { min = { c.x - 2, 0, c.z - 3 }, size = { 5, 4, 5 } }
	cm.load_region(box)
	for x = c.x - 2, c.x + 2 do for z = c.z - 2, c.z + 2 do
		for y = 1, 2 do core.set_node({ x = x, y = y, z = z }, { name = "crystalminer:stone_brick" }) end
	end end
	core.set_node({ x = c.x, y = 2, z = c.z }, { name = "crystalminer:lamp" })
	-- Remove the old manual controls from worlds built by hologram migration v1.
	core.set_node({ x = c.x - 1, y = 1, z = c.z - 3 }, { name = "air" })
	core.set_node({ x = c.x + 1, y = 1, z = c.z - 3 }, { name = "air" })
end

local function build_all()
	for n = 1, 6 do
		cm.hologram_generations[n] = cm.hologram_generations[n] or 1
		build_pedestal(n)
		refresh_plaque(n, records[n] and records[n].record)
	end
	save_generations()
end

local function clear_old_pedestals()
	for n, c in ipairs(OLD_CENTRES) do
		for x = c.x - 2, c.x + 2 do for z = c.z - 3, c.z + 2 do
			for y = 1, 3 do core.set_node({ x = x, y = y, z = z }, { name = "air" }) end
		end end
		for _, object in ipairs(core.get_objects_inside_radius({ x = c.x, y = 2, z = c.z - 2 }, 5)) do
			local entity, pos = object:get_luaentity(), object:get_pos()
			if entity and entity.name == "crystalminer:sign" and pos
				and pos.x >= c.x - 3 and pos.x <= c.x + 3 and pos.z >= c.z - 4 and pos.z <= c.z + 1 then object:remove() end
		end
	end
end

local function bump_generations()
	for n = 1, 6 do cm.hologram_generations[n] = (cm.hologram_generations[n] or 1) + 1 end
	save_generations()
end

local function emerge_gallery(done)
	local minp, maxp = { x = -49, y = 0, z = 25 }, { x = -27, y = 4, z = 54 }
	if not core.emerge_area then done(true); return end
	core.emerge_area(minp, maxp, function(_, action)
		done(action ~= core.EMERGE_CANCELLED and action ~= core.EMERGE_ERRORED)
	end)
end

-- Remove any obsolete rotor entities left by the earlier hologram implementation.
core.register_entity("crystalminer:holo_rotor", {
	on_activate = function(self) self.object:remove() end,
})
core.register_alias("crystalminer:holo_left", "air")
core.register_alias("crystalminer:holo_right", "air")

local function changed(n, record)
	cm.hologram_generations[n] = (cm.hologram_generations[n] or 0) + 1
	save_generations()
	refresh_plaque(n, record)
end
cm.exhibit_changed = cm.exhibit_changed or {}
cm.exhibit_changed[#cm.exhibit_changed + 1] = changed

local function marker_def(point, name)
	local spread = point.spread or 0
	local minpos = { x = point.pos.x - spread, y = point.pos.y - spread, z = point.pos.z - spread }
	local maxpos = { x = point.pos.x + spread, y = point.pos.y + spread, z = point.pos.z + spread }
	local velocity = { x = 0, y = point.kind == "atoms" and -logic.ATOM_FALL_SPEED or 0, z = 0 }
	return {
		amount = point.amount, time = 0, minpos = minpos, maxpos = maxpos, minvel = velocity, maxvel = velocity,
		minacc = { x = 0, y = 0, z = 0 }, maxacc = { x = 0, y = 0, z = 0 },
		minexptime = point.exptime, maxexptime = point.exptime,
		minsize = point.size, maxsize = point.size,
		texture = "crystalminer_dot.png^[colorize:" .. point.colour .. ":255", glow = 14, playername = name,
	}
end

local function scanner_def(point, name)
	return marker_def({ pos = point, colour = "#FFFFFF", kind = "atoms", spread = 0, size = 3.2,
		amount = logic.ATOM_AMOUNT, exptime = logic.ATOM_EXPTIME }, name)
end

local viewers = {}
local function delete_state(state, name)
	for _, id in ipairs(state.ids or {}) do cm.marker_api.delete(id, name) end
	if state.scanner then cm.marker_api.delete(state.scanner, name) end
end

local function add_point(point, name)
	local id = cm.marker_api.add(marker_def(point, name))
	return E.spawner_ok(id) and id or nil
end

local function add_all(state, name)
	for _, point in ipairs(state.points) do
		local id = add_point(point, name)
		if id then state.ids[#state.ids + 1] = id end
	end
end

local function start_scan(viewer, n, points, tier)
	viewer[n] = { points = points, index = 0, ids = {}, mode = "scan", tier = tier,
		generation = cm.hologram_generations[n] }
end

local function step_player(player)
	local name = player:get_player_name()
	local states = viewers[name] or {}; viewers[name] = states
	local additions, resends = 0, 0
	local order = {}
	local player_pos = player:get_pos()
	for n, c in ipairs(CENTRES) do
		local dx, dz = player_pos.x - c.x, player_pos.z - c.z
		order[#order + 1] = { n = n, distance = math.sqrt(dx * dx + dz * dz) }
	end
	table.sort(order, function(a, b) return a.distance < b.distance end)
	for _, item in ipairs(order) do
		local n, distance = item.n, item.distance
		local entry, c = records[n], CENTRES[n]
		local record, state = entry and entry.record, states[n]
		local visible = record and logic.visible(player_pos, state ~= nil)
		if not visible then
			if state then delete_state(state, name); states[n] = nil end
		else
			local centre = { x = c.x, y = logic.HOVER_BASE, z = c.z }
			local tier = logic.lod(distance, state and state.tier)
			if not state then
				start_scan(states, n, logic.points(record, centre, tier), tier)
			elseif state.tier ~= tier then
				if resends < 2 then
					delete_state(state, name)
					states[n] = { points = logic.points(record, centre, tier), index = 0, ids = {}, mode = "full",
						tier = tier, generation = cm.hologram_generations[n] }
					add_all(states[n], name); resends = resends + 1
				end
			elseif state.generation ~= cm.hologram_generations[n] then
				if resends < 2 then
					delete_state(state, name); states[n] = nil
					start_scan(states, n, logic.points(record, centre, tier), tier); resends = resends + 1
				end
			elseif state.mode == "scan" and additions < 60 then
				local count = logic.reveal_count(#state.points, state.index, 60 - additions)
				for _ = 1, count do
					state.index = state.index + 1
					local id = add_point(state.points[state.index], name)
					if id then state.ids[#state.ids + 1] = id end
				end
				additions = additions + count
				if state.index > 0 then
					if state.scanner then cm.marker_api.delete(state.scanner, name) end
					if state.index < #state.points then
						state.scanner = cm.marker_api.add(scanner_def(state.points[state.index].pos, name))
					end
				end
				if state.index >= #state.points then
					if state.scanner then cm.marker_api.delete(state.scanner, name); state.scanner = nil end
					state.mode = "full"
				end
			end
		end
	end
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.2 then return end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do step_player(player) end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	for _, state in pairs(viewers[name] or {}) do delete_state(state, name) end
	viewers[name] = nil
end)

cm.hologram_viewers = viewers
cm.hologram_step_player = step_player

table.insert(cm.on_build, function()
	build_all()
	cm.storage:set_string("hologram_version", "3")
end)
cm.when_ready(function()
	local stamp = cm.storage:get_string("hologram_version")
	if stamp == "3" then
		for n = 1, 6 do changed(n, records[n] and records[n].record) end
		return
	end
	-- Versions 1 and 2 used the old centres (and version 1 also had manual buttons). Clear only
	-- those footprints, bump plaque generations so sleeping signs reject themselves, then build the
	-- new layout.
	emerge_gallery(function(ok)
		if ok then clear_old_pedestals(); bump_generations(); build_all(); cm.storage:set_string("hologram_version", "3") end
	end)
end)
