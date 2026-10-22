-- Where to draw a region's symmetry elements: points along rotation axes, the outline of each
-- mirror plane, the inversion centre, and unit-cell edges for lattices. Pure Lua.
--
-- Luanti nodes are centred on integer positions, so a node at x spans [x - 0.5, x + 0.5] and
-- a doubled coordinate d is at world position d / 2 - 0.5.

-- Loaded with loadfile(...)(symmetry), since mod security does not allow require.
local S = ...

local E = {}

E.COLOURS = {
	axis2 = "#FFD700", axis3 = "#32CD32", axis4 = "#FF3030",
	rotoinversion = "#B040FF", mirror = "#40C0FF", inversion = "#FFFFFF", lattice = "#FF8C00",
}

--- A small integer direction v with W v = sign v, or nil.
local function fixed_direction(o, sign)
	for a = -1, 1 do
		for b = -1, 1 do
			for c = -1, 1 do
				if a ~= 0 or b ~= 0 or c ~= 0 then
					local w = S.apply_linear(o, { a, b, c })
					if w[1] == sign * a and w[2] == sign * b and w[3] == sign * c then return { a, b, c } end
				end
			end
		end
	end
	return nil
end

--- Treats v and -v as the same line.
local function dir_key(v)
	local s = 1
	for _, x in ipairs(v) do
		if x ~= 0 then
			s = x > 0 and 1 or -1
			break
		end
	end
	return (s * v[1]) .. "," .. (s * v[2]) .. "," .. (s * v[3]), { s * v[1], s * v[2], s * v[3] }
end

local function inside(p, lo, hi)
	return p[1] >= lo[1] and p[1] <= hi[1] and p[2] >= lo[2] and p[2] <= hi[2] and p[3] >= lo[3] and p[3] <= hi[3]
end

