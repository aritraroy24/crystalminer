package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local content = require("content")
local B = loadfile("mods/crystalminer/billboard.lua")()
local T = require("testlib")
local WORDS = content.tutor.board

-- The longest texture an entity can carry (object properties are sent with serializeString16); keep a margin, as test_signs.lua does.
local MAX_TEXTURE = 60000

print("billboard")

local function text_of(line)
	local s = {}
	for _, ch in ipairs(line) do s[#s + 1] = string.char(ch[1] < 128 and ch[1] or 63) end
	return table.concat(s)
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() end
	return f ~= nil
end

T.run("the screen has room for a full answer", function()
	T.ok(B.COLS >= 60, tostring(B.COLS)); T.ok(B.ROWS >= 15, tostring(B.ROWS))
	T.eq(B.FONT.screen.w / 128, B.SIZE.w); T.eq(B.FONT.screen.h / 128, B.SIZE.h)
end)

T.run("lines never pass the edge, and words are not split when they fit", function()
	local lines = B.lines(string.rep("crystallography symmetry ", 20), "w")
	for _, l in ipairs(lines) do T.ok(#l <= B.COLS, tostring(#l)) end
	for _, l in ipairs(lines) do T.ok(text_of(l):match("^%a") and text_of(l):match("%a$"), text_of(l)) end
	local long = B.lines(string.rep("x", B.COLS * 2 + 5), "w")
	T.eq(#long, 3); T.eq(#long[1], B.COLS)
end)

T.run("bold words are highlighted, unknown characters become ?", function()
	local chars = B.inked("A **mirror** here", "w")
	T.eq(chars[1][2], "w"); T.eq(chars[3][2], "y"); T.eq(chars[3][1], string.byte("m")); T.eq(chars[#chars][2], "w")
	T.eq(#chars, #"A mirror here")
	local cps = B.codepoints("4₁ ’x’ 好")
	T.eq(cps[2], 8321)            -- the subscript is in the font
	T.ok(cps[4] == 8217 or cps[4] == 39, tostring(cps[4]))   -- a curly quote stays, or becomes straight if the font lacks it
	T.eq(cps[#cps], 63)
end)

T.run("every glyph the screen can draw exists, in every ink", function()
	for code in pairs(B.FONT.have) do
		if code ~= 32 then
			for _, ink in ipairs(B.FONT.inks) do
				T.ok(exists("mods/crystalminer/textures/crystalminer_px_" .. ink .. "_" .. code .. ".png"), ink .. " " .. code)
			end
		end
	end
	T.ok(exists("mods/crystalminer/textures/crystalminer_billboard_screen.png"))
end)

T.run("idle: the welcome, how to ask, and a word to know", function()
	local rows = B.rows({ mode = "idle", fact = content.glossary[1] }, WORDS)
	T.ok(#rows <= B.ROWS)
	local all = {}
	for _, r in ipairs(rows) do all[#all + 1] = text_of(r) end
	all = table.concat(all, " ")
	T.ok(all:find("Prism", 1, true) and all:find("/ask", 1, true) and all:find("WORDS TO KNOW", 1, true), all)
end)

T.run("an answer is typed out line by line, then complete", function()
	local st = { mode = "answer", q = "What is a mirror?", a = "A **mirror** plane reflects. " .. string.rep("More words here. ", 12), reveal = 0 }
	local rows0, done0 = B.rows(st, WORDS)
	st.reveal = 2
	local rows2 = B.rows(st, WORDS)
	T.eq(#rows2, #rows0 + 2); T.ok(not done0)
	st.reveal = nil
	local _, done = B.rows(st, WORDS)
	T.ok(done)
	T.eq(text_of(rows0[1]), WORDS.asked)
end)

T.run("a very long answer ends with where to read the rest, and fits the texture limit", function()
	local long = string.rep("Symmetry operations map a crystal onto itself, with **many** words. ", 40)
	local q = string.rep("Why? ", 60)
	local rows = B.rows({ mode = "answer", q = q, a = long }, WORDS)
	T.eq(#rows, B.ROWS)
	T.ok(text_of(rows[#rows]):find("the rest", 1, true), text_of(rows[#rows]))
	local tex = B.texture(rows, WORDS)
	T.ok(#tex < MAX_TEXTURE, tostring(#tex))
	T.ok(tex:match("^%[combine:1536x896:0,0=crystalminer_billboard_screen%.png:"))
end)

T.run("a blank line between paragraphs stays a blank line", function()
	local lines = B.lines("First paragraph.\n\nSecond one.", "w")
	T.eq(#lines, 3); T.eq(text_of(lines[1]), "First paragraph."); T.eq(#lines[2], 0); T.eq(text_of(lines[3]), "Second one.")
end)

T.run("thinking: the question and Prism thinking", function()
	local rows = B.rows({ mode = "thinking", q = "What is a glide plane?" }, WORDS)
	T.eq(text_of(rows[2]), "What is a glide plane?")
	T.eq(text_of(rows[#rows]), WORDS.thinking)
end)

T.finish()
