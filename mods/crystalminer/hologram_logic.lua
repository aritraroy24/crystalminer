-- Pure geometry and scheduling for Gallery 2 exhibit holograms.

local elements, layout = ...
local M = {}

M.MAX_POINTS = 450
M.MAX_SPAN = 3.6
-- Particle-cloud look: each retained point is a small overlapping cloud, rather than one sparse dot.
-- A hologram should look still. Each point is a cloud of particles that each live exptime seconds at a
-- random spot in a small box, so a long life means a slow, calm turnover and a steady shape (a short life
-- makes the dust shimmer). Alive particles per point = amount x exptime. A structure that changes keeps
-- the old particles for up to exptime seconds. ATOM_FALL_SPEED is 0: nothing drifts.
M.ATOM_SPREAD, M.ATOM_SIZE, M.ATOM_AMOUNT, M.ATOM_EXPTIME = 0.16, 1.1, 18, 2.0
M.BOND_SPREAD, M.BOND_SIZE, M.BOND_AMOUNT, M.BOND_EXPTIME = 0.10, 0.45, 9, 2.0
M.CELL_SPREAD, M.CELL_SIZE, M.CELL_AMOUNT, M.CELL_EXPTIME = 0.08, 0.40, 8, 2.0
M.ATOM_FALL_SPEED = 0
M.STATIC_ANGLE = 30
-- The hologram floats: its lowest point is HOVER_BASE blocks up, 1.5 above the top of the pedestal (whose
-- surface is at y 2.5), so there is a little clear air between the projector lamp and the structure.
M.PEDESTAL_TOP, M.HOVER_BASE = 2.5, 4.0

M.LOD = {
	[1] = { amount = 1.0, bond_step = 1, cell_step = 1, size = 1.0 },
	[2] = { amount = 0.5, bond_step = 2, cell_step = 2, size = 1.25 },
	[3] = { amount = 0.3, bond_step = 3, cell_step = 2, size = 1.5 },
}

local function key(x, y, z) return x .. ":" .. y .. ":" .. z end

function M.scale(record)
	local span = math.max(record.hi[1] - record.lo[1] + 1, record.hi[2] - record.lo[2] + 1, record.hi[3] - record.lo[3] + 1)
	return math.min(1, M.MAX_SPAN / span)
end

