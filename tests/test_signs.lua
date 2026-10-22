-- Every sign in the game: its text fits its sign, every character has a glyph, and the texture
-- string stays well below Luanti's limit.
package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local L = require("lessons")
local content = require("content")
local SG = require("signs")
local GD = require("guides")
local T = require("testlib")

print("signs")

local LB, W = content.lobby, content.worlds

-- Luanti clears an entity texture longer than 65535 bytes (ObjectProperties::validate, which
-- serialises textures with serializeString16). Keep a margin.
local MAX_TEXTURE = 60000

--- Every sign the game builds, as { format, text, where, opts }, mirroring lobby.lua, worlds.lua,
-- museum.lua and furniture.lua.
local function all_signs()
	local out = {}
	local function add(format, text, where, opts) out[#out + 1] = { format, text, where, opts } end
	-- Banners over the doorways (lobby.lua) and the information desk (furniture.lua).
	for _, b in ipairs({
		"# MUSEUM OF CRYSTALS AND SYMMETRY\nWelcome. The doors open with a click.",
		"# GALLERY 1\nFour kinds of symmetry", "# WORKSHOP\nThe Try-it Pad", "# VISITOR INFORMATION\nHow to explore · Ask Prism, the AI tutor",
		"# GALLERY 2\nA history of crystallography", "# GALLERY 3\nCrystals at the atomic scale",
		"# FOYER\nWay out, welcome and map", "# PORTAL HALL\nTo the symmetry worlds",
		content.tutor.desk,
	}) do add("banner", b, "banner " .. b:match("^# ([^\n]*)")) end
	for _, k in ipairs({ "welcome", "information", "workshop", "gallery1", "gallery2", "gallery3", "portals" }) do
		add("board", LB[k], k)
	end
	add("board", GD.board_text(GD.tryit_pad), "Try-it Pad board")
	add("board", GD.board_text(GD.symmetry_gate), "Gallery 1 board")
	add("board", GD.howto, "how to")
	local words = { "# Words to know" }
	for i = 1, 9 do words[#words + 1] = content.glossary[i] end
	add("board", table.concat(words, "\n"), "words to know")
	for _, l in ipairs({ "A", "B", "C", "D" }) do add("plaque", string.format(LB.display, l), "display " .. l) end
	for _, h in ipairs(LB.history) do add("panel", "# " .. h.year .. "  " .. h.who .. "\n" .. h.text, "history " .. h.year) end
	add("plaque", "# Haüy's idea, in blocks\nIdentical cubes, stacked, make an octahedron with stepped faces. From far away the steps vanish and the faces look flat.", "Haüy")
	for _, ex in ipairs(content.museum.exhibits) do add("panel", "# " .. ex.name .. "\n" .. table.concat(ex.facts, " "), ex.id) end
	for _, a in ipairs(content.regions) do
		local idea = ((a.explain or {})[a.tier] or {})[1] or ""
		add("plaque", "# " .. a.name .. "\n## Symmetry " .. a.symbol .. " · tier " .. a.tier .. "\n" .. idea, "portal " .. a.id,
			{ tier = a.tier })
		-- The world's main board (worlds.lua info_text): the guide if there is one, else the explanation.
		local board
		if GD[a.id] then
			board = GD.board_text(GD[a.id])
			if a.tier > 0 then board = board .. "\n\n" .. string.format(W.locked, a.tier) end
		else
			local lines = { "# " .. a.name, "## Symmetry " .. a.symbol .. " · tier " .. a.tier, "" }
			for _, l in ipairs(L.explanation(a, a.tier)) do lines[#lines + 1] = l end
			lines[#lines + 1] = ""
			lines[#lines + 1] = string.format(W.locked, a.tier)
			board = table.concat(lines, "\n")
		end
		add("board", board, "board " .. a.id)
		add("banner", "# " .. a.name:upper() .. "\nSymmetry " .. a.symbol .. " · tier " .. a.tier, "arch " .. a.id)
	end
	for _, sc in ipairs(require("sculptures").list) do add("plaque", sc.plaque, "sculpture " .. sc.id) end
	add("plaque", "# YOUR SHAPE\nBuild your shape in this box.", "pad build")
	add("plaque", "# COPY\nThe lever's copy appears here.", "pad copy")
	for _, w in ipairs({ "T\nslide", "R\nturn half a turn", "M\nmirror", "I\nthrough the centre" }) do
		add("label", "# " .. w, "lever " .. w:sub(1, 1))
	end
	add("plaque", "# To the museum\nPunch the portal to go back to the Portal Hall.", "portal back")
	return out
end

-- Largest size of each format before the redesign: no sign may grow (they hang between pillars,
-- under lintels and just above the floor).
local LIMIT = { plaque = { 384, 192 }, panel = { 576, 384 }, board = { 768, 576 }, banner = { 768, 192 }, label = { 192, 96 } }

T.run("every sign's text fits its sign, which is no larger than before", function()
	for _, s in ipairs(all_signs()) do
		local _, fits, w, h = SG.texture(s[1], s[2], s[4])
		T.ok(fits, s[3] .. " does not fit a " .. s[1])
		T.ok(w <= LIMIT[s[1]][1] and h <= LIMIT[s[1]][2], s[3] .. " is larger than a " .. s[1] .. " used to be")
		T.eq(h % SG.STEP, 0, s[3] .. ": height on the grid")
	end
end)

T.run("every texture string is far below Luanti's 65535-byte limit", function()
	for _, s in ipairs(all_signs()) do
		local tex = SG.texture(s[1], s[2], s[4])
		T.ok(#tex < MAX_TEXTURE, s[3] .. ": texture string of " .. #tex .. " bytes")
	end
end)

T.run("every character on every sign has a glyph and metrics in every set", function()
	for _, s in ipairs(all_signs()) do
		local text = s[2]:gsub("%?", ""):gsub("\n", " ")
		for _, c in ipairs(SG.codepoints(text)) do
			T.ok(c ~= 63, s[3] .. ": a character has no glyph in: " .. s[2]:sub(1, 60))
		end
	end
	for name, set in pairs(SG.METRICS) do
		for c in pairs(SG.METRICS.r20.adv) do
			T.ok(set.adv[c] ~= nil, name .. " has no advance for " .. c)
		end
		for _, c in ipairs({ 8216, 8217, 8722 }) do T.ok(set.adv[c] ~= nil, name .. " lacks " .. c) end
	end
end)

T.run("every image a sign texture names exists", function()
	local seen = {}   -- each file once: opening files on a shared folder is slow
	for _, s in ipairs(all_signs()) do
		local tex = SG.texture(s[1], s[2], s[4])
		for name in tex:gmatch("([%w_]+%.png)") do
			if not seen[name] then
				seen[name] = true
				local f = io.open("mods/crystalminer/textures/" .. name, "rb")
				T.ok(f ~= nil, "missing texture " .. name)
				if f then f:close() end
			end
		end
	end
end)

T.run("wrapping keeps words whole and within the width", function()
	local lines = SG.wrap("r20", "alpha beta gamma delta epsilon", 120)
	T.ok(#lines >= 2, "wraps")
	local words = {}
	for _, l in ipairs(lines) do
		T.ok(l.w <= 120, "line within width")
		words[#words + 1] = string.char(unpack(l.cps))
	end
	T.eq(table.concat(words, " "), "alpha beta gamma delta epsilon", "words kept whole")
	T.eq(SG.measure("r20", SG.codepoints("ii")) < SG.measure("r20", SG.codepoints("MM")), true, "proportional widths")
end)

T.run("title, meta lines and typography", function()
	local title, meta, paras = SG.parse("# Kaleidoscope\n## Symmetry m-3m · tier 3\nThe full symmetry.\n\nMore.")
	T.eq(title, "Kaleidoscope", "title")
	T.eq(#meta, 1, "one meta line")
	T.eq(#paras, 3, "two paragraphs and a break")
	local tex = SG.texture("plaque", "# Kaleidoscope\n## Symmetry m-3m · tier 3\nIt's -4, not '4'.", { tier = 3 })
	T.ok(tex:find("crystalminer_b26_75.png", 1, true), "bold title K")
	T.ok(tex:find("crystalminer_b17_8722.png", 1, true), "minus in m-3m on the meta line")
	T.ok(tex:find("crystalminer_r18_8722.png", 1, true), "minus in -4")
	T.ok(tex:find("crystalminer_r18_8217.png", 1, true) and tex:find("crystalminer_r18_8216.png", 1, true), "curly quotes")
	T.ok(tex:find("crystalminer_sign_bar_3.png", 1, true), "tier-coloured bar")
	local short = select(4, SG.texture("board", "# Hi\nShort."))
	T.eq(short, SG.FORMATS.board.minh, "a short board is sized to its text")
	local tex2 = SG.texture("label", "# T\nslide")
	T.ok(tex2:find("crystalminer_b34_84.png", 1, true), "big T on a label")
end)

T.finish()