-- Kinds, for the per-player filter: "axes", "mirrors", "centres", "cells".
-- size is the particle size; the inversion centre is drawn larger with its own texture.
local function add(dots, x, y, z, colour, kind, size)
	dots[#dots + 1] = { pos = { x = x - 0.5, y = y - 0.5, z = z - 0.5 }, colour = colour, kind = kind, size = size or 1.5 }
end

-- symbol: "2", "3", "4", "-3", "-4", drawn with the International Tables shape for that axis.
local function line(dots, o, v, lo, hi, colour, symbol)
	local len = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
	for t = -30, 30, 0.75 do
		local p = { o[1] + t * v[1] / len, o[2] + t * v[2] / len, o[3] + t * v[3] / len }
		if inside(p, lo, hi) then
			add(dots, p[1], p[2], p[3], colour, "axes", 2.2)
			dots[#dots].symbol = symbol
		end
	end
end

--- Where the plane cuts the faces of the box (its outline), plus a sparse grid of smaller dots
-- across the plane every `spacing` nodes, so it reads as a sheet rather than a line.
local function plane_outline(dots, o, n, lo, hi, spacing)
	for x = lo[1], hi[1], 0.5 do
		for y = lo[2], hi[2], 0.5 do
			for z = lo[3], hi[3], 0.5 do
				if n[1] * (x - o[1]) + n[2] * (y - o[2]) + n[3] * (z - o[3]) == 0 then
					local on_face = x == lo[1] or x == hi[1] or y == lo[2] or y == hi[2] or z == lo[3] or z == hi[3]
					local whole = (2 * (x + y + z)) % 2 == 0 -- every other point along the outline
					if on_face and (spacing <= 2 or whole) then
						add(dots, x, y, z, E.COLOURS.mirror, "mirrors")
					elseif not on_face and (x - o[1]) % spacing == 0 and (y - o[2]) % spacing == 0 and (z - o[3]) % spacing == 0 then
						add(dots, x, y, z, E.COLOURS.mirror, "mirrors", 0.8)
					end
				end
			end
		end
	end
end

local function lattice(r)
	local dots = {}
	for axis = 1, 3 do
		local a1, a2 = axis % 3 + 1, (axis + 1) % 3 + 1
		for i = 0, r.size[a1], r.cell[a1] do
			for j = 0, r.size[a2], r.cell[a2] do
				for t = 0, r.size[axis] do
					local p = {}
					p[axis], p[a1], p[a2] = r.min[axis] + t, r.min[a1] + i, r.min[a2] + j
					add(dots, p[1], p[2], p[3], E.COLOURS.lattice, "cells")
				end
			end
		end
	end
	return dots
end

--- Dots for a region from symmetry.region(). Coordinates are world positions.
-- Each dot: pos, colour, kind ("axes", "mirrors", "centres", "cells") and particle size.
function E.dots(r)
	if r.cell then return lattice(r) end
	local lo = { r.min[1], r.min[2], r.min[3] }
	local hi = { lo[1] + r.size[1], lo[2] + r.size[2], lo[3] + r.size[3] }
	local o = { r.origin[1] / 2, r.origin[2] / 2, r.origin[3] / 2 }

	local proper, proper_dir, roto, roto_dir, mirrors, inversion = {}, {}, {}, {}, {}, false
	for _, op in ipairs(r.group.ops) do
		local k = S.kind(op)
		if k == "2" or k == "3" or k == "4" or k == "6" then
			local v = fixed_direction(op, 1)
			if v then
				local key, dir = dir_key(v)
				proper[key] = math.max(proper[key] or 0, tonumber(k))
				proper_dir[key] = dir
			end
		elseif k == "-3" or k == "-4" or k == "-6" then
			local v = fixed_direction(op, -1)
			if v then
				local key, dir = dir_key(v)
				roto[key], roto_dir[key] = k, dir
			end
		elseif k == "m" then
			local v = fixed_direction(op, -1)
			if v then
				local key, dir = dir_key(v)
				mirrors[key] = dir
			end
		elseif k == "-1" then
			inversion = true
		end
	end

	local dots = {}
	for key, fold in pairs(proper) do
		local colour = fold == 4 and E.COLOURS.axis4 or fold == 3 and E.COLOURS.axis3 or E.COLOURS.axis2
		-- A 3-fold axis that is also a -3 axis is drawn with the -3 symbol (International Tables),
		-- keeping the 3-fold colour.
		local symbol = (fold == 3 and roto[key] == "-3") and "-3" or tostring(fold)
		line(dots, o, proper_dir[key], lo, hi, colour, symbol)
	end
	for key, k in pairs(roto) do
		if not proper[key] or proper[key] == 2 then line(dots, o, roto_dir[key], lo, hi, E.COLOURS.rotoinversion, k) end
	end
	local n_mirrors = 0
	for _ in pairs(mirrors) do n_mirrors = n_mirrors + 1 end
	-- Fill planes densely when there are few, sparsely when there are many (the Kaleidoscope has 9).
	local spacing = n_mirrors <= 2 and 2 or 4
	for _, n in pairs(mirrors) do plane_outline(dots, o, n, lo, hi, spacing) end
	if inversion then add(dots, o[1], o[2], o[3], E.COLOURS.inversion, "centres", 4) end
	return dots
end

---------------------------------------------------------------------------- markers on screen

-- Each dot is shown to a player by its own particle spawner that never ends (time = 0), placed
-- at the dot's exact position (minpos = maxpos), and deleted when the player should no longer
-- see it. The server sends one packet when a spawner is added and one when it is deleted, and
-- none while it runs: the client spawns the particles itself.
--
-- A spawner cannot be told to keep one particle alive: in Luanti (5.4.1 to 5.17.0,
-- src/client/particles.cpp, ParticleSpawner::step) an endless spawner makes amount + 1 tries per
-- client frame, each succeeding with probability dtime, so particles start at random times at
-- a mean rate of amount + 1 per second. A dot is blank only if no particle started within the
-- last MARKER_EXPTIME seconds, a fraction exp(-(amount + 1) * MARKER_EXPTIME) of the time:
-- exp(-6), about 0.25 %, with the values below. The overlapping copies are invisible because
-- they are identical and the textures' alpha is 0 or 255. Deleting a spawner does not remove
-- particles it already made, so a hidden dot disappears within MARKER_EXPTIME seconds.
E.MARKER_AMOUNT, E.MARKER_EXPTIME = 1, 3

function E.marker_texture(d)
	if d.kind == "centres" then return "crystalminer_centre.png" end
	return "crystalminer_" .. (d.symbol and ("sym_" .. d.symbol) or "dot") .. ".png^[colorize:" .. d.colour .. ":255"
end

--- The add_particlespawner definition for dot d, seen only by player name. Legacy fields only
-- (minpos, minexptime, ...), which every version from 5.4 on understands.
function E.marker_def(d, name)
	local still = { x = 0, y = 0, z = 0 }
	return {
		amount = E.MARKER_AMOUNT, time = 0,
		minpos = d.pos, maxpos = d.pos, minvel = still, maxvel = still, minacc = still, maxacc = still,
		minexptime = E.MARKER_EXPTIME, maxexptime = E.MARKER_EXPTIME, minsize = d.size, maxsize = d.size,
		texture = E.marker_texture(d), glow = 14, playername = name,
	}
end

--- Whether add_particlespawner succeeded. The docs say it returns -1 on failure, but the engine
-- (5.4.1 and 5.17.0, l_add_particlespawner) pushes that as a u32, so Lua sees 4294967295;
-- 5.17 also returns 0 when it has run out of ids. Real ids start at 1. Note that 5.17 no longer fails for a player who is not connected: it returns an id and sends nothing.
function E.spawner_ok(id)
	return type(id) == "number" and id >= 1 and id < 4294967295
end

--- Brings one player's markers up to date and returns the new state (or nil when none show).
-- m: the state from the last call, { dots = <dots table>, filter = <string>, ids = { [i] = id } }.
-- dots: the dots the player should see (nil for none); filter: nil for all, else a kind.
-- add(d) returns a spawner id (see E.spawner_ok); delete(id) removes one. Only the
-- differences are sent: nothing at all when nothing changed.
function E.sync_markers(m, dots, filter, add, delete)
	if dots and #dots == 0 then dots = nil end
	local key = filter or "all"
	if m and m.dots == dots and m.filter == key then return m end
	if m and m.dots ~= dots then
		for _, id in pairs(m.ids) do delete(id) end
		m = nil
	end
	if not dots then return nil end
	m = m or { dots = dots, ids = {} }
	m.filter = key
	for i, d in ipairs(dots) do
		local want = filter == nil or filter == d.kind
		local id = m.ids[i]
		if want and not id then
			id = add(d)
			if E.spawner_ok(id) then m.ids[i] = id end
		elseif id and not want then
			delete(id)
			m.ids[i] = nil
		end
	end
	return m
end

return E
