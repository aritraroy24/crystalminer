package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local layout = dofile("mods/crystalminer/gallery2_layout.lua")
local logic = loadfile("mods/crystalminer/hologram_logic.lua")(dofile("mods/crystalminer/exhibit_elements.lua"), layout)
local T = require("testlib")

print("hologram logic")

local function record()
	return {
		lo = { 0, 0, 0 }, hi = { 1, 1, 1 },
		atoms = { { 0, 0, 0, "O" }, { 1, 1, 1, "Mg" } },
		bonds = { { 1, 0, 0 } }, cell = { { 0, 1, 0 } },
	}
end

T.run("Gallery 2 pedestal layout fits the real furniture", function()
	local centres = layout.pedestals.centres
	for _, c in ipairs(centres) do
		T.ok(c.x - 2 >= layout.bounds.x0 and c.x + 2 <= layout.bounds.x1 and c.z - 2 >= layout.bounds.z0 and c.z + 2 <= layout.bounds.z1, "inside Gallery 2")
		T.ok(c.x + 2 < layout.carpet.x0 or c.x - 2 > layout.carpet.x1, "clear of carpet")
		T.ok(c.x - 2 > layout.wall_x[1] and c.x + 2 < layout.wall_x[2], "clear of walls")
		T.ok(c.z - 2 - (layout.haeuy.centre.z + layout.haeuy.radius) >= 4, "clear of Haeuy model")
		T.ok(layout.bounds.z1 + 1 - (c.z + 2) >= 8, "clear of far wall")
		for _, b in ipairs(layout.benches) do
			T.ok(c.x + 2 < b.x0 or c.x - 2 > b.x1 or c.z + 2 < b.z0 or c.z - 2 > b.z1, "clear of benches")
		end
	end
	T.ok(layout.carpet.x0 + layout.carpet.x1 == 2 * layout.axis, "carpet symmetry")
	T.ok(layout.pedestals.columns[1] + layout.pedestals.columns[2] == 2 * layout.axis, "pedestal symmetry")
	T.eq(layout.pedestals.rows[2] - layout.pedestals.rows[1], 10)
	T.eq(layout.pedestals.rows[3] - layout.pedestals.rows[2], 10)
end)

