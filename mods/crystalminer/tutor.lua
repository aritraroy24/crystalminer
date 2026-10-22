-- The in-game tutor, over raw HTTP: the Claude API (default) or any OpenAI-compatible server, such
-- as Ollama running a free open-source model locally (see "Providers" below).
--
-- The model only explains and translates. /ask answers from the reviewed text in content.lua;
-- /symmetry only picks a point-group symbol, which the symmetry engine then checks.
--
-- Loaded with loadfile(...)(symmetry, content).

local S, content = ...

local T = {}

-- Verified against https://platform.claude.com/docs/en/models/overview (October 2026).
T.MODEL = "claude-opus-5-5"
T.URL = "https://api.anthropic.com/v1/messages"
-- Hard cap on output per request (thinking plus reply). Opus 5.5 always thinks a little, even at
-- low effort; 4096 leaves ample room for an 80-word answer while bounding the cost of one request.
T.MAX_TOKENS = 4096

-- Cost and abuse limits.
T.COOLDOWN = 20        -- seconds between requests from one player
T.MAX_IN_FLIGHT = 3    -- requests waiting for the API at once, across the whole server
T.MAX_CHARS = 300      -- longest question or description a player may send

--- Number of characters (UTF-8 code points) in s.
function T.char_count(s)
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

--- nil if the text may be sent, otherwise a message for the player.
function T.check_length(text)
	if T.char_count(text) > T.MAX_CHARS then
		return "That is too long for the tutor. Please keep it under " .. T.MAX_CHARS .. " characters."
	end
	return nil
end

function T.new_limiter()
	return { last = {}, busy = {}, in_flight = 0 }
end

--- Reserves a request slot for a player. now is in seconds.
-- Returns true, or false and a friendly message.
function T.try_start(lim, name, now)
	if lim.busy[name] then
		return false, "The tutor is still thinking about your last question."
	end
	local last = lim.last[name]
	if last and now - last < T.COOLDOWN then
		local wait = math.ceil(T.COOLDOWN - (now - last))
		return false, "Give the tutor a moment: you can ask again in " .. wait .. " s."
	end
	if lim.in_flight >= T.MAX_IN_FLIGHT then
		return false, "The tutor is helping other players right now. Try again in a few seconds."
	end
	lim.busy[name] = true
	lim.last[name] = now
	lim.in_flight = lim.in_flight + 1
	return true
end

--- Releases the slot taken by try_start once the reply (or error) has arrived.
function T.finish(lim, name)
	if lim.busy[name] then
		lim.busy[name] = nil
		lim.in_flight = lim.in_flight - 1
	end
end