local function raw_points(record)
	local atoms, bonds, cells = {}, {}, {}
	local atom_by, bond_by, cell_by = {}, {}, {}
	for _, atom in ipairs(record.atoms or {}) do atom_by[key(atom[1], atom[2], atom[3])] = atom end
	for _, voxel in ipairs(record.bonds or {}) do bond_by[key(voxel[1], voxel[2], voxel[3])] = voxel end
	for _, voxel in ipairs(record.cell or {}) do cell_by[key(voxel[1], voxel[2], voxel[3])] = voxel end
	local out = {}
	for y = record.lo[2], record.hi[2] do
		for z = record.lo[3], record.hi[3] do
			for x = record.lo[1], record.hi[1] do
				local k = key(x, y, z)
				if atom_by[k] then out[#out + 1] = { x = x, y = y, z = z, kind = "atoms", element = atom_by[k][4] }
				elseif bond_by[k] then out[#out + 1] = { x = x, y = y, z = z, kind = "bonds" }
				elseif cell_by[k] then out[#out + 1] = { x = x, y = y, z = z, kind = "cells" } end
			end
		end
	end
	return out
end

local function kept(points, cell_step, bond_step)
	local cell_i, bond_i, out = 0, 0, {}
	for _, point in ipairs(points) do
		local keep = true
		if point.kind == "cells" then cell_i = cell_i + 1; keep = (cell_i - 1) % cell_step == 0
		elseif point.kind == "bonds" then bond_i = bond_i + 1; keep = (bond_i - 1) % bond_step == 0 end
		if keep then out[#out + 1] = point end
	end
	return out
end

function M.thin(points, cap)
	cap = cap or M.MAX_POINTS
	if #points <= cap then return points end
	local cell_step, bond_step = 1, 1
	local out = points
	while #out > cap and cell_step <= #points + 1 do
		cell_step = cell_step + 1
		out = kept(points, cell_step, bond_step)
	end
	while #out > cap do
		bond_step = bond_step + 1
		out = kept(points, cell_step, bond_step)
	end
	return out
end

local function colour(point)
	if point.kind == "bonds" then return "#FFFFFF" end
	if point.kind == "cells" then return "#FF8C00" end
	return elements[point.element] and elements[point.element].hex or "#FFFFFF"
end

local function look(kind)
	if kind == "atoms" then return M.ATOM_SPREAD, M.ATOM_SIZE, M.ATOM_AMOUNT, M.ATOM_EXPTIME end
	if kind == "bonds" then return M.BOND_SPREAD, M.BOND_SIZE, M.BOND_AMOUNT, M.BOND_EXPTIME end
	return M.CELL_SPREAD, M.CELL_SIZE, M.CELL_AMOUNT, M.CELL_EXPTIME
end

local function round_amount(amount)
	return math.max(2, math.floor(amount + 0.5))
end

local function minimum_amount(exptime)
	return math.max(2, math.ceil(-math.log(0.03) / exptime - 1))
end

-- Level of detail by horizontal distance to a pedestal. The ranges where a tier is entered and left
-- differ, so a player standing on a boundary does not cause re-sends.
function M.lod(distance, tier)
	if not tier then return distance > 33 and 3 or (distance > 17 and 2 or 1) end
	if tier == 1 then return distance > 33 and 3 or (distance > 17 and 2 or 1) end
	if tier == 2 then return distance <= 11 and 1 or (distance > 33 and 3 or 2) end
	return distance <= 11 and 1 or (distance <= 30 and 2 or 3)
end

function M.points(record, centre, tier)
	if not record or not record.lo or not record.hi then return {} end
	local raw = M.thin(raw_points(record))
	tier = tier or 1
	local settings = M.LOD[tier] or M.LOD[1]
	raw = kept(raw, settings.cell_step, settings.bond_step)
	local scale = M.scale(record)
	local radians = math.rad(M.STATIC_ANGLE)
	local c, s = math.cos(radians), math.sin(radians)
	local middle = { (record.lo[1] + record.hi[1]) / 2, (record.lo[2] + record.hi[2]) / 2, (record.lo[3] + record.hi[3]) / 2 }
	local out = {}
	for _, point in ipairs(raw) do
		local east = (point.x - middle[1]) * scale
		local north = (point.y - middle[2]) * scale
		local up = (point.z - record.lo[3]) * scale -- from the bottom of the hologram, which hovers at centre.y
		local spread, size, amount, exptime = look(point.kind)
		local step = point.kind == "atoms" and 1 or (point.kind == "bonds" and settings.bond_step or settings.cell_step)
		amount = math.max(minimum_amount(exptime), round_amount(amount * settings.amount))
		out[#out + 1] = {
			pos = { x = centre.x + east * c - north * s, y = centre.y + up, z = centre.z + east * s + north * c },
			colour = colour(point), kind = point.kind,
			size = size * settings.size, spread = spread * step, amount = amount, exptime = exptime,
		}
	end
	return out
end

-- Gallery 2 (interior), from lobby.lua. All six holograms are shown to anyone in the gallery or
-- within a margin of it (the doorways), so a visitor sees them without walking up to a pedestal.
M.GALLERY = layout and layout.bounds or { x0 = -59, x1 = -17, z0 = -3, z1 = 59 }
M.SHOW_MARGIN, M.HIDE_MARGIN = 8, 14

--- Whether a player at pos should see the holograms; showing: they are already shown (hysteresis).
function M.visible(pos, showing)
	local g, m = M.GALLERY, showing and M.HIDE_MARGIN or M.SHOW_MARGIN
	return pos.x >= g.x0 - m and pos.x <= g.x1 + m and pos.z >= g.z0 - m and pos.z <= g.z1 + m and pos.y >= -2 and pos.y <= 22
end

function M.reveal_count(total, revealed, per_step)
	return math.min(total, revealed + (per_step or 60)) - revealed
end

return M
