-- Signs with real lettering. Luanti has no text on nodes, so a sign is a flat entity whose
-- texture is assembled from glyph images ([combine), rendered from DejaVu Sans, Sans Bold and
-- Sans Condensed Bold by tools/make_glyphs.py, which also writes the width of every glyph to
-- sign_metrics.lua.
--
-- Text: a first line starting with "# " is the title; lines right after it starting with "## " are
-- meta lines (small, bold, in the accent colour); the rest is body text, an empty line a paragraph
-- break. On a banner or a label, everything after the title is a centred subtitle.
--
-- Every format has a fixed width; its height is chosen from the text, in steps of 32 px (a quarter
-- node at 128 px per node), up to the size the format had before (so a sign never grows). A long
-- text falls back to a smaller body size.
--
-- The layout part is pure Lua (tested in tests/test_signs.lua); the entity is registered only
-- when running inside Luanti.

local SG = {}

local M
if core then
	M = dofile(core.get_modpath("crystalminer") .. "/sign_metrics.lua")
else
	M = require("sign_metrics")
end
SG.METRICS = M

SG.PX = 128   -- texture px per node
SG.STEP = 32  -- heights are multiples of this

-- x0: left edge of the text; pr: right padding; top/bottom: padding (top includes a top bar);
-- after: space between the title block and the body; pgap: extra space for an empty line.
SG.FORMATS = {
	board = { w = 768, minh = 256, maxh = 576, title = "b34", meta = "b17", body = { "r20", "r18", "r16" },
		x0 = 48, pr = 48, top = 40, bottom = 38, rule = { w = 72, h = 4, above = 10, below = 16 }, pgap = 12 },
	panel = { w = 576, minh = 192, maxh = 384, title = "b26", meta = "b17", body = { "r20", "r18" },
		x0 = 40, pr = 32, top = 26, bottom = 28, after = 8, pgap = 10, bar = "left" },
	plaque = { w = 384, minh = 128, maxh = 192, title = "b26", meta = "b17", body = { "r18", "r16" },
		x0 = 30, pr = 22, top = 16, bottom = 18, after = 4, pgap = 6, bar = "left" },
	banner = { w = 768, minh = 160, maxh = 192, title = { "b52", "c44" }, sub = "r24", pad = 40, vpad = 24, bar = 8, centred = true },
	label = { w = 192, minh = 96, maxh = 96, title = { "b34" }, sub = "r16", pad = 8, vpad = 4, bar = 6, centred = true },
}

local KNOWN = M.r20.adv

--- UTF-8 string to a list of code points; unknown characters become "?".
function SG.codepoints(s)
	local out, i = {}, 1
	while i <= #s do
		local b = s:byte(i)
		local c, n
		if b < 0x80 then c, n = b, 1
		elseif b < 0xE0 then c, n = (b % 0x20) * 64 + (s:byte(i + 1) % 64), 2
		elseif b < 0xF0 then c, n = (b % 0x10) * 4096 + (s:byte(i + 1) % 64) * 64 + (s:byte(i + 2) % 64), 3
		else c, n = 63, 4 end
		out[#out + 1] = KNOWN[c] and c or 63
		i = i + n
	end
	return out
end

--- Code points of one word, with typography: ' becomes an opening or closing quote, and a hyphen
-- before a digit (m-3m, -4) a minus sign.
local function word_cps(word)
	local cps = SG.codepoints(word)
	for i, c in ipairs(cps) do
		if c == 39 then
			cps[i] = (i == 1 or cps[i - 1] == 40) and 8216 or 8217
		elseif c == 45 and cps[i + 1] and cps[i + 1] >= 48 and cps[i + 1] <= 57 then
			cps[i] = 8722
		end
	end
	return cps
end

--- Width in px of a run of code points in a glyph set.
function SG.measure(set, cps)
	local m, w = M[set], 0
	for i, c in ipairs(cps) do
		w = w + m.adv[c] + (i > 1 and m.track or 0)
	end
	return w
end

--- Wraps a paragraph into lines no wider than maxw px. Returns a list of { cps, width }.
local function wrap(set, para, maxw)
	local m = M[set]
	local space = m.adv[32] + m.track
	local lines, line, w = {}, {}, 0
	for word in para:gmatch("%S+") do
		local cps = word_cps(word)
		local ww = SG.measure(set, cps)
		if #line > 0 and w + space + m.track + ww > maxw then
			lines[#lines + 1] = { cps = line, w = w }
			line, w = {}, 0
		end
		if #line > 0 then
			line[#line + 1] = 32
			w = w + space + m.track
		end
		for _, c in ipairs(cps) do line[#line + 1] = c end
		w = w + ww
	end
	if #line > 0 then lines[#lines + 1] = { cps = line, w = w } end
	return lines
end
SG.wrap = wrap

--- Splits sign text into title, meta lines and body paragraphs ("" = an empty line).
local function parse(text)
	local title, meta, paras = nil, {}, {}
	local stage = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if stage == 0 and line:sub(1, 2) == "# " then
			title, stage = line:sub(3), 1
		elseif stage <= 1 and line:sub(1, 3) == "## " then
			meta[#meta + 1], stage = line:sub(4), 1
		else
			stage = 2
			if line:sub(1, 3) == "## " then line = line:sub(4) elseif line:sub(1, 2) == "# " then line = line:sub(3) end
			paras[#paras + 1] = line
		end
	end
	while paras[#paras] == "" do paras[#paras] = nil end
	return title, meta, paras
end
SG.parse = parse

local function snap(h) return math.ceil(h / SG.STEP) * SG.STEP end

-- Adds the glyphs of one line to parts. y is the top of the line box.
local function draw_line(parts, set, cps, x, y)
	local m = M[set]
	local gy = y + math.floor((m.lh - m.h) / 2)
	local pen = x
	for _, c in ipairs(cps) do
		local xo = m.xoff[c]
		if xo then
			parts[#parts + 1] = (math.floor(pen + 0.5) + xo) .. "," .. gy .. "=crystalminer_" .. set .. "_" .. c .. ".png"
		end
		pen = pen + m.adv[c] + m.track
	end
end

-- Layout of a board, panel or plaque with one body set. Returns parts (without the background),
-- the height, and whether the text fits.
local function layout_block(f, text, body)
	local title, meta, paras = parse(text)
	local maxw = f.w - f.x0 - f.pr
	local plan, y, fits = {}, f.top, true
	local function add(set, lines)
		for _, l in ipairs(lines) do
			if l.w > maxw then fits = false end
			plan[#plan + 1] = { set, l.cps, y }
			y = y + M[set].lh
		end
	end
	if title then add(f.title, wrap(f.title, title, maxw)) end
	if #meta > 0 then y = y + 2 end
	for _, m in ipairs(meta) do add(f.meta, wrap(f.meta, m, maxw)) end
	local rule_y
	if f.rule and title then
		y = y + f.rule.above
		rule_y = y
		y = y + f.rule.h + f.rule.below
	elseif title or #meta > 0 then
		y = y + f.after
	end
	for _, p in ipairs(paras) do
		if p == "" then y = y + f.pgap else add(body, wrap(body, p, maxw)) end
	end
	local content = y + f.bottom
	local h = math.max(f.minh, snap(content))
	if h > f.maxh then fits = false end
	local shift = math.floor((math.min(h, f.maxh) - content) / 2)
	if shift < 0 then shift = 0 end
	local parts = {}
	if rule_y then parts[#parts + 1] = f.x0 .. "," .. (rule_y + shift) .. "=crystalminer_sign_rule.png" end
	for _, p in ipairs(plan) do draw_line(parts, p[1], p[2], f.x0, p[3] + shift) end
	return parts, math.min(h, f.maxh), fits
end

-- Layout of a banner or a label: a centred title (in the first set it fits in, else wrapped in
-- the last) and a centred subtitle.
local function layout_centred(f, text)
	local title, meta, paras = parse(text)
	local sub = {}
	for _, m in ipairs(meta) do sub[#sub + 1] = m end
	for _, p in ipairs(paras) do if p ~= "" then sub[#sub + 1] = p end end
	local maxw = f.w - 2 * f.pad
	local tset, tlines = f.title[#f.title], nil
	for _, set in ipairs(f.title) do
		local cps = {}
		for _, l in ipairs(wrap(set, title or "", 1e9)) do cps = l.cps end
		if SG.measure(set, cps) <= maxw then
			tset, tlines = set, { { cps = cps, w = SG.measure(set, cps) } }
			break
		end
	end
	tlines = tlines or wrap(tset, title or "", maxw)
	local slines = #sub > 0 and wrap(f.sub, table.concat(sub, " "), maxw) or {}
	local gap = #slines > 0 and 6 or 0
	local content = #tlines * M[tset].lh + gap + #slines * M[f.sub].lh
	local h = f.minh
	if content > h - f.bar - 2 * f.vpad then h = snap(content + f.bar + 2 * f.vpad) end
	local fits = h <= f.maxh
	h = math.min(h, f.maxh)
	local y = math.floor((h - f.bar - content) / 2)
	if f.minh == f.maxh then y = math.max(0, y) end
	local parts = {}
	for _, l in ipairs(tlines) do
		if l.w > maxw then fits = false end
		draw_line(parts, tset, l.cps, (f.w - l.w) / 2, y)
		y = y + M[tset].lh
	end
	y = y + gap
	for _, l in ipairs(slines) do
		if l.w > maxw then fits = false end
		draw_line(parts, f.sub, l.cps, (f.w - l.w) / 2, y)
		y = y + M[f.sub].lh
	end
	if y + f.bar > h then fits = false end
	return parts, h, fits
end

--- Texture string for a sign, whether the text fitted, and the size in px.
-- opts.tier (1 to 4) colours the side bar of a panel or plaque with the tier's colour.
function SG.texture(format, text, opts)
	local f = SG.FORMATS[format]
	local parts, h, fits
	if f.centred then
		parts, h, fits = layout_centred(f, text)
	else
		for _, body in ipairs(f.body) do
			parts, h, fits = layout_block(f, text, body)
			if fits then break end
		end
	end
	local head = { "[combine:" .. f.w .. "x" .. h .. ":0,0=crystalminer_sign_" .. format .. "_" .. h .. ".png" }
	if opts and opts.tier and f.bar == "left" then
		for y = 0, h - 1, SG.STEP do head[#head + 1] = "0," .. y .. "=crystalminer_sign_bar_" .. math.min(opts.tier, 4) .. ".png" end
	end
	for _, p in ipairs(parts) do head[#head + 1] = p end
	return table.concat(head, ":"), fits, f.w, h
end

-- Yaw that makes a sign face each direction (towards the reader).
SG.YAW = { n = 0, w = math.pi / 2, s = math.pi, e = 3 * math.pi / 2 }
SG.DIR = { n = { x = 0, z = 1 }, s = { x = 0, z = -1 }, e = { x = 1, z = 0 }, w = { x = -1, z = 0 } }

if not core then return SG end

---------------------------------------------------------------------------- the entity

core.register_entity("crystalminer:sign", {
	initial_properties = {
		visual = "upright_sprite", textures = { "crystalminer_blank.png", "crystalminer_blank.png" },
		physical = false, pointable = false, static_save = true, visual_size = { x = 1, y = 1 },
	},
	on_activate = function(self, staticdata)
		local d = staticdata ~= "" and core.deserialize(staticdata) or nil
		-- A sign from an earlier build of the world removes itself: signs far from players are
		-- stored, not active, so a rebuild cannot find them to replace them.
		local known = d and (SG.FORMATS[d.format] or d.picture)
		if not known or d.v ~= crystalminer.WORLD_VERSION then
			self.object:remove()
			return
		end
		if d.opts and d.opts.holo_pedestal then
			local generation = crystalminer.hologram_generations and crystalminer.hologram_generations[d.opts.holo_pedestal]
			if generation ~= d.opts.holo_gen then self.object:remove(); return end
		end
		self.data = d
		if d.picture then
			self.object:set_properties({ textures = { d.picture, "crystalminer_sign_back.png" },
				visual_size = { x = d.w, y = d.h } })
			return
		end
		local tex, _, w, h = SG.texture(d.format, d.text, d.opts)
		self.object:set_properties({ textures = { tex, "crystalminer_sign_back.png" },
			visual_size = { x = w / SG.PX, y = h / SG.PX } })
	end,
	get_staticdata = function(self) return core.serialize(self.data) end,
})

--- Places a sign whose centre is at pos, facing dir ("n", "e", "s" or "w"). Removes any sign
-- already within half a node of that spot, so rebuilding never doubles them. opts: see SG.texture.
function SG.place(pos, dir, format, text, opts)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.6)) do
		local e = obj:get_luaentity()
		if e and e.name == "crystalminer:sign" then obj:remove() end
	end
	local obj = core.add_entity(pos, "crystalminer:sign",
		core.serialize({ format = format, text = text, opts = opts, v = crystalminer.WORLD_VERSION }))
	if obj then obj:set_yaw(SG.YAW[dir]) end
	return obj
end

--- A framed picture (a texture) whose centre is at pos, facing dir, w by h nodes.
function SG.place_picture(pos, dir, texture, w, h)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.6)) do
		local e = obj:get_luaentity()
		if e and e.name == "crystalminer:sign" then obj:remove() end
	end
	local obj = core.add_entity(pos, "crystalminer:sign",
		core.serialize({ picture = texture, w = w, h = h, v = crystalminer.WORLD_VERSION }))
	if obj then obj:set_yaw(SG.YAW[dir]) end
	return obj
end

--- A sign on the face of a wall node: wall is the node, dir the side it faces.
function SG.on_wall(wall, dir, format, text, dy, opts)
	local d = SG.DIR[dir]
	local p = { x = wall.x + d.x * 0.52, y = wall.y + (dy or 0), z = wall.z + d.z * 0.52 }
	return SG.place(p, dir, format, text, opts)
end

return SG