function T.tutor_system_prompt()
	local lines = {
		"You are the tutor inside crystalminer, a Luanti world where students learn symmetry, the "
			.. "foundation of crystallography. Each region of the world has a symmetry group: whatever a "
			.. "student builds there is copied by every operation of the group.",
		"",
		"How to answer:",
		"- Use only the reference below. If it does not cover the question, say you are not sure and "
			.. "suggest asking their teacher. Never guess or invent facts.",
		"- Reply in plain text for game chat: no markdown, no bullet symbols, at most 80 words.",
		"- Pitch the answer at the student's tier. Ideas from a higher tier than theirs can be mentioned "
			.. "as something they will meet later, without explaining them in full.",
		"- Do not give away quiz answers or the hidden symmetry of the Mystery Lab. Give a hint about what "
			.. "to build or look for instead.",
		"- If the question is not about symmetry, crystals or this world, say briefly that you can only "
			.. "help with those.",
		"",
		"REFERENCE",
		"",
		"Glossary:",
	}
	for _, g in ipairs(content.glossary) do lines[#lines + 1] = "- " .. g end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Introduction (tier 0):"
	for _, l in ipairs(content.intro) do lines[#lines + 1] = "- " .. l end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Museum navigation:"
	lines[#lines + 1] = "- The foyer is the starting area and contains the welcome board and information desk."
	lines[#lines + 1] = "- The Workshop is west of the foyer and contains the Try-it Pad."
	lines[#lines + 1] = "- Gallery 1 is north of the foyer and teaches translation, rotation, reflection and inversion."
	lines[#lines + 1] = "- Beyond Gallery 1 are Gallery 2, the history of crystallography, and Gallery 3, crystals at the atomic scale."
	lines[#lines + 1] = "- The Portal Hall is furthest north and contains a portal to each symmetry world."
	lines[#lines + 1] = "- The /quiz command unlocks tiers; /tour starts a guided tour; /guide lists commands; /spawn returns to the foyer."
	for _, a in ipairs(content.regions) do
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Region: " .. a.name .. " (tier " .. a.tier .. ", symmetry "
			.. (a.hidden and "hidden" or a.symbol) .. ")"
		local tiers = {}
		for t in pairs(a.explain or {}) do tiers[#tiers + 1] = t end
		table.sort(tiers)
		for _, t in ipairs(tiers) do
			lines[#lines + 1] = "  Tier " .. t .. ":"
			for _, l in ipairs(a.explain[t]) do lines[#lines + 1] = "  - " .. l end
		end
	end
	return table.concat(lines, "\n")
end

function T.symmetry_system_prompt()
	local symbols = {}
	for _, e in ipairs(S.catalog) do symbols[#symbols + 1] = e.symbol end
	return "A student describes a symmetry in words. Pick the crystallographic point group that matches "
		.. "the description. Use exactly one symbol from this list, or 'none' if nothing matches (for "
		.. "example a 5-fold axis, which no crystal can have):\n"
		.. table.concat(symbols, " ") .. " \n\n"
		.. "If the description is incomplete, choose the smallest group that has everything mentioned. "
		.. "For example \"a fourfold axis\" is 4, \"a fourfold axis with mirrors\" is 4mm, \"a mirror\" is m. "
		.. "Pick the group even if it cannot be built on a grid of cubes; the game checks that separately."
end

local function base(system, user_text)
	return {
		model = T.MODEL,
		max_tokens = T.MAX_TOKENS,
		-- https://platform.claude.com/docs/en/build-with-claude/effort (GA, no beta header)
		output_config = { effort = "low" },
		-- Server-side fallback (beta, needs the anthropic-beta header in T.headers): if a safety
		-- classifier declines, the API retries on a recommended fallback model.
		-- https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback#server-side-fallback
		fallbacks = "default",
		system = { { type = "text", text = system, cache_control = { type = "ephemeral" } } },
		messages = { { role = "user", content = user_text } },
	}
end

function T.ask_body(question, tier, region_name)
	return base(T.tutor_system_prompt(),
		"Student tier: " .. tier .. "\nStudent is in: " .. (region_name or "no region") .. "\nQuestion: " .. question)
end

function T.symmetry_body(description)
	local body = base(T.symmetry_system_prompt(), "Description: " .. description)
	-- Structured outputs, GA, no beta header:
	-- https://platform.claude.com/docs/en/build-with-claude/structured-outputs
	-- The field is "explanation", not "reason": the docs warn that a property asking for the
	-- model's reasoning can trigger a reasoning_extraction refusal; a short explanation is fine.
	body.output_config.format = {
		type = "json_schema",
		schema = {
			type = "object",
			properties = {
				symbol = {
					type = "string",
					description = "Hermann-Mauguin symbol of the crystallographic point group that matches the "
						.. "description, exactly as written in the list, or 'none' if no point group matches",
				},
				explanation = {
					type = "string",
					description = "One short sentence for a student explaining which words in the description "
						.. "led to this symbol. Do not list the group's operations.",
				},
			},
			required = { "symbol", "explanation" },
			additionalProperties = false,
		},
	}
	return body
end

function T.headers(api_key)
	return {
		"Content-Type: application/json",
		"x-api-key: " .. api_key,
		"anthropic-version: 2023-06-01",
		-- Required for the fallbacks field; must be exactly this date for fallbacks = "default".
		"anthropic-beta: server-side-fallback-2026-07-01",
	}
end

--- Text of a Messages API response, or nil and a message for the player.
function T.response_text(response)
	if type(response) ~= "table" then return nil, "The tutor sent an unreadable reply." end
	if response.type == "error" then
		local kind = response.error and response.error.type or "error"
		if kind == "rate_limit_error" or kind == "overloaded_error" then
			return nil, "The tutor is busy right now. Try again in a minute."
		end
		return nil, "The tutor is unavailable (" .. kind .. ")."
	end
	if response.stop_reason == "refusal" then
		return nil, "The tutor can't answer that one. Try asking about symmetry or crystals."
	end
	-- A cut-off reply may be half a sentence or broken JSON, so it is not shown.
	-- https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons
	if response.stop_reason == "max_tokens" or response.stop_reason == "model_context_window_exceeded" then
		return nil, "The tutor's answer was cut off. Try a shorter or simpler question."
	end
	local parts = {}
	for _, block in ipairs(response.content or {}) do
		if block.type == "text" then parts[#parts + 1] = block.text end
	end
	local text = table.concat(parts):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil, "The tutor had nothing to say. Try rephrasing your question." end
	return text
end

--- Sends a request. http is Luanti's HTTP API; encode/decode are core.write_json/parse_json.
-- cfg is a table from T.config (a plain string is taken as an Anthropic API key).
-- callback(text_or_nil, error_message_or_nil)
function T.send(http, cfg, body, encode, decode, callback)
	if type(cfg) == "string" then cfg = { provider = "anthropic", api_key = cfg } end
	if cfg.provider == "openai_compatible" then
		T.openai_fetch(http, cfg, body, encode, decode, function(text, err) callback(text, err) end)
		return
	end
	local api_key = cfg.api_key
	local ok, data = pcall(encode, body)
	if not ok or type(data) ~= "string" then
		callback(nil, "The tutor could not send that question.")
		return
	end
	http.fetch({
		url = T.URL,
		method = "POST",
		extra_headers = T.headers(api_key),
		data = data,
		timeout = 90,
	}, function(res)
		if not res.succeeded then
			callback(nil, "The tutor could not be reached.")
			return
		end
		local ok, parsed = pcall(decode, res.data)
		if not ok or parsed == nil then
			callback(nil, "The tutor sent an unreadable reply.")
			return
		end
		callback(T.response_text(parsed))
	end)
end

---------------------------------------------------------------------------------------------------
-- Providers. "anthropic" (the default) is the Messages API above, unchanged. "openai_compatible" is
-- the Chat Completions API defined by OpenAI and also served by local servers such as Ollama and
-- llama.cpp's llama-server, so free open-source models can run the tutor:
--   https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
--   https://docs.ollama.com/api/openai-compatibility
--   https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
-- Both providers get the same system prompts (tutor_system_prompt, symmetry_system_prompt), so the
-- grounding rules are the same.

T.DEFAULT_BASE_URL = "http://localhost:11434/v1" -- Ollama's OpenAI-compatible endpoint
T.ANTHROPIC_TIMEOUT = 90
T.OPENAI_TIMEOUT = 60          -- seconds; crystalminer.tutor_timeout changes it
T.OPENAI_TEMPERATURE = 0.2
-- Small local models are slow on a CPU, so their answers are kept short. Thinking models need more:
-- crystalminer.tutor_max_tokens sets both.
T.OPENAI_ASK_TOKENS = 400
T.OPENAI_SYMMETRY_TOKENS = 200
-- Not every OpenAI-compatible server accepts "json_schema" (llama-cpp-python rejects it), so
-- /symmetry falls back to "json_object" and then to no response_format; the prompt asks for JSON.
T.RESPONSE_FORMATS = { "json_schema", "json_object", "none" }
T.SYMMETRY_JSON_INSTRUCTION = "\n\nReply with only a JSON object with two string fields, "
	.. "\"symbol\" (one symbol from the list, or \"none\") and \"explanation\" (one short sentence for "
	.. "the student). No other text."

local function trim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Reads the tutor settings. get(name) returns a setting or nil; getenv is os.getenv.
-- Returns cfg when the tutor can run; otherwise cfg (or nil) and the reason it is off.
function T.config(get, getenv)
	local provider = trim(get("crystalminer.tutor_provider"))
	if provider == "" then provider = "anthropic" end
	if provider == "anthropic" then
		-- Read exactly as before there was a provider setting.
		local key = get("crystalminer.anthropic_api_key")
		if not key or key == "" then key = getenv("ANTHROPIC_API_KEY") end
		local cfg = { provider = "anthropic", url = T.URL, model = T.MODEL, api_key = key,
			timeout = T.ANTHROPIC_TIMEOUT }
		if key == nil or key == "" then return cfg, "no API key set" end
		return cfg
	end
	if provider ~= "openai_compatible" then
		return nil, "unknown crystalminer.tutor_provider '" .. provider .. "' (use anthropic or openai_compatible)"
	end
	local base = trim(get("crystalminer.tutor_base_url"))
	if base == "" then base = T.DEFAULT_BASE_URL end
	base = base:gsub("/+$", "")
	local key = trim(get("crystalminer.tutor_api_key"))
	if key == "" then key = trim(getenv("CRYSTALMINER_TUTOR_API_KEY")) end
	local timeout = math.floor(tonumber(get("crystalminer.tutor_timeout")) or T.OPENAI_TIMEOUT)
	local max_tokens = tonumber(get("crystalminer.tutor_max_tokens"))
	if max_tokens then max_tokens = math.max(16, math.min(T.MAX_TOKENS, math.floor(max_tokens))) end
	local cfg = {
		provider = "openai_compatible",
		base_url = base,
		url = base .. "/chat/completions",
		model = trim(get("crystalminer.tutor_model")),
		api_key = key ~= "" and key or nil,
		timeout = math.max(5, math.min(600, timeout)),
		ask_tokens = max_tokens or T.OPENAI_ASK_TOKENS,
		symmetry_tokens = max_tokens or T.OPENAI_SYMMETRY_TOKENS,
	}
	if not base:match("^https?://[^%s]+$") then
		return cfg, "crystalminer.tutor_base_url must start with http:// or https://"
	end
	if cfg.model == "" then return cfg, "set crystalminer.tutor_model to the name of the model" end
	if key:find("%c") then return cfg, "the tutor API key contains control characters" end
	return cfg
end

--- One line for the server log. Never includes the API key.
function T.describe(cfg)
	if cfg.provider == "anthropic" then
		return "provider anthropic, url " .. cfg.url .. ", model " .. cfg.model
	end
	local url = cfg.base_url:gsub("//[^/@]*@", "//***@")
	return "provider openai_compatible, base_url " .. url .. ", model "
		.. (cfg.model ~= "" and cfg.model or "(not set)") .. ", API key " .. (cfg.api_key and "set" or "not set")
end

function T.openai_headers(api_key)
	local h = { "Content-Type: application/json" }
	if api_key and api_key ~= "" then h[#h + 1] = "Authorization: Bearer " .. api_key end
	return h
end

local function openai_body(cfg, system, user_text, max_tokens)
	return {
		model = cfg.model,
		messages = { { role = "system", content = system }, { role = "user", content = user_text } },
		max_tokens = max_tokens,
		temperature = T.OPENAI_TEMPERATURE,
	}
end

--- Request body for /ask with the configured provider. The text is the same for both providers.
function T.ask_request(cfg, question, tier, region_name)
	local a = T.ask_body(question, tier, region_name)
	if cfg.provider ~= "openai_compatible" then return a end
	return openai_body(cfg, a.system[1].text, a.messages[1].content, cfg.ask_tokens)
end

--- Request body for /symmetry. mode (openai_compatible only) is one of T.RESPONSE_FORMATS.
function T.symmetry_request(cfg, description, mode)
	local a = T.symmetry_body(description)
	if cfg.provider ~= "openai_compatible" then return a end
	local body = openai_body(cfg, a.system[1].text .. T.SYMMETRY_JSON_INSTRUCTION, a.messages[1].content,
		cfg.symmetry_tokens)
	mode = mode or "json_schema"
	if mode == "json_schema" then
		body.response_format = { type = "json_schema", json_schema = {
			name = "point_group_choice", schema = a.output_config.format.schema, strict = true } }
	elseif mode == "json_object" then
		body.response_format = { type = "json_object" }
	end
	return body
end

function T.http_error_message(code)
	code = tonumber(code) or 0
	if code == 429 then return "The tutor is busy right now. Try again in a minute." end
	if code == 401 or code == 403 then return "The tutor is unavailable: the AI server refused the API key." end
	if code == 404 then return "The tutor is unavailable: the AI server does not know that model or address." end
	if code >= 400 then return "The tutor is unavailable (error " .. code .. ")." end
	return "The tutor is unavailable."
end

local function error_detail(response)
	local err = response and response.error
	local message = type(err) == "table" and err.message or nil
	if type(message) ~= "string" or message == "" then return nil end
	return message:gsub("[%c\r\n]", " "):sub(1, 240)
end

--- Text of a Chat Completions response, or nil and a message for the player. code is the HTTP status.
function T.openai_response_text(response, code)
	if type(response) ~= "table" then return nil, "The tutor sent an unreadable reply." end
	code = tonumber(code) or 200
	if response.error ~= nil or code >= 400 then
		local detail = error_detail(response)
		return nil, T.http_error_message(code) .. (detail and ": " .. detail or "")
	end
	local choice = type(response.choices) == "table" and response.choices[1]
	if type(choice) ~= "table" then return nil, "The tutor sent an unreadable reply." end
	-- A cut-off reply may be half a sentence or broken JSON, so it is not shown.
	if choice.finish_reason == "length" then
		return nil, "The tutor's answer was cut off. Try a shorter or simpler question."
	end
	if choice.finish_reason == "content_filter" then
		return nil, "The tutor can't answer that one. Try asking about symmetry or crystals."
	end
	local msg = type(choice.message) == "table" and choice.message or {}
	local content = msg.content
	if type(content) == "table" then
		local parts = {}
		for _, p in ipairs(content) do
			if type(p) == "table" and type(p.text) == "string" then parts[#parts + 1] = p.text end
		end
		content = table.concat(parts)
	end
	if type(content) ~= "string" then content = "" end
	-- Some local reasoning models put their thinking in the reply; it is never shown.
	content = content:gsub("^%s*<think>.-</think>", "")
	if content:match("^%s*<think>") then content = "" end
	content = trim(content)
	if content == "" then
		if type(msg.refusal) == "string" and msg.refusal ~= "" then
			return nil, "The tutor can't answer that one. Try asking about symmetry or crystals."
		end
		return nil, "The tutor had nothing to say. Try rephrasing your question."
	end
	return content
end

--- One Chat Completions request. done(text, err, retryable): retryable is true when the server
-- returned an HTTP error that another response_format might avoid.
function T.openai_fetch(http, cfg, body, encode, decode, done)
	local ok, data = pcall(encode, body)
	if not ok or type(data) ~= "string" then
		done(nil, "The tutor could not send that question.")
		return
	end
	http.fetch({
		url = cfg.url,
		method = "POST",
		extra_headers = T.openai_headers(cfg.api_key),
		data = data,
		timeout = cfg.timeout or T.OPENAI_TIMEOUT,
	}, function(res)
		if not res.succeeded then
			done(nil, res.timeout and "The tutor took too long to answer. Try again with a simpler question."
				or "The tutor could not be reached.")
			return
		end
		local code = tonumber(res.code) or 0
		local retryable = code >= 400 and code ~= 401 and code ~= 403 and code ~= 404 and code ~= 429
		local okd, parsed = pcall(decode, res.data or "", nil, true)
		if not okd or parsed == nil then
			if code >= 400 then
				done(nil, T.http_error_message(code) .. " (the server response was not readable)", retryable)
			else
				done(nil, "The tutor sent an unreadable reply.")
			end
			return
		end
		local text, err = T.openai_response_text(parsed, code)
		done(text, err, text == nil and retryable)
	end)
end

--- /symmetry request. For openai_compatible, an HTTP error is retried once with "json_object" and
-- once more without response_format. The retries happen inside the caller's limiter slot.
function T.send_symmetry(http, cfg, description, encode, decode, callback)
	if cfg.provider ~= "openai_compatible" then
		T.send(http, cfg, T.symmetry_body(description), encode, decode, callback)
		return
	end
	local function try(i)
		T.openai_fetch(http, cfg, T.symmetry_request(cfg, description, T.RESPONSE_FORMATS[i]), encode, decode,
			function(text, err, retryable)
				if text == nil and retryable and T.RESPONSE_FORMATS[i + 1] then
					try(i + 1)
				else
					callback(text, err)
				end
			end)
	end
	try(1)
end

--- Finds the point-group choice in a model's reply: plain JSON, JSON in ``` fences, or JSON with
-- text around it. Only a symbol the symmetry engine knows (or "none") is accepted.
-- Returns symbol, explanation_or_nil; or nil and a message for the player.
function T.choose_symbol(text, decode)
	local fail = "The tutor could not pick a valid symmetry from that. Try a point-group symbol, like /symmetry 4mm."
	if type(text) ~= "string" then return nil, fail end
	local candidates = { text }
	local fenced = text:match("```[%w_]*%s*(.-)%s*```")
	if fenced then candidates[#candidates + 1] = fenced end
	local braces = text:match("%b{}")
	if braces then candidates[#candidates + 1] = braces end
	for _, c in ipairs(candidates) do
		local ok, obj = pcall(decode, c, nil, true)
		if ok and type(obj) == "table" and type(obj.symbol) == "string" then
			local symbol = trim(obj.symbol)
			if S.point_group(symbol) or symbol:lower() == "none" then
				local note = trim(obj.explanation)
				if note == "" or T.char_count(note) > T.MAX_CHARS then note = nil end
				return symbol, note
			end
		end
	end
	return nil, fail
end

--- Removes a "Tutor:" the model may have written itself, since the game adds its own label.
function T.strip_label(text)
	return (text:gsub("^%s*[Tt]utor%s*:%s*", ""))
end

return T