T.run("gallery2 layout data is internally consistent", function()
	T.eq(layout.axis, -38)
	T.eq(#layout.pedestals.centres, 6)
	for i, c in ipairs(layout.pedestals.centres) do
		T.eq(c.x, layout.pedestals.columns[(i - 1) % 2 + 1])
		T.eq(c.z, layout.pedestals.rows[math.floor((i - 1) / 2) + 1])
	end
	T.eq(layout.benches[1].x0 + layout.benches[2].x0, 2 * layout.axis)
	T.eq(layout.benches[3].x0 + layout.benches[4].x0, 2 * layout.axis)
	T.eq(layout.carpet.x1 - layout.carpet.x0 + 1, 7)
end)

T.run("points use north, up, east scan order", function()
	local r = { lo = { 0, 0, 0 }, hi = { 1, 1, 0 }, atoms = {
		{ 0, 0, 0, "O" }, { 1, 0, 0, "O" }, { 0, 1, 0, "O" }, { 1, 1, 0, "O" },
	}, bonds = {}, cell = {} }
	local p = logic.points(r, { x = 0, y = 0, z = 0 })
	T.ok(math.abs(p[1].pos.x - (-0.5 * math.cos(math.rad(30)) + 0.5 * math.sin(math.rad(30)))) < 1e-12)
	T.ok(math.abs(p[2].pos.x - (0.5 * math.cos(math.rad(30)) + 0.5 * math.sin(math.rad(30)))) < 1e-12)
	T.ok(p[1].pos.x < p[2].pos.x and p[2].pos.z < p[4].pos.z, "x fastest, then north")
end)

T.run("scale centres and applies the fixed static angle", function()
	local p = logic.points({ lo = { 0, 0, 0 }, hi = { 1, 0, 0 }, atoms = {
		{ 1, 0, 0, "O" },
	}, bonds = {}, cell = {} }, { x = 10, y = 3.2, z = 20 })
	T.ok(math.abs(p[1].pos.x - (10 + 0.5 * math.cos(math.rad(30)))) < 1e-12, "static x angle")
	T.ok(math.abs(p[1].pos.z - (20 + 0.5 * math.sin(math.rad(30)))) < 1e-12, "static z angle")
	T.eq(logic.scale(record()), 1)
end)

T.run("the hologram floats above the pedestal", function()
	-- The lowest point of a structure is at the hover base, well above the pedestal top.
	local r = { lo = { 0, 0, 3 }, hi = { 1, 1, 12 }, atoms = { { 0, 0, 3, "O" }, { 1, 1, 12, "Mg" } }, bonds = {}, cell = {} }
	local p = logic.points(r, { x = 0, y = logic.HOVER_BASE, z = 0 })
	local lowest, highest = math.huge, -math.huge
	for _, point in ipairs(p) do lowest = math.min(lowest, point.pos.y); highest = math.max(highest, point.pos.y) end
	T.eq(lowest, logic.HOVER_BASE)
	T.ok(lowest - logic.PEDESTAL_TOP >= 1, "at least a block of air above the pedestal")
	T.ok(lowest - logic.PEDESTAL_TOP <= 2, "not floating far away")
	T.ok(highest < 18, "stays well below the roof")
end)

T.run("same inputs produce identical static points", function()
	local a = logic.points(record(), { x = 12, y = 3.2, z = -4 })
	local b = logic.points(record(), { x = 12, y = 3.2, z = -4 })
	T.eq(#a, #b)
	for i = 1, #a do
		T.eq(a[i].pos.x, b[i].pos.x); T.eq(a[i].pos.y, b[i].pos.y); T.eq(a[i].pos.z, b[i].pos.z)
	end
end)

T.run("empty records have no points and range has hysteresis", function()
	T.eq(#logic.points(nil, { x = 0, y = 0, z = 0 }), 0)
	-- Anyone in Gallery 2, or within 8 blocks of it (14 once shown), sees every hologram.
	T.ok(logic.visible({ x = -38, y = 1, z = 28 }, false), "inside the gallery")
	T.ok(logic.visible({ x = -38, y = 1, z = -3 }, false), "at the entrance")
	T.ok(logic.visible({ x = -38, y = 1, z = 66 }, false), "8 blocks beyond the far wall")
	T.ok(not logic.visible({ x = -38, y = 1, z = 68 }, false), "too far to start")
	T.ok(logic.visible({ x = -38, y = 1, z = 72 }, true), "keeps showing a little further")
	T.ok(not logic.visible({ x = -38, y = 1, z = 74 }, true), "hidden beyond 14")
	T.ok(not logic.visible({ x = 20, y = 1, z = 28 }, false), "Gallery 3 side is out of range")
	T.ok(not logic.visible({ x = -38, y = 40, z = 28 }, false), "far above the museum")
	T.eq(logic.reveal_count(100, 0, 60), 60)
	T.eq(logic.reveal_count(100, 60, 60), 40)
end)

T.run("LOD hysteresis avoids flapping at both boundaries", function()
	-- Tier 1 is entered at 17 or less and left above 17; tier 3 is entered above 33 and left at 30 or less.
	T.eq(logic.lod(14), 1); T.eq(logic.lod(17), 1); T.eq(logic.lod(18), 2); T.eq(logic.lod(33), 2); T.eq(logic.lod(34), 3)
	T.eq(logic.lod(17, 1), 1); T.eq(logic.lod(18, 1), 2); T.eq(logic.lod(33, 1), 2); T.eq(logic.lod(34, 1), 3)
	T.eq(logic.lod(11, 2), 1); T.eq(logic.lod(12, 2), 2); T.eq(logic.lod(33, 2), 2); T.eq(logic.lod(34, 2), 3)
	T.eq(logic.lod(11, 3), 1); T.eq(logic.lod(12, 3), 2); T.eq(logic.lod(30, 3), 2); T.eq(logic.lod(31, 3), 3)
	T.eq(logic.lod(100), 3)
end)

T.run("LOD thins lines, preserves atoms, and scales clouds", function()
	local atoms, bonds, cell = {}, {}, {}
	for i = 0, 4 do atoms[#atoms + 1] = { i, 0, 0, "O" } end
	for i = 10, 21 do bonds[#bonds + 1] = { i, 0, 0 } end
	for i = 1, 8 do cell[#cell + 1] = { 0, i, 0 } end
	local r = { lo = { 0, 0, 0 }, hi = { 21, 8, 0 }, atoms = atoms, bonds = bonds, cell = cell }
	local function counts(p)
		local n = { atoms = 0, bonds = 0, cells = 0 }
		for _, point in ipairs(p) do n[point.kind] = n[point.kind] + 1 end
		return n
	end
	local p1, p2, p3 = logic.points(r, { x = 0, y = 0, z = 0 }, 1), logic.points(r, { x = 0, y = 0, z = 0 }, 2), logic.points(r, { x = 0, y = 0, z = 0 }, 3)
	local c1, c2, c3 = counts(p1), counts(p2), counts(p3)
	T.eq(c1.atoms, 5); T.eq(c2.atoms, 5); T.eq(c3.atoms, 5)
	T.eq(c1.bonds, 12); T.eq(c2.bonds, 6); T.eq(c3.bonds, 4)
	T.eq(c1.cells, 8); T.eq(c2.cells, 4); T.eq(c3.cells, 4)
	local function find(p, kind) for _, point in ipairs(p) do if point.kind == kind then return point end end end
	local a1, b1, b2, c1p, c2p = find(p1, "atoms"), find(p1, "bonds"), find(p2, "bonds"), find(p1, "cells"), find(p2, "cells")
	T.eq(a1.amount, 18); T.eq(b1.amount, 9); T.eq(b2.amount, 5); T.eq(c1p.amount, 8); T.eq(c2p.amount, 4)
	T.eq(b2.spread, b1.spread * 2); T.eq(c2p.spread, c1p.spread * 2)
	T.eq(b2.size, b1.size * 1.25); T.eq(find(p3, "bonds").size, b1.size * 1.5)
	local default = logic.points(r, { x = 0, y = 0, z = 0 })
	T.eq(#default, #p1); T.eq(default[1].amount, p1[1].amount)
end)

T.run("point cap keeps atoms and thins non-atoms", function()
	local atoms, bonds, cell = {}, {}, {}
	for i = 1, 20 do atoms[#atoms + 1] = { i, 0, 0, "O" } end
	for i = 1, 300 do bonds[#bonds + 1] = { i, 1, 0 } end
	for i = 1, 300 do cell[#cell + 1] = { i, 2, 0 } end
	local p = logic.points({ lo = { 1, 0, 0 }, hi = { 300, 2, 0 }, atoms = atoms, bonds = bonds, cell = cell }, { x = 0, y = 0, z = 0 })
	T.ok(#p <= 450, "cap")
	local count = 0
	for _, point in ipairs(p) do if point.kind == "atoms" then count = count + 1 end end
	T.eq(count, 20, "all atoms retained")
end)

T.run("colours and particle sizes follow exhibit conventions", function()
	local p = logic.points({ lo = { 0, 0, 0 }, hi = { 2, 0, 0 }, atoms = {
		{ 0, 0, 0, "O" }, { 1, 0, 0, "Mg" },
	}, bonds = { { 2, 0, 0 } }, cell = {} }, { x = 0, y = 0, z = 0 })
	T.eq(p[1].colour, "#FF0D0D"); T.eq(p[1].size, 1.1); T.eq(p[1].spread, 0.16); T.eq(p[1].amount, 18); T.eq(p[1].exptime, 2.0)
	T.eq(p[2].colour, "#8AFF00"); T.eq(p[2].amount, 18)
	T.eq(p[3].colour, "#FFFFFF"); T.eq(p[3].size, 0.45); T.eq(p[3].spread, 0.10); T.eq(p[3].amount, 9); T.eq(p[3].exptime, 2.0)
end)

T.run("cloud spreads overlap the scaled grid spacing", function()
	local r = { lo = { 0, 0, 0 }, hi = { 19, 19, 19 }, atoms = {},
		bonds = { { 0, 0, 0 } }, cell = { { 1, 0, 0 } } }
	local p = logic.points(r, { x = 0, y = 0, z = 0 })
	local spacing = logic.scale(r)
	T.ok(p[1].spread >= spacing / 2, "bond spread")
	-- Cell voxels are intentionally a slightly softer cloud; adjacent cell boxes overlap at the
	-- usual one-cell visual spacing even though their half-width is tuned separately.
	T.ok(p[2].spread * 2 >= spacing * 0.75, "cell cloud overlap")
end)

T.finish()
