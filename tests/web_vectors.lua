-- Reference results from the Lua engine for tests/test_web.mjs, which checks web/js/symmetry.js against them: the images of sample blocks in every world (in each world's own coordinates, as tools/export_web.lua writes them) and the detected symmetry of sample builds. Run from the repository root; prints JSON.
package.path = "mods/crystalminer/?.lua;" .. package.path
local S = require("symmetry")
local L = require("lessons")
local content = require("content")

local out = { images = {}, detect = {} }
for _, a in ipairs(content.regions) do
	local r = S.region(L.region_spec(a, a.generators))
	-- A few blocks spread through the build space, including its edges and centre.
	local picks = {}
	for _, f in ipairs({ { 0, 0, 0 }, { 0.5, 0.5, 0.5 }, { 0.2, 0.7, 0.4 }, { 0.9, 0.1, 0.6 }, { 0.33, 0.0, 0.81 } }) do
		local p = {}
		for i = 1, 3 do p[i] = r.min[i] + math.floor(f[i] * (r.size[i] - 1) + 0.5) end
		picks[#picks + 1] = p
	end
	for _, p in ipairs(picks) do
		local imgs = {}
		for _, q in ipairs(S.images(r, p[1], p[2], p[3])) do
			imgs[#imgs + 1] = string.format("%d,%d,%d", q.x - r.min[1], q.y, q.z - r.min[3])
		end
		table.sort(imgs)
		out.images[#out.images + 1] = string.format('{"id":"%s","at":[%d,%d,%d],"images":["%s"]}', a.id,
			p[1] - r.min[1], p[2], p[3] - r.min[3], table.concat(imgs, '","'))
	end
end

-- Builds whose symmetry is known: each as a list of blocks "x,y,z=colour".
local builds = {
	{ "0,0,0=red" },
	{ "0,0,0=red", "1,0,0=red" },
	{ "0,0,0=red", "1,0,0=blue" },
	{ "0,0,0=red", "1,0,0=red", "0,1,0=red" },
	{ "0,0,0=red", "2,0,0=red", "1,1,0=red", "1,-1,0=red", "1,0,1=red", "1,0,-1=red" },
	{ "0,0,0=red", "1,0,0=red", "0,0,1=red", "1,0,1=red", "0,1,0=blue" },
	{ "0,0,0=red", "1,0,0=red", "2,0,0=red", "0,0,1=red" },
}
for _, b in ipairs(builds) do
	local nodes = {}
	for _, e in ipairs(b) do
		local x, y, z, c = e:match("^(-?%d+),(-?%d+),(-?%d+)=(%a+)$")
		nodes[(2 * x + 1) .. "," .. (2 * y + 1) .. "," .. (2 * z + 1)] = c
	end
	local g, entry = S.detect(nodes)
	out.detect[#out.detect + 1] = string.format('{"blocks":["%s"],"symbol":"%s","order":%d}', table.concat(b, '","'),
		entry and entry.symbol or "?", #g.ops)
end
-- The crystal exhibits' live pipeline (exhibit_live.lua) on the game's sample records and on cases it must reject, and its fingerprints, for web/js/exhibit_live.js.
local function json(v)
	local t = type(v)
	if t == "number" then return v == math.floor(v) and string.format("%d", v) or string.format("%.17g", v) end
	if t == "string" then return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"' end
	if t == "boolean" then return tostring(v) end
	if t ~= "table" then return "null" end
	local n = 0
	for _ in pairs(v) do n = n + 1 end
	if n == #v then
		local o = {}
		for i, x in ipairs(v) do o[i] = json(x) end
		return "[" .. table.concat(o, ",") .. "]"
	end
	local o = {}
	for k, x in pairs(v) do o[#o + 1] = json(tostring(k)) .. ":" .. json(x) end
	table.sort(o)
	return "{" .. table.concat(o, ",") .. "}"
end
local elements = dofile("mods/crystalminer/exhibit_elements.lua")
local Live = loadfile("mods/crystalminer/exhibit_live.lua")(elements)
local live = { records = {}, prepared = {}, rejected = {}, fingerprints = {}, names = {} }
local function synthetic()
	local sites = {}
	for x = 0.25, 0.75, 0.5 do for y = 0.25, 0.75, 0.5 do for z = 0.25, 0.75, 0.5 do
		sites[#sites + 1] = { abc = { x, y, z }, species = { { element = (#sites % 2 == 0) and "O" or "Sr", occu = 1 } } }
	end end end
	return { id = "synthetic", name = "Synthetic", md5 = "synthetic", lattice = { a = 6, b = 6, c = 6, alpha = 90, beta = 90, gamma = 90,
		matrix = { { 6, 0, 0 }, { 0, 6, 0 }, { 0, 0, 6 } } }, sites = sites }
end
local records = dofile("tests/fixtures/exhibit_records.lua")
records[#records + 1] = synthetic()
for _, r in ipairs(records) do
	live.records[#live.records + 1] = r
	local p, err = Live.prepare(r)
	live.prepared[#live.prepared + 1] = p and { atoms = p.atoms, lo = p.lo, hi = p.hi, cell = p.cell, bonds = p.bonds, formula = p.formula } or { error = err }
	local fp = Live.fingerprint(r)
	live.fingerprints[#live.fingerprints + 1] = { fp.formula, fp.anonymous }
end
local slab = synthetic(); slab.lattice.c = 20; slab.lattice.matrix[3][3] = 20
local disorder = synthetic(); disorder.sites[1].species[1].occu = 0.5
local unknown = synthetic(); unknown.sites[1].species[1].element = "Xx"
local collision = synthetic(); collision.sites[2].abc = collision.sites[1].abc
for _, r in ipairs({ slab, disorder, unknown, collision }) do
	local p, err = Live.prepare(r)
	live.rejected[#live.rejected + 1] = { record = r, error = err or "accepted" }
end
for _, n in ipairs({ "BaTi(SiO3)3", "Ca(TiS2)4", "Ag10Sn10CS20N", "BaTiO3-0", "junk", "SrTiO3", "MgMn4O8-0", "(Fe2O3", "Fe2O3)" }) do
	local fp = Live.name_fingerprint(n)
	live.names[#live.names + 1] = { n, fp and fp.formula or false, fp and fp.anonymous or false }
end
for _, f in ipairs({ "SrTiO3", "CaTiO3", "MgMn4O8", "TiCaO3" }) do
	local fp = Live.fingerprint_formula(f)
	live.names[#live.names + 1] = { "formula:" .. f, fp.formula, fp.anonymous }
end
-- Sign lettering for live panels (web/js/sign_layout.js): SG.texture on panel texts with quotes, minus signs, letters outside ASCII, paragraphs and a text too long for the larger body size.
local SG = require("signs")
live.signs = {}
for _, t in ipairs({
	"# Ba2Ti6N2O11\n## Ba2N2O11Ti6\ncell a 5.71 b 5.71 c 23.10 A\nangles 90.00 90.00 120.00 deg\n21 atoms\nMaterials Project record 609d9d0f\nSource: MPContribs\nAtoms: Jmol colours. White lines: bonds. Orange: unit cell.",
	"# It's 'quoted' at -4 and m-3m\n## first meta\n## second meta\nbody with é, ü, Å and an emoji 🙂\n\nA second paragraph.\n\n",
	"no title, only body text",
	"# " .. string.rep("Long title ", 4) .. "\n" .. string.rep("A body long enough to fall back to the smaller set of letters. ", 9),
	"# " .. string.rep("Too long ", 3) .. "\n" .. string.rep("Far more than any panel can hold, so it does not fit at all. ", 30),
}) do
	local tex, fits, w, h = SG.texture("panel", t)
	live.signs[#live.signs + 1] = { text = t, texture = tex, fits = fits, w = w, h = h }
end
-- Gallery 2's holograms (hologram_logic.lua), for web/js/hologram_logic.js: the points of the baked records and the sample records at every level of detail, the plaque text (as hologram.lua words it), and the level of detail and visibility rules.
local H = loadfile("mods/crystalminer/hologram_logic.lua")(elements, dofile("mods/crystalminer/gallery2_layout.lua"))
live.holograms = {}
local holo_records = dofile("mods/crystalminer/exhibit_data.lua")
for _, r in ipairs(records) do local p = Live.prepare(r); if p then holo_records[#holo_records + 1] = p end end
-- A dense grid, more than MAX_POINTS points, to thin.
local dense = { id = "densegrid0000", name = "Dense", formula = "Dense", sites = 8, lo = { 0, 0, 0 }, hi = { 11, 9, 7 },
	lattice = { a = 8.4, b = 7, c = 5.6 }, atoms = {}, bonds = {}, cell = {} }
for x = 0, 11 do for y = 0, 9 do for z = 0, 7 do
	if x % 4 == 0 and y % 4 == 0 and z % 4 == 0 then dense.atoms[#dense.atoms + 1] = { x, y, z, "Na" }
	elseif (x + y + z) % 2 == 0 then dense.bonds[#dense.bonds + 1] = { x, y, z }
	else dense.cell[#dense.cell + 1] = { x, y, z } end
end end end
holo_records[#holo_records + 1] = dense
for _, r in ipairs(holo_records) do
	for tier = 1, 3 do
		local flat = {}
		for _, p in ipairs(H.points(r, { x = -47, y = 4, z = 30 }, tier)) do
			flat[#flat + 1] = { p.pos.x, p.pos.y, p.pos.z, p.colour, p.kind, p.size, p.spread, p.amount, p.exptime }
		end
		local l = r.lattice
		live.holograms[#live.holograms + 1] = { grid = { lo = r.lo, hi = r.hi, atoms = r.atoms, bonds = r.bonds, cell = r.cell }, tier = tier, points = flat,
			plaque = string.format("# Exhibit %d: %s\ncell %.2f / %.2f / %.2f A\n%d atoms\nMaterials Project record %s\nScale 1:%.1f",
				3, r.name or r.formula or "Crystal structure", l.a, l.b, l.c, r.sites or #r.atoms, r.id:sub(1, 8), 1 / H.scale(r)),
			record = { record_name = r.name, formula = r.formula, lattice = { a = l.a, b = l.b, c = l.c }, sites = r.sites, id = r.id } }
	end
end
live.lod = {}
for _, d in ipairs({ 0, 11, 11.5, 17, 17.5, 30, 30.5, 33, 34 }) do
	live.lod[#live.lod + 1] = { d, H.lod(d), H.lod(d, 1), H.lod(d, 2), H.lod(d, 3) }
end
live.visible = {}
for _, p in ipairs({ { -38, 1, 20 }, { -67, 1, 20 }, { -68, 1, 20 }, { -72, 1, 20 }, { -74, 1, 20 }, { -38, 23, 20 }, { -38, 1, 68 }, { 0, 1, 70 } }) do
	live.visible[#live.visible + 1] = { p, H.visible({ x = p[1], y = p[2], z = p[3] }, false), H.visible({ x = p[1], y = p[2], z = p[3] }, true) }
end
-- The live loading notice's texts (exhibit_notice.lua), for exhibit_fetch.js.
local N = dofile("mods/crystalminer/exhibit_notice.lua")
live.notice = {}
for _, c in ipairs({ { "searching", 0 }, { "searching", 1.7 }, { "searching", 5 }, { "checking", 12.3, "Checking record 4 of up to 60" }, { "checking", 3 }, { "building", 41.9 }, { "bogus", -2 } }) do
	local t, st = N.lines(c[1], c[2], c[3]); live.notice[#live.notice + 1] = { "lines", c[1], c[2], c[3] or false, t, st }
end
for _, name in ipairs({ "SrTiO3", string.rep("Ab", 30) }) do local t, st = N.success(name, 4); live.notice[#live.notice + 1] = { "success", name, t, st } end
for _, reason in ipairs({ "Could not load a new structure; showing CaTiO3", false }) do local t, st = N.failure(reason or nil); live.notice[#live.notice + 1] = { "failure", reason, t, st } end
live.notice_seconds = { N.SUCCESS_SECONDS, N.FAILURE_SECONDS }
print('{"images":[' .. table.concat(out.images, ",") .. '],"detect":[' .. table.concat(out.detect, ",") .. '],"live":' .. json(live) .. "}")
