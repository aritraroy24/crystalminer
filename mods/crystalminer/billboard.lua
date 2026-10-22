-- Prism's billboard: a big pixel screen high on the south wall of Visitor information, above Prism's desk, where its large letters can be read from across the room. It shows the latest question anyone asked Prism (without the asker's name) and Prism's answer, typed out line by line; between conversations, a welcome and the words to know, one at a time. Right-clicking it opens the chat window (tutor_window.lua), like the desk and /ask.
--
-- The letters are the pixel font of tools/make_pixel_font.py (pixel_font.lua): fixed width, so a line is a number of cells. The layout part is pure Lua (tested in tests/test_billboard.lua); the entity is registered only when running inside Luanti.

local F
if core then
	F = dofile(core.get_modpath("crystalminer") .. "/pixel_font.lua")
else
	F = require("pixel_font")
end

local B = { FONT = F }

B.MARGIN = 54                  -- px between the frame and the text, left and right
B.BODY_TOP = F.screen.header + 24
B.COLS = math.floor((F.screen.w - 2 * B.MARGIN) / F.w)
B.ROWS = math.floor((F.screen.h - B.BODY_TOP - 40) / F.h)
B.SIZE = { w = 12, h = 7 }     -- nodes; the screen texture is 128 px per node

local TYPO = { [8216] = 39, [8217] = 39, [8220] = 34, [8221] = 34 }  -- curly quotes the font may lack

--- UTF-8 string to code points the font has; anything else becomes "?".
function B.codepoints(s)
	local out, i = {}, 1
	while i <= #s do
		local b = s:byte(i)
		local c, n
		if b < 0x80 then c, n = b, 1
		elseif b < 0xE0 then c, n = (b % 0x20) * 64 + ((s:byte(i + 1) or 0) % 64), 2
		elseif b < 0xF0 then c, n = (b % 0x10) * 4096 + ((s:byte(i + 1) or 0) % 64) * 64 + ((s:byte(i + 2) or 0) % 64), 3
		else c, n = 63, 4 end
		if c == 9 then c = 32 end
		-- A newline is kept for B.wrap, which starts a new line there.
		if c ~= 10 and not F.have[c] then c = TYPO[c] or 63 end
		if c ~= 10 and not F.have[c] then c = 63 end
		out[#out + 1] = c
		i = i + n
	end
	return out
end

--- Text to a list of { cp, ink }: **bold** words are highlighted (ink "y"), the rest is in ink.
function B.inked(text, ink)
	local out, bold = {}, false
	text = text:gsub("\r", ""):gsub("`", "")
	local pos = 1
	while pos <= #text do
		local s, e = text:find("**", pos, true)
		local chunk = text:sub(pos, (s or #text + 1) - 1)
		for _, c in ipairs(B.codepoints(chunk)) do out[#out + 1] = { c, bold and "y" or ink } end
		if not s then break end
		bold = not bold
		pos = e + 1
	end
	return out
end

--- Wraps inked characters into lines of at most cols cells; a newline starts a new line, an empty line stays empty. Returns a list of lines, each a list of { cp, ink }.
function B.wrap(chars, cols)
	local lines, line, word = {}, {}, {}
	local function flush_word()
		if #word == 0 then return end
		if #line > 0 and #line + 1 + #word > cols then
			lines[#lines + 1] = line
			line = {}
		end
		if #line > 0 then line[#line + 1] = { 32, "w" } end
		for _, ch in ipairs(word) do
			if #line >= cols then   -- a word longer than a line is cut
				lines[#lines + 1] = line
				line = {}
			end
			line[#line + 1] = ch
		end
		word = {}
	end
	for _, ch in ipairs(chars) do
		if ch[1] == 10 then
			flush_word()
			lines[#lines + 1] = line
			line = {}
		elseif ch[1] == 32 then
			flush_word()
		else
			word[#word + 1] = ch
		end
	end
	flush_word()
	if #line > 0 then lines[#lines + 1] = line end
	return lines
end

--- Lines of one paragraph of text in one ink (with **bold** highlighted).
function B.lines(text, ink, cols)
	return B.wrap(B.inked(text, ink), cols or B.COLS)
end

--- The rows of the screen for a state, at most B.ROWS. words: content.tutor.board.
-- state.mode is "idle" (state.fact: a line to show under the welcome), "thinking" (state.q) or "answer" (state.q, state.a, state.reveal: how many answer lines to show so far, nil for all).
-- Returns the rows and whether every line of the answer is shown.
function B.rows(state, words)
	local rows = {}
	local function add(lines) for _, l in ipairs(lines) do rows[#rows + 1] = l end end
	local blank = {}
	if state.mode == "idle" then
		add(B.lines(words.welcome, "w"))
		add(B.lines(words.how, "c"))
		if state.fact then
			rows[#rows + 1] = blank
			add(B.lines(words.fact_title, "y"))
			add(B.lines(state.fact, "w"))
		end
		while #rows > B.ROWS do rows[#rows] = nil end
		return rows, true
	end
	add(B.lines(words.asked, "g"))
	local q = B.lines(state.q or "", "c")
	for i = 1, math.min(#q, 3) do rows[#rows + 1] = q[i] end   -- a long question keeps three lines
	rows[#rows + 1] = blank
	add(B.lines(words.answer, "v"))
	if state.mode == "thinking" then
		add(B.lines(words.thinking, "g"))
		return rows, true
	end
	local a = B.lines(state.a or "", "w")
	local room = B.ROWS - #rows
	local shown = math.min(#a, state.reveal or #a)
	local complete = shown >= #a
	if #a > room then
		-- Too long for the screen: the last row says where to read the rest.
		shown = math.min(shown, room - 1)
		for i = 1, shown do rows[#rows + 1] = a[i] end
		if shown == room - 1 then add(B.lines(words.more, "g")) end
		return rows, complete
	end
	for i = 1, shown do rows[#rows + 1] = a[i] end
	return rows, complete
end

--- Number of answer lines the state's answer takes on the screen (for the typing effect).
function B.answer_lines(state)
	return #B.lines(state.a or "", "w")
end

local function draw(parts, line, x, y)
	for i, ch in ipairs(line) do
		if ch[1] ~= 32 then
			parts[#parts + 1] = (x + (i - 1) * F.w) .. "," .. y .. "=crystalminer_px_" .. ch[2] .. "_" .. ch[1] .. ".png"
		end
	end
end

--- Texture string for the screen: a header (left: title, right: hint) and the rows.
function B.texture(rows, words)
	local parts = { "[combine:" .. F.screen.w .. "x" .. F.screen.h .. ":0,0=crystalminer_billboard_screen.png" }
	local hy = math.floor((F.screen.header - F.h) / 2)
	local title = B.lines(words.title, "v", B.COLS)[1] or {}
	draw(parts, title, B.MARGIN, hy)
	local hint = B.lines(words.hint, "g", B.COLS - #title - 2)[1] or {}
	draw(parts, hint, F.screen.w - B.MARGIN - #hint * F.w, hy)
	for r, line in ipairs(rows) do draw(parts, line, B.MARGIN, B.BODY_TOP + (r - 1) * F.h) end
	return table.concat(parts, ":")
end

if not core then return B end

---------------------------------------------------------------------------- the screen in the game

local cm = crystalminer
local WORDS = cm.content.tutor.board
local GROUND = cm.GROUND_Y
local storage = cm.storage

B.AT = { wall = { x = 40, y = GROUND + 9, z = -50 }, dir = "n", dy = 0.5 }   -- the museum's south wall (lobby.lua: Z0 = -50) behind the desk; its bottom edge clears Prism, which floats up to GROUND + 5.9
B.TYPE_STEP = 0.3      -- seconds per line while an answer is typed out
B.HOLD = 300           -- seconds an answer stays up before the welcome and the words to know return
B.FACT_EVERY = 20      -- seconds per word to know

local boards = {}      -- live billboard entities
local state = { mode = "idle", fact_i = 0 }
local last_tex
local timer, since = 0, 0

-- The latest answer survives a restart of the server.
do
	local saved = storage:get_string("billboard")
	local d = saved ~= "" and core.deserialize(saved) or nil
	if d and d.q and d.a then state = { mode = "answer", q = d.q, a = d.a, fact_i = 0 } end
end

local function next_fact()
	local g = cm.content.glossary
	state.fact_i = state.fact_i % #g + 1
	state.fact = g[state.fact_i]
end
if state.mode == "idle" then next_fact() end

local function render()
	local rows = B.rows(state, WORDS)
	local tex = B.texture(rows, WORDS)
	if tex == last_tex then return end
	last_tex = tex
	for obj in pairs(boards) do
		if obj:get_pos() then obj:set_properties({ textures = { tex, "crystalminer_sign_back.png" } }) else boards[obj] = nil end
	end
end
cm.billboard_render = render

--- Someone asked Prism a question (tutor_window.lua): show it, with Prism thinking.
function cm.billboard_asked(question)
	state = { mode = "thinking", q = question, fact_i = state.fact_i }
	since = 0
	render()
end

--- Prism answered: type the answer out, line by line.
function cm.billboard_answered(question, answer)
	state = { mode = "answer", q = question, a = answer, reveal = 0, fact_i = state.fact_i }
	since = 0
	storage:set_string("billboard", core.serialize({ q = question, a = answer }))
	render()
end

--- The question got no answer: back to the welcome.
function cm.billboard_failed()
	state = { mode = "idle", fact_i = state.fact_i }
	next_fact()
	render()
end

cm.billboard_state = function() return state end

core.register_globalstep(function(dtime)
	timer, since = timer + dtime, since + dtime
	if state.mode == "answer" and state.reveal then
		if timer < B.TYPE_STEP then return end
		timer = 0
		state.reveal = state.reveal + 1
		if state.reveal >= B.answer_lines(state) then state.reveal, since = nil, 0 end
		render()
	elseif state.mode == "answer" and since > B.HOLD then
		state = { mode = "idle", fact_i = state.fact_i }
		next_fact()
		since, timer = 0, 0
		render()
	elseif state.mode == "idle" and timer > B.FACT_EVERY then
		timer = 0
		next_fact()
		render()
	end
end)

-- The selection box of an upright sprite does not turn with it, so it is set from the side the screen faces.
local function selection(dir)
	local w, h = B.SIZE.w / 2, B.SIZE.h / 2
	if dir == "e" or dir == "w" then return { -0.05, -h, -w, 0.05, h, w } end
	return { -w, -h, -0.05, w, h, 0.05 }
end

local function open_from(clicker)
	if clicker and clicker:is_player() then cm.open_tutor(clicker:get_player_name()) end
end

core.register_entity("crystalminer:billboard", {
	initial_properties = {
		visual = "upright_sprite", textures = { "crystalminer_billboard_screen.png", "crystalminer_sign_back.png" },
		visual_size = { x = B.SIZE.w, y = B.SIZE.h }, physical = false, pointable = true, static_save = true,
		glow = 12, infotext = "Prism's screen: right-click to chat",
	},
	on_activate = function(self, staticdata)
		local d = staticdata ~= "" and core.deserialize(staticdata) or nil
		-- One from an earlier build of the world removes itself (as signs do, signs.lua).
		if not d or d.v ~= cm.WORLD_VERSION then
			self.object:remove()
			return
		end
		self.data = d
		-- Turned from its own data each time it wakes up: one put back after the map lost it was found facing north, edge-on to the room and so invisible.
		self.object:set_yaw(cm.SG.YAW[d.dir] or 0)
		self.object:set_armor_groups({ immortal = 1 })
		self.object:set_properties({ selectionbox = selection(d.dir) })
		boards[self.object] = true
		last_tex = nil
		render()
	end,
	get_staticdata = function(self) return core.serialize(self.data) end,
	on_rightclick = function(_, clicker) open_from(clicker) end,
	on_punch = function(_, puncher)
		open_from(puncher)
		return true
	end,
})

--- Puts the billboard on its wall, replacing one already there.
function B.place()
	local d = cm.SG.DIR[B.AT.dir]
	local pos = { x = B.AT.wall.x + d.x * 0.52, y = B.AT.wall.y + (B.AT.dy or 0), z = B.AT.wall.z + d.z * 0.52 }
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
		local e = obj:get_luaentity()
		if e and e.name == "crystalminer:billboard" then obj:remove() end
	end
	local obj = core.add_entity(pos, "crystalminer:billboard", core.serialize({ v = cm.WORLD_VERSION, dir = B.AT.dir }))
	if obj then obj:set_yaw(cm.SG.YAW[B.AT.dir]) end
	return obj
end

-- The wall block behind the screen is a mount that looks like the pillar it replaces (lobby.lua puts a pillar every 10 nodes along the outer wall). An entity is saved with the map only when its part of the map is saved, so a server that stops abruptly after a build can lose it; whenever the mount is loaded, a missing billboard is put back.
core.register_node("crystalminer:billboard_mount", {
	description = "Billboard mount", tiles = { "crystalminer_pillar.png" }, groups = { not_in_creative_inventory = 1 },
	is_ground_content = false, sounds = cm.node_sounds("hard"),
})

local function present()
	local d = cm.SG.DIR[B.AT.dir]
	local pos = { x = B.AT.wall.x + d.x * 0.52, y = B.AT.wall.y + (B.AT.dy or 0), z = B.AT.wall.z + d.z * 0.52 }
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
		local e = obj:get_luaentity()
		if e and e.name == "crystalminer:billboard" then return true end
	end
	return false
end
B.present = present

core.register_lbm({
	label = "Put Prism's billboard back if it is missing",
	name = "crystalminer:billboard_check",
	nodenames = { "crystalminer:billboard_mount" },
	run_at_every_load = true,
	-- The block's own objects are woken in the same step; look a moment later.
	action = function() core.after(1, function() if not present() then B.place() end end) end,
})

table.insert(cm.on_build, function()
	core.set_node(B.AT.wall, { name = "crystalminer:billboard_mount" })
	B.place()
end)

cm.BILLBOARD = B
return B
