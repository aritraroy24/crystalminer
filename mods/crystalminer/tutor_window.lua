-- Prism, the AI tutor: a chat window, the conversation each player has with Prism, and the desk in Visitor information where Prism lives (a floating crystal above a screen; right-click either). /ask opens the window from anywhere. The model is reached through tutor.lua, with the settings read in init.lua (cm.tutor); every word of the window is in content.lua (content.tutor).

local cm = crystalminer
local TC = cm.content.tutor
local tutor = cm.tutor   -- { T, http, cfg, on, limits, now }
local T = tutor.T
local GROUND = cm.GROUND_Y

local FORM = "crystalminer:tutor"
local MAX_KEPT = 40      -- messages kept per player; the model sees the last T.CHAT_HISTORY of them
local chats = {}         -- name -> { msgs = { { role, text } }, waiting, notice, suggested }
cm.tutor_chats = chats

local function chat(name)
	chats[name] = chats[name] or { msgs = {} }
	return chats[name]
end

local function push(c, role, text)
	c.msgs[#c.msgs + 1] = { role = role, text = text }
	while #c.msgs > MAX_KEPT do table.remove(c.msgs, 1) end
end

--- Where the player is, in words for the model: a world, the museum, or nil.
local function place_of(name)
	local player = core.get_player_by_name(name)
	if not player then return nil, nil end
	local pos = player:get_pos()
	local live = cm.region_near(pos)
	if live then return live.area.name, live end
	local L = cm.lobby
	if L and pos.x >= L.X0 and pos.x <= L.X1 and pos.z >= L.Z0 and pos.z <= L.Z1 then
		return "the Museum of Crystals and Symmetry", nil
	end
	return nil, nil
end

local function service()
	local cfg = tutor.cfg
	if not cfg then return nil end
	if cfg.provider == "anthropic" then return "Claude (" .. cfg.model .. ")" end
	return (cfg.service or "an open model") .. " (" .. cfg.model .. ")"
end

---------------------------------------------------------------------------- the window

local function esc(t)
	-- hypertext markup: escape the formspec, then the markup characters.
	return core.formspec_escape((t:gsub("\\", "\\\\"):gsub("<", "\\<")))
end

--- Hypertext for one message: the model's **bold** is kept; headings, code marks and other markdown it may still write are dropped, and "* " bullets become dots.
local function rich(text)
	text = ("\n" .. text:gsub("\r", "")):gsub("\n[ \t]*#+[ \t]*", "\n"):gsub("\n[ \t]*[%*%-][ \t]+", "\n• ")
		:gsub("`", ""):sub(2)
	return (esc(text):gsub("%*%*(.-)%*%*", "<b>%1</b>"))
end

-- Text in a bubble is 15 px. In a 1280 x 800 window a formspec unit is about 54 px, which fits 7.5 characters of it and a line is 0.33 units; the margins here leave room for a larger GUI scale, so a bubble is rather a little too tall than cut off.
local CHARS_PER_UNIT, LINE, PAD = 6.4, 0.37, 0.18
local VIEW_X, VIEW_Y, VIEW_W, VIEW_H = 5.3, 0.4, 11.9, 7.7
local BUBBLE_W, ICON = 9.4, 0.75
local COLOURS = { user = "#1F3A5A", assistant = "#2B2346", error = "#4A2228", note = "#2B2346" }

--- Width (units) and number of lines of text in a bubble at most BUBBLE_W wide.
local function measure(text)
	local per = math.floor((BUBBLE_W - 2 * PAD) * CHARS_PER_UNIT)
	local lines, longest = 0, 0
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local n = T.char_count(para)
		longest = math.max(longest, n)
		lines = lines + math.max(1, math.ceil(n / per))
	end
	local w = math.min(BUBBLE_W, math.max(2.6, longest / CHARS_PER_UNIT + 2 * PAD + 0.3))
	return w, lines
end

--- Formspec elements for one bubble at height y inside the chat view; returns them and the next y.
local function bubble(i, role, text, y, italic)
	local header = role ~= "user"
	local w, lines = measure(text)
	if header then w = math.max(w, 3) end
	-- The name above an answer is followed by a paragraph gap, so it takes more than a line.
	local h = lines * LINE + 2 * PAD + (header and 0.5 or 0)
	local x = role == "user" and (VIEW_W - 0.1 - ICON - 0.15 - w) or (0.1 + ICON + 0.15)
	local icon_x = role == "user" and (VIEW_W - 0.1 - ICON) or 0.1
	local icon = role == "user" and "crystalminer_tutor_user.png" or "crystalminer_tutor_icon.png"
	local body = "<global size=15 color=#F0F0F0 valign=top>"
	if header then
		local who = role == "error" and "<style color=#FF9C9C><b>" .. esc(TC.name) .. "</b></style>"
			or "<style color=#D080FF><b>" .. esc(TC.name) .. "</b></style>"
		body = body .. who .. "\n"
	end
	body = body .. (italic and "<i><style color=#B8B0D0>" .. esc(text) .. "</style></i>" or rich(text))
	-- The text area reaches a little below its bubble: it is transparent, and a hypertext element that is even slightly too short for its text shows a scrollbar of its own.
	local out = {
		"image[" .. icon_x .. "," .. y .. ";" .. ICON .. "," .. ICON .. ";" .. icon .. "]",
		"box[" .. x .. "," .. y .. ";" .. w .. "," .. h .. ";" .. COLOURS[role] .. "]",
		"hypertext[" .. (x + PAD) .. "," .. (y + PAD * 0.7) .. ";" .. (w - 2 * PAD) .. "," .. (h + 0.45) .. ";m" .. i
			.. ";" .. body .. "]",
	}
	return out, y + h + 0.25
end

--- The suggested questions for a player: by tier, the first about the world they are in.
local function suggestions(name)
	local tier = math.max(0, math.min(4, cm.progress(name).tier))
	local list = {}
	for i, s in ipairs(TC.suggestions[tier] or TC.suggestions[0]) do list[i] = s end
	local _, live = place_of(name)
	if live then list[1] = TC.here end
	return list
end

function cm.tutor_formspec(name)
	local c = chat(name)
	local place = place_of(name)
	local p = cm.progress(name)
	-- The conversation: a welcome, the messages, then what is happening now.
	local items = { { role = "assistant", text = string.format(TC.welcome, name) } }
	if not tutor.on then items[#items + 1] = { role = "error", text = TC.off } end
	for _, m in ipairs(c.msgs) do items[#items + 1] = m end
	if c.waiting then items[#items + 1] = { role = "note", text = TC.thinking, italic = true } end
	if c.notice then items[#items + 1] = { role = "error", text = c.notice } end
	local view, y = {}, 0.15
	for i, m in ipairs(items) do
		local els
		els, y = bubble(i, m.role, m.text, y, m.italic)
		for _, e in ipairs(els) do view[#view + 1] = e end
	end
	-- Scrolled to the newest message: 10 scrollbar steps per unit (the container's factor is 0.1).
	local max = math.max(0, math.ceil((y - VIEW_H) * 10))
	c.suggested = suggestions(name)

	local info = "<global size=14 color=#D8D8E8>"
		.. "<center><style size=26 color=#D080FF><b>" .. esc(TC.name) .. "</b></style>\n"
		.. "<style color=#A89CC8>" .. esc(TC.role) .. "</style></center>\n"
		.. esc(TC.about) .. "\n\n"
		.. "<style color=#9FD8FF><b>Your tier:</b></style> " .. p.tier .. "\n"
		.. "<style color=#9FD8FF><b>You are in:</b></style> " .. esc(place or "the open world")
	local note = "<global size=12 color=#8A8FA3>" .. esc(TC.disclaimer)
		.. (service() and (" Powered by " .. esc(service()) .. ".") or "")
	local fs = {
		"formspec_version[4]size[18,11]",
		"bgcolor[#141A26F5;both;#00000050]",
		"style_type[button;bgcolor=#4A3A7A;textcolor=#F4F0FF]",
		"style[send;bgcolor=#7A52D0;textcolor=#FFFFFF]",
		"style[close;bgcolor=#3A3F52]",
		-- Prism
		"box[0.3,0.3;4.6,10.4;#1E2433FF]",
		"image[0.85,0.45;3.5,3.5;crystalminer_tutor_avatar.png]",
		"hypertext[0.5,4.0;4.2,4.9;about;" .. info .. "]",
		"button[0.55,9.0;4.1,0.75;new;New chat]",
		"button_exit[0.55,9.9;4.1,0.75;close;Close]",
		-- The conversation
		"box[5.2,0.3;12.5,7.9;#0D1220FF]",
		"scroll_container[" .. VIEW_X .. "," .. VIEW_Y .. ";" .. VIEW_W .. "," .. VIEW_H .. ";chat_scroll;vertical;0.1]",
		table.concat(view),
		"scroll_container_end[]",
		"scrollbaroptions[min=0;max=" .. max .. ";smallstep=6;largestep=" .. math.floor(VIEW_H * 10)
			.. ";thumbsize=" .. math.floor(VIEW_H * 10) .. "]",
		"scrollbar[17.3,0.4;0.3,7.7;vertical;chat_scroll;" .. max .. "]",
	}
	-- Suggested questions, then the question box (on a box of its own: a field without a border draws no background), then where the answers come from.
	for i, s in ipairs(c.suggested) do
		fs[#fs + 1] = "button[" .. (5.2 + (i - 1) * 4.2) .. ",8.35;4.1,0.7;q" .. i .. ";" .. core.formspec_escape(s) .. "]"
	end
	fs[#fs + 1] = "box[5.2,9.25;10.1,0.85;#0D1220FF]"
	fs[#fs + 1] = "style[msg;border=false;textcolor=#F4F0FF]"
	fs[#fs + 1] = "field[5.35,9.25;9.9,0.85;msg;;]"
	fs[#fs + 1] = "field_close_on_enter[msg;false]"
	fs[#fs + 1] = "set_focus[msg;true]"
	fs[#fs + 1] = "button[15.45,9.25;2.25,0.85;send;Send]"
	fs[#fs + 1] = "hypertext[5.2,10.2;12.5,0.75;note;" .. note .. "]"
	return table.concat(fs)
end

local function show(name)
	if core.get_player_by_name(name) then core.show_formspec(name, FORM, cm.tutor_formspec(name)) end
end

---------------------------------------------------------------------------- asking

--- Sends a question from the window. Replies arrive later and redraw the window if it is still open.
function cm.tutor_ask(name, text)
	local c = chat(name)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return show(name) end
	c.notice = nil
	if not tutor.on then
		c.notice = TC.off
		return show(name)
	end
	local too_long = T.check_length(text)
	if too_long then
		c.notice = too_long
		return show(name)
	end
	local ok, busy = T.try_start(tutor.limits, name, tutor.now())
	if not ok then
		c.notice = busy
		return show(name)
	end
	local history = {}
	for i, m in ipairs(c.msgs) do history[i] = m end
	push(c, "user", text)
	c.waiting = true
	show(name)
	if cm.billboard_asked then cm.billboard_asked(text) end
	local place = place_of(name)
	T.send(tutor.http, tutor.cfg, T.chat_request(tutor.cfg, history, text, cm.progress(name).tier, place),
		core.write_json, core.parse_json, function(answer, err)
			T.finish(tutor.limits, name)
			c.waiting = false
			if answer then push(c, "assistant", T.strip_label(answer)) else push(c, "error", err) end
			-- The billboard in Visitor information shows it too (billboard.lua).
			if answer and cm.billboard_answered then cm.billboard_answered(text, T.strip_label(answer))
			elseif not answer and cm.billboard_failed then cm.billboard_failed() end
			if not core.get_player_by_name(name) then return end
			if cm.window_open(name) == FORM then
				show(name)
			else
				cm.say(name, core.colorize("#D080FF", TC.name .. ": ")
					.. (answer and "I've answered your question. Type /ask to read it." or err))
			end
		end)
end

--- Opens the chat window; with a question, asks it straight away.
function cm.open_tutor(name, question)
	if question and question ~= "" then return cm.tutor_ask(name, question) end
	show(name)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then return false end
	local name = player:get_player_name()
	local c = chat(name)
	if fields.new then
		if not c.waiting then c.msgs, c.notice = {}, nil end
		show(name)
		return true
	end
	for i = 1, 3 do
		if fields["q" .. i] and c.suggested and c.suggested[i] then
			cm.tutor_ask(name, c.suggested[i])
			return true
		end
	end
	if fields.send or fields.key_enter_field == "msg" then cm.tutor_ask(name, fields.msg) end
	return true
end)

core.register_on_leaveplayer(function(player) chats[player:get_player_name()] = nil end)

---------------------------------------------------------------------------- the desk

local function open_from(_, _, who)
	if who and who:is_player() then cm.open_tutor(who:get_player_name()) end
end

-- A stepped octahedron, like Haüy's in Gallery 2, drawn 1.8 times the size of a node. The middle band shows rows 9 to 23 of the face texture (tools/make_tutor_art.py), where the face is.
core.register_node("crystalminer:tutor_prism", {
	description = "Prism, the crystal tutor",
	drawtype = "nodebox", visual_scale = 1.8, paramtype = "light", paramtype2 = "facedir", light_source = 11,
	tiles = { "crystalminer_tutor_prism.png", "crystalminer_tutor_prism.png", "crystalminer_tutor_prism.png",
		"crystalminer_tutor_prism.png", "crystalminer_tutor_prism_face.png", "crystalminer_tutor_prism.png" },
	node_box = { type = "fixed", fixed = {
		{ -0.14, -0.5, -0.14, 0.14, -0.36, 0.14 }, { -0.32, -0.36, -0.32, 0.32, -0.22, 0.32 },
		{ -0.5, -0.22, -0.5, 0.5, 0.22, 0.5 },
		{ -0.32, 0.22, -0.32, 0.32, 0.36, 0.32 }, { -0.14, 0.36, -0.14, 0.14, 0.5, 0.14 },
	} },
	selection_box = { type = "fixed", fixed = { -0.9, -0.9, -0.9, 0.9, 0.9, 0.9 } },
	walkable = false, sunlight_propagates = true, is_ground_content = false,
	groups = { not_in_creative_inventory = 1 }, sounds = cm.node_sounds("hard"),
	on_rightclick = open_from, on_punch = open_from,
})

core.register_node("crystalminer:tutor_screen", {
	description = "Prism's screen",
	drawtype = "nodebox", paramtype = "light", paramtype2 = "facedir", light_source = 5,
	tiles = { "crystalminer_tutor_case.png", "crystalminer_tutor_case.png", "crystalminer_tutor_case.png",
		"crystalminer_tutor_case.png", "crystalminer_tutor_screen.png", "crystalminer_tutor_case.png" },
	node_box = { type = "fixed", fixed = {
		{ -0.3, -0.5, -0.2, 0.3, -0.44, 0.2 },          -- foot
		{ -0.06, -0.44, -0.04, 0.06, -0.3, 0.04 },      -- neck
		{ -0.45, -0.3, -0.06, 0.45, 0.45, 0.04 },       -- the screen, facing north
	} },
	sunlight_propagates = true, is_ground_content = false,
	groups = { not_in_creative_inventory = 1 }, sounds = cm.node_sounds("hard"),
	on_rightclick = open_from, on_punch = open_from,
})

-- On the information desk (furniture.lua: x 36 to 44, z = -45): the screen in the middle, facing visitors who come in from the foyer, and Prism floating behind it.
local DESK = { x = 40, z = -45 }
cm.TUTOR_DESK = DESK

local function place_desk()
	local screen = { x = DESK.x, y = GROUND + 3, z = DESK.z }
	local prism = { x = DESK.x, y = GROUND + 5, z = DESK.z - 2 }
	core.set_node(screen, { name = "crystalminer:tutor_screen" })
	core.set_node(prism, { name = "crystalminer:tutor_prism" })
	for _, pos in ipairs({ screen, prism }) do
		core.get_meta(pos):set_string("infotext", TC.name .. ", the AI tutor\nRight-click to chat")
	end
end
cm.place_tutor_desk = place_desk

-- Loaded after furniture.lua, so this runs after the on_build that makes the desk (and its banner, content.tutor.desk).
table.insert(cm.on_build, function() place_desk() end)

-- A few sparkles around Prism while someone is nearby.
local SPARK = { x = DESK.x, y = GROUND + 5, z = DESK.z - 2 }
local spark_timer = 0
core.register_globalstep(function(dtime)
	spark_timer = spark_timer + dtime
	if spark_timer < 2 then return end
	spark_timer = 0
	for _, obj in ipairs(core.get_objects_inside_radius(SPARK, 20)) do
		if obj:is_player() then
			core.add_particlespawner({
				amount = 5, time = 2, playername = obj:get_player_name(),
				minpos = vector.subtract(SPARK, 1.1), maxpos = vector.add(SPARK, 1.1),
				minvel = { x = 0, y = 0.15, z = 0 }, maxvel = { x = 0, y = 0.4, z = 0 },
				minexptime = 1.2, maxexptime = 2, minsize = 0.8, maxsize = 1.6, glow = 14,
				texture = "crystalminer_dot.png^[colorize:#E0C8FF:255",
			})
		end
	end
end)
