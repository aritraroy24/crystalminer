-- Exports what the web version (web/) needs, computed by the game's own engine, so the science is defined once, in Lua, and tested there. Run from the repository root:
--   luajit tools/export_web.lua
-- It writes web/data/crystalminer.json (worlds, symmetry operations, markers, lessons, guides, Prism's words) and web/api/prompt.txt (Prism's grounding text, read only by the server, never sent to the browser).
--
-- Each world is exported in its own coordinates: x and z from the corner of its build space, y as in the game (the ground is at y = 0). Operations stay in the engine's doubled coordinates (a node at x has its centre at 2x + 1), with the origin moved to match.
package.path = "mods/crystalminer/?.lua;" .. package.path
local S = require("symmetry")
local L = require("lessons")
local content = require("content")
local E = loadfile("mods/crystalminer/elements.lua")(S)
local G = loadfile("mods/crystalminer/gate.lua")(S)
local GD = require("guides")
local Tutor = loadfile("mods/crystalminer/tutor.lua")(S, content)

---------------------------------------------------------------------------- JSON

-- A table is an array only if its keys are exactly 1..n; tier tables ({ [0] = ..., [3] = ... }) become objects.
local function is_array(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do if t[i] == nil then return false end end
	return true
end

local function json(v)
	local t = type(v)
	if t == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return (string.format("%.4f", v):gsub("0+$", ""))
	end
	if t == "string" then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", ""):gsub("\t", "\\t") .. '"'
	end
	if t == "boolean" then return tostring(v) end
	if t == "table" then
		if next(v) == nil then return "[]" end
		if is_array(v) then
			local o = {}
			for i, x in ipairs(v) do o[i] = json(x) end
			return "[" .. table.concat(o, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local o = {}
		for _, k in ipairs(keys) do o[#o + 1] = json(tostring(k)) .. ":" .. json(v[k]) end
		return "{" .. table.concat(o, ",") .. "}"
	end
	return "null"
end

---------------------------------------------------------------------------- helpers

--- An operation as one flat list: the 9 entries of W (row-major), then t.
local function flat(o)
	return { o.w[1], o.w[2], o.w[3], o.w[4], o.w[5], o.w[6], o.w[7], o.w[8], o.w[9], o.t[1], o.t[2], o.t[3] }
end

--- A region in its world's own coordinates (see the top of this file).
local function local_region(r)
	local ops = {}
	for i, o in ipairs(r.group.ops) do ops[i] = flat(o) end
	return {
		size = r.size, cell = r.cell, ground = r.min[2],
		origin = { r.origin[1] - 2 * r.min[1], r.origin[2], r.origin[3] - 2 * r.min[3] },
		ops = ops,
	}
end

--- Marker dots as { x, y, z, colour, kind, size, symbol } in the world's coordinates.
local function local_dots(r)
	local out = {}
	for _, d in ipairs(E.dots(r)) do
		out[#out + 1] = { d.pos.x - r.min[1], d.pos.y, d.pos.z - r.min[3], d.colour, d.kind, d.size, d.symbol or "" }
	end
	-- E.dots gathers axes in a hash table, so their order changes from run to run; sorted, the file only changes when the content does.
	table.sort(out, function(a, b)
		for i = 1, 7 do
			if a[i] ~= b[i] then return tostring(a[i]) < tostring(b[i]) end
		end
		return false
	end)
	return out
end

--- Quiz questions by tier, with the ids the game uses ("area.tier.index").
local function quiz(area)
	local out = {}
	for t in pairs(area.quiz or {}) do
		local qs = {}
		for _, q in ipairs(L.questions(area, t)) do
			qs[#qs + 1] = { id = q.id, q = q.q, options = q.options, answer = q.answer, why = q.why, hint = q.hint, display = q.display }
		end
		out[tostring(t)] = qs
	end
	return out
end

local function explain(area)
	local out = {}
	for t, lines in pairs(area.explain or {}) do out[tostring(t)] = lines end
	return out
end

local function guide(id)
	local g = GD[id]
	if not g then return nil end
	return { title = g.title, what = g.what, steps = g.steps, see = g.see, example = g.example, word = g.word, count = g.count }
end

---------------------------------------------------------------------------- worlds

local regions = {}
for _, a in ipairs(content.regions) do
	local r = S.region(L.region_spec(a, a.generators))
	local entry = {
		id = a.id, name = a.name, tier = a.tier, style = a.style,
		-- The Mystery Lab's symmetry is the puzzle, so its symbol is not sent; its operations are, to copy blocks.
		symbol = a.hidden and "?" or a.symbol, hidden = a.hidden ~= nil,
		explain = explain(a), quiz = quiz(a), guide = guide(a.id),
		region = local_region(r), dots = a.hidden and {} or local_dots(r),
		showcase = { text = a.showcase and a.showcase.text or nil, blocks = L.showcase_blocks(a) },
		challenges = a.challenges, free = a.free == true,
	}
	if a.free then
		-- The Free Lab can take any point group that fits the block grid.
		entry.free_groups = {}
		for _, e in ipairs(S.catalog) do
			local ok, fr = pcall(S.region, L.region_spec(a, e.generators))
			if ok then
				entry.free_groups[#entry.free_groups + 1] = { symbol = e.symbol, system = e.system, region = local_region(fr), dots = local_dots(fr) }
			end
		end
	end
	regions[#regions + 1] = entry
end

---------------------------------------------------------------------------- the Symmetry Gate

local gate = content.gate
local box = G.box(gate.at)
local displays = {}
for _, d in ipairs(G.displays(gate.at)) do
	local function rel(list)
		local out = {}
		for i, p in ipairs(list) do out[i] = { p.x - box.min[1], p.y, p.z - box.min[3] } end
		return out
	end
	displays[#displays + 1] = {
		letter = d.letter, operation = d.operation, colour = d.colour,
		original = rel(d.original), copy = rel(d.copy),
		floor = { d.floor[1] - box.min[1], d.floor[2] - box.min[1], d.floor[3] - box.min[3], d.floor[4] - box.min[3] },
	}
end

---------------------------------------------------------------------------- detection

-- What /whatsymmetry needs: the 48 operations of the cube (every grid symmetry is one of them) and each point group's signature.
local cube = {}
for i, o in ipairs(S.point_group("m-3m").group.ops) do cube[i] = flat(o) end
local catalog = {}
for i, e in ipairs(S.catalog) do
	catalog[i] = { symbol = e.symbol, system = e.system, signature = e.signature_key, order = #e.group.ops, grid = S.fits_grid(e.group) }
end

---------------------------------------------------------------------------- write

---------------------------------------------------------------------------- the museum's exhibits

-- Gallery 3's clue crystals (museum.lua): the question each one asks, by exhibit id.
local clues = {}
for _, e in ipairs(content.museum.exhibits) do
	if e.clue then clues[e.id] = { name = e.name, q = e.clue.q, options = e.clue.options, answer = e.clue.answer, why = e.clue.why } end
end

-- The crystal-exhibit rooms show one of the structures baked into the game (exhibit_data.lua), as exhibit_dynamic.lua builds them when it cannot load a live one: atoms as blocks on a grid of 0.7 angstrom, bonds and the unit cell as marker points, and an information panel. Positions are from the model's origin, in the game's axes (y up).
local SG = require("signs")
local elements = dofile("mods/crystalminer/exhibit_elements.lua")
local Live = loadfile("mods/crystalminer/exhibit_live.lua")(elements)
local function display_name(r)
	if type(r.name) == "string" and #r.name <= 24 and not r.name:find("%s") then return r.name end
	return r.formula or "Live structure"
end
-- As exhibit_dynamic.lua's plaque_text.
local function plaque_text(r)
	local l = r.lattice
	return string.format("# %s\n## %s\ncell a %.2f b %.2f c %.2f A\nangles %.2f %.2f %.2f deg\n%d atoms\nMaterials Project record %s\nSource: MPContribs\nAtoms: Jmol colours. White lines: bonds. Orange: unit cell.",
		display_name(r), r.formula or "", l.a, l.b, l.c, l.alpha, l.beta, l.gamma, r.sites, r.id:sub(1, 8))
end
local structures = {}
for _, r in ipairs(dofile("mods/crystalminer/exhibit_data.lua")) do
	local atoms = {}
	for _, a in ipairs(r.atoms) do atoms[#atoms + 1] = { a[1] - r.lo[1], a[3] - r.lo[3], a[2] - r.lo[2], a[4] } end
	local dots = {}
	for _, d in ipairs(Live.dots(r, { x = 0, y = 0, z = 0 })) do dots[#dots + 1] = { d.pos.x, d.pos.y, d.pos.z, d.colour, d.kind, d.size } end
	local text = plaque_text(r)
	local tex, _, w, h = SG.texture("panel", text)
	-- grid: the record on its 0.7 angstrom grid (atoms, bonds and cell voxels), which Gallery 2's holograms are made from (hologram_logic.lua).
	structures[#structures + 1] = { id = r.id, name = display_name(r), record_name = r.name, formula = r.formula, md5 = r.md5, fingerprint = Live.fingerprint(r), footprint = Live.footprint(r),
		lattice = { a = r.lattice.a, b = r.lattice.b, c = r.lattice.c }, sites = r.sites,
		grid = { lo = r.lo, hi = r.hi, atoms = r.atoms, bonds = r.bonds, cell = r.cell },
		atoms = atoms, dots = dots, plaque = { text = text, texture = tex, w = w, h = h } }
end
-- Colours for drawing, and the radii the live pipeline (web/js/exhibit_live.js) needs for bonds.
local element_colours, element_data = {}, {}
for el, e in pairs(elements) do element_colours[el] = e.hex; element_data[el] = { hex = e.hex, radius = e.radius } end

-- The panel and plaque formats and their glyph metrics, so the browser can letter what only it knows (a live structure's panel, a hologram's plaque) as SG.texture would (web/js/sign_layout.js).
local lettering = { formats = {}, metrics = {} }
for _, name in ipairs({ "panel", "plaque" }) do
	local f = SG.FORMATS[name]
	lettering.formats[name] = f
	for _, set in ipairs({ f.title, f.meta, unpack(f.body) }) do lettering.metrics[set] = SG.METRICS[set] end
end

-- Gallery 2's holograms (hologram.lua, hologram_logic.lua): where the six pedestals are and how a structure becomes dust clouds, for web/js/hologram.js.
local layout = dofile("mods/crystalminer/gallery2_layout.lua")
local H = loadfile("mods/crystalminer/hologram_logic.lua")(elements, layout)
local hologram = { centres = layout.pedestals.centres, gallery = H.GALLERY, show_margin = H.SHOW_MARGIN, hide_margin = H.HIDE_MARGIN,
	max_points = H.MAX_POINTS, max_span = H.MAX_SPAN, static_angle = H.STATIC_ANGLE, hover_base = H.HOVER_BASE, lod = H.LOD,
	look = { atoms = { H.ATOM_SPREAD, H.ATOM_SIZE, H.ATOM_AMOUNT, H.ATOM_EXPTIME }, bonds = { H.BOND_SPREAD, H.BOND_SIZE, H.BOND_AMOUNT, H.BOND_EXPTIME },
		cells = { H.CELL_SPREAD, H.CELL_SIZE, H.CELL_AMOUNT, H.CELL_EXPTIME } } }

local T = content.tutor
local data = {
	generated_by = "tools/export_web.lua",
	tiers = content.tiers, intro = content.intro, glossary = content.glossary,
	gate = { id = gate.id, name = gate.name, size = box.size, quiz = quiz(gate), guide = guide("symmetry_gate"), displays = displays },
	regions = regions,
	detect = { cube = cube, catalog = catalog },
	marker_colours = E.COLOURS,
	museum = { clues = clues, structures = structures, element_colours = element_colours, elements = element_data, lettering = lettering, hologram = hologram, intro = content.museum.intro,
		guides = { tryit_pad = guide("tryit_pad") }, welcome = content.lobby.welcome, information = content.lobby.information },
	tutor = { name = T.name, role = T.role, welcome = T.welcome, about = T.about, disclaimer = T.disclaimer, thinking = T.thinking,
		here = T.here, suggestions = T.suggestions, board = T.board, max_chars = Tutor.MAX_CHARS, history = Tutor.CHAT_HISTORY },
}

local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
write("web/data/crystalminer.json", json(data) .. "\n")
write("web/api/prompt.txt", Tutor.chat_system_prompt() .. "\n")

-- The textures the web version draws, copied so that web/ can be uploaded on its own.
local TEXTURES = { "floor", "floor_alt", "frame", "plaza", "stone_brick", "pillar", "brick", "ground", "marble", "planks",
	"carpet", "teleporter", "glass", "tutor_avatar", "tutor_icon", "tutor_user", "tutor_prism_face", "tutor_prism", "tutor_screen" }
for i = 0, 4 do TEXTURES[#TEXTURES + 1] = "border_" .. i end
for _, c in ipairs({ "white", "light_grey", "grey", "black", "brown", "red", "orange", "yellow", "lime", "green", "cyan",
	"light_blue", "blue", "purple", "magenta", "pink" }) do TEXTURES[#TEXTURES + 1] = c end
for _, a in ipairs(content.regions) do TEXTURES[#TEXTURES + 1] = "guide_" .. a.id end
TEXTURES[#TEXTURES + 1] = "guide_symmetry_gate"
TEXTURES[#TEXTURES + 1] = "guide_tryit_pad"
local copied = 0
for _, name in ipairs(TEXTURES) do
	local f = io.open("mods/crystalminer/textures/crystalminer_" .. name .. ".png", "rb")
	if f then
		write("web/textures/" .. name .. ".png", f:read("*a"))
		f:close()
		copied = copied + 1
	end
end
io.stderr:write(string.format("web/data/crystalminer.json: %d worlds; web/api/prompt.txt: %d characters; %d textures\n", #regions, #Tutor.chat_system_prompt(), copied))
