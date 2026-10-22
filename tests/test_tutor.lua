package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local S = require("symmetry")
local content = require("content")
local Tutor = loadfile("mods/crystalminer/tutor.lua")(S, content)
local T = require("testlib")

print("tutor")

T.run("reference covers every region but not the Mystery Lab answer", function()
	local prompt = Tutor.tutor_system_prompt()
	for _, a in ipairs(content.regions) do T.ok(prompt:find(a.name, 1, true), a.name) end
	for _, a in ipairs(content.regions) do
		if a.hidden then T.ok(not prompt:find(a.hidden, 1, true), "hidden answer leaked: " .. a.hidden) end
	end
end)

T.run("symmetry prompt lists all 32 groups", function()
	local prompt = Tutor.symmetry_system_prompt()
	for _, e in ipairs(S.catalog) do T.ok(prompt:find(" " .. e.symbol .. " ", 1, true) or prompt:find("\n" .. e.symbol .. " ", 1, true), e.symbol) end
end)

T.run("ask request uses the model, low effort, fallbacks and a cached system prompt", function()
	local b = Tutor.ask_body("Why?", 2, "Square Court")
	T.eq(Tutor.URL, "https://api.anthropic.com/v1/messages")
	T.eq(b.model, "claude-opus-5-5")
	T.eq(b.max_tokens, 4096)
	T.eq(b.output_config.format, nil)
	T.eq(b.system[1].type, "text")
	T.eq(b.messages[1].role, "user")
	T.eq(#b.messages, 1)
	T.eq(b.output_config.effort, "low")
	T.eq(b.fallbacks, "default")
	T.eq(b.system[1].cache_control.type, "ephemeral")
	T.ok(b.messages[1].content:find("Square Court", 1, true))
	local hs = Tutor.headers("k")
	T.eq(#hs, 4)
	local h = table.concat(hs, "\n")
	T.ok(h:find("Content-Type: application/json", 1, true))
	T.ok(h:find("x-api-key: k", 1, true))
	T.ok(h:find("anthropic-version: 2023-06-01", 1, true))
	T.ok(h:find("anthropic-beta: server-side-fallback-2026-07-01", 1, true))
	for _, line in ipairs(hs) do T.ok(line:match("^[%w%-]+: %S"), "header format: " .. line) end
end)

T.run("symmetry request asks for a JSON schema with symbol and explanation", function()
	local b = Tutor.symmetry_body("a fourfold axis")
	T.eq(b.output_config.effort, "low")
	T.eq(b.fallbacks, "default")
	local f = b.output_config.format
	T.eq(f.type, "json_schema")
	T.eq(f.schema.type, "object")
	T.eq(f.schema.required[1], "symbol")
	T.eq(f.schema.required[2], "explanation")
	T.eq(f.schema.additionalProperties, false)
	T.eq(f.schema.properties.reason, nil)
	for k, prop in pairs(f.schema.properties) do
		T.eq(prop.type, "string", k)
		-- unsupported by structured outputs
		T.eq(prop.minLength, nil); T.eq(prop.maxLength, nil)
	end
	T.ok(b.messages[1].content:find("a fourfold axis", 1, true))
	-- ask bodies must not share the output_config table with symmetry bodies
	T.eq(Tutor.ask_body("x", 0, nil).output_config.format, nil)
end)

T.run("cut-off replies are not shown", function()
	local t, err = Tutor.response_text({ stop_reason = "max_tokens", content = { { type = "text", text = '{"symbol": "4' } } })
	T.ok(t == nil and err:find("cut off"))
	t = Tutor.response_text({ stop_reason = "end_turn", content = {
		{ type = "fallback", from = { model = "claude-opus-5-5" }, to = { model = "x" } },
		{ type = "text", text = "Hi" } } })
	T.eq(t, "Hi")
end)

T.run("question length is capped in characters, not bytes", function()
	T.eq(Tutor.char_count("abc"), 3)
	T.eq(Tutor.char_count("\u{00E9}\u{00E9}"), 2)
	T.eq(Tutor.check_length(string.rep("a", 300)), nil)
	T.ok(Tutor.check_length(string.rep("a", 301)):find("300"))
	T.eq(Tutor.check_length(string.rep("\u{00E9}", 300)), nil)
end)

T.run("cooldown per player and cap on requests in flight", function()
	local lim = Tutor.new_limiter()
	T.ok(Tutor.try_start(lim, "ann", 100))
	local ok, msg = Tutor.try_start(lim, "ann", 101)
	T.ok(not ok and msg:find("still thinking"))
	Tutor.finish(lim, "ann")
	ok, msg = Tutor.try_start(lim, "ann", 105)
	T.ok(not ok and msg:find("15 s"), msg)
	T.ok(Tutor.try_start(lim, "ann", 120))
	Tutor.finish(lim, "ann")
	-- server cap
	T.ok(Tutor.try_start(lim, "a", 200)); T.ok(Tutor.try_start(lim, "b", 200)); T.ok(Tutor.try_start(lim, "c", 200))
	ok, msg = Tutor.try_start(lim, "d", 200)
	T.ok(not ok and msg:find("other players"))
	T.eq(lim.last.d, nil)
	Tutor.finish(lim, "b")
	T.ok(Tutor.try_start(lim, "d", 201))
	-- finishing twice does not free an extra slot
	Tutor.finish(lim, "b")
	T.eq(lim.in_flight, 3)
end)

T.run("send reports an encode failure instead of hanging", function()
	local got
	Tutor.send({ fetch = function() error("should not fetch") end }, "k", {}, function() return nil, "bad" end,
		nil, function(t, e) got = e end)
	T.ok(got and got:find("could not send"))
	local req
	Tutor.send({ fetch = function(r, cb) req = r; cb({ succeeded = true, code = 200,
		data = '{"type":"message","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}' }) end },
		"k", Tutor.ask_body("q", 0), function() return "{}" end,
		function(d) return { type = "message", stop_reason = "end_turn", content = { { type = "text", text = "ok" } } } end,
		function(t) got = t end)
	T.eq(req.method, "POST"); T.eq(req.url, Tutor.URL); T.eq(req.data, "{}"); T.eq(got, "ok")
end)

T.run("responses are read safely", function()
	T.eq(Tutor.response_text({ content = { { type = "text", text = "  A mirror.  " } }, stop_reason = "end_turn" }), "A mirror.")
	local t, err = Tutor.response_text({ stop_reason = "refusal", content = {} })
	T.ok(t == nil and err:find("can't answer"))
	t, err = Tutor.response_text({ type = "error", error = { type = "rate_limit_error" } })
	T.ok(t == nil and err:find("busy"))
	t, err = Tutor.response_text({ content = { { type = "thinking", thinking = "" } }, stop_reason = "end_turn" })
	T.ok(t == nil and err:find("nothing to say"))
end)


--------------------------------------------------------------------------- providers

-- Canonical text of a table (keys sorted), to compare requests exactly.
local function ser(v)
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t ~= "table" then return tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

-- Minimal JSON decoder standing in for core.parse_json(s, nil, true): nil, err on bad input.
local function json_decode(s)
	local i = 1
	local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
	local value
	local function str()
		local out = {}
		i = i + 1
		while true do
			local c = s:sub(i, i)
			if c == "" then error("unterminated string") end
			if c == '"' then i = i + 1; return table.concat(out) end
			if c == "\\" then
				local e = s:sub(i + 1, i + 1)
				out[#out + 1] = ({ n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" })[e] or error("escape")
				i = i + 2
			else
				out[#out + 1] = c; i = i + 1
			end
		end
	end
	function value()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local o = {}; i = i + 1; ws()
			if s:sub(i, i) == "}" then i = i + 1; return o end
			while true do
				ws(); if s:sub(i, i) ~= '"' then error("key") end
				local k = str(); ws()
				if s:sub(i, i) ~= ":" then error("colon") end
				i = i + 1; o[k] = value(); ws()
				local d = s:sub(i, i); i = i + 1
				if d == "}" then return o end
				if d ~= "," then error("comma") end
			end
		elseif c == "[" then
			local a = {}; i = i + 1; ws()
			if s:sub(i, i) == "]" then i = i + 1; return a end
			while true do
				a[#a + 1] = value(); ws()
				local d = s:sub(i, i); i = i + 1
				if d == "]" then return a end
				if d ~= "," then error("comma") end
			end
		elseif c == '"' then return str()
		elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
		else
			local n = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			if not n or n == "" then error("unexpected " .. c) end
			i = i + #n; return tonumber(n)
		end
	end
	local ok, v = pcall(function() local v = value(); ws(); if i <= #s then error("trailing") end; return v end)
	if not ok then return nil, v end
	return v
end

local function settings(t) return function(k) return t[k] end end
local no_env = function() return nil end
local OC = { ["crystalminer.tutor_provider"] = "openai_compatible", ["crystalminer.tutor_model"] = "llama3.2" }

-- Captured from tutor.lua before the provider setting was added (system prompt text replaced by
-- <SYSTEM> because content.lua may change; it is compared to tutor_system_prompt() separately).
local GOLDEN_ASK = [==[{fallbacks="default",max_tokens=4096,messages={1={content="Student tier: 2\
Student is in: Square Court\
Question: Why is a mirror a symmetry?",role="user"}},model="claude-opus-5-5",output_config={effort="low"},system={1={cache_control={type="ephemeral"},text="<SYSTEM>",type="text"}}}]==]
local GOLDEN_SYM = [==[{fallbacks="default",max_tokens=4096,messages={1={content="Description: a fourfold axis with mirrors",role="user"}},model="claude-opus-5-5",output_config={effort="low",format={schema={additionalProperties=false,properties={explanation={description="One short sentence for a student explaining which words in the description led to this symbol. Do not list the group's operations.",type="string"},symbol={description="Hermann-Mauguin symbol of the crystallographic point group that matches the description, exactly as written in the list, or 'none' if no point group matches",type="string"}},required={1="symbol",2="explanation"},type="object"},type="json_schema"}},system={1={cache_control={type="ephemeral"},text="<SYSTEM>",type="text"}}}]==]
local GOLDEN_FETCH = [==[{data="BODY",extra_headers={1="Content-Type: application/json",2="x-api-key: sk-test",3="anthropic-version: 2023-06-01",4="anthropic-beta: server-side-fallback-2026-07-01"},method="POST",timeout=90,url="https://api.anthropic.com/v1/messages"}]==]

T.run("anthropic, by provider or by prefix: its requests are byte-for-byte unchanged", function()
	for _, get in ipairs({ settings({ ["crystalminer.anthropic_api_key"] = "sk-test", ["crystalminer.tutor_model"] = "anthropic/claude-opus-5-5" }),
		settings({ ["crystalminer.anthropic_api_key"] = "sk-test", ["crystalminer.tutor_provider"] = "anthropic" }) }) do
		local cfg, off = Tutor.config(get, no_env)
		T.eq(off, nil); T.eq(cfg.provider, "anthropic"); T.eq(cfg.api_key, "sk-test")
		local a = Tutor.ask_request(cfg, "Why is a mirror a symmetry?", 2, "Square Court")
		T.eq(a.system[1].text, Tutor.tutor_system_prompt()); a.system[1].text = "<SYSTEM>"
		T.eq(ser(a), GOLDEN_ASK)
		local s = Tutor.symmetry_request(cfg, "a fourfold axis with mirrors")
		T.eq(s.system[1].text, Tutor.symmetry_system_prompt()); s.system[1].text = "<SYSTEM>"
		T.eq(ser(s), GOLDEN_SYM)
		-- the old entry points give the same
		local a2 = Tutor.ask_body("Why is a mirror a symmetry?", 2, "Square Court"); a2.system[1].text = "<SYSTEM>"
		T.eq(ser(a2), GOLDEN_ASK)
		local req
		Tutor.send({ fetch = function(r) req = r end }, cfg, { x = 1 }, function() return "BODY" end, nil, function() end)
		T.eq(ser(req), GOLDEN_FETCH)
		Tutor.send({ fetch = function(r) req = r end }, "sk-test", { x = 1 }, function() return "BODY" end, nil, function() end)
		T.eq(ser(req), GOLDEN_FETCH)
		-- send_symmetry sends the Anthropic body once, with no retries
		local n = 0
		Tutor.send_symmetry({ fetch = function(r, cb) n = n + 1; req = r
			cb({ succeeded = true, code = 500, data = "x" }) end }, cfg, "a fourfold axis with mirrors",
			function(b) return ser(b) end, function() return nil end, function() end)
		T.eq(n, 1); T.eq(req.url, Tutor.URL)
		local sym = Tutor.symmetry_body("a fourfold axis with mirrors")
		T.eq(req.data, ser(sym))
	end
end)

T.run("anthropic key: setting, then ANTHROPIC_API_KEY, else off", function()
	local A = { ["crystalminer.tutor_provider"] = "anthropic" }
	local cfg, off = Tutor.config(settings(A), function(k) return k == "ANTHROPIC_API_KEY" and "env-key" or nil end)
	T.eq(off, nil); T.eq(cfg.api_key, "env-key")
	cfg, off = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "anthropic", ["crystalminer.anthropic_api_key"] = "" }), no_env)
	T.eq(off, "no API key set")
	cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "anthropic", ["crystalminer.anthropic_api_key"] = "sk-secret" }), no_env)
	T.ok(not Tutor.describe(cfg):find("sk-secret", 1, true))
	local _, why = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "nonsense" }), no_env)
	T.ok(why:find("unknown"), why)
end)

T.run("openai_compatible settings: base URL, model, key, env, timeout, tokens", function()
	local cfg, off = Tutor.config(settings(OC), no_env)
	T.eq(off, nil)
	T.eq(cfg.url, "http://localhost:11434/v1/chat/completions")
	T.eq(cfg.api_key, nil); T.eq(cfg.timeout, 60); T.eq(cfg.ask_tokens, 400); T.eq(cfg.symmetry_tokens, 200)
	local s = {}
	for k, v in pairs(OC) do s[k] = v end
	s["crystalminer.tutor_base_url"] = " https://openrouter.ai/api/v1/ "
	cfg = Tutor.config(settings(s), no_env)
	T.eq(cfg.url, "https://openrouter.ai/api/v1/chat/completions")
	s["crystalminer.tutor_base_url"] = "http://127.0.0.1:8080/v1"
	T.eq(Tutor.config(settings(s), no_env).url, "http://127.0.0.1:8080/v1/chat/completions")
	s["crystalminer.tutor_base_url"] = "localhost:11434"
	local _, why = Tutor.config(settings(s), no_env)
	T.ok(why and why:find("http"), why)
	s["crystalminer.tutor_base_url"] = nil
	cfg = Tutor.config(settings(s), function(k) return k == "CRYSTALMINER_TUTOR_API_KEY" and "env-secret" or nil end)
	T.eq(cfg.api_key, "env-secret")
	T.ok(not Tutor.describe(cfg):find("env-secret", 1, true))
	T.ok(Tutor.describe(cfg):find("llama3.2", 1, true) and Tutor.describe(cfg):find("localhost:11434", 1, true))
	s["crystalminer.tutor_api_key"] = "set-secret"
	T.eq(Tutor.config(settings(s), no_env).api_key, "set-secret")
	s["crystalminer.tutor_timeout"] = "120"; s["crystalminer.tutor_max_tokens"] = "2000"
	cfg = Tutor.config(settings(s), no_env)
	T.eq(cfg.timeout, 120); T.eq(cfg.ask_tokens, 2000); T.eq(cfg.symmetry_tokens, 2000)
	s["crystalminer.tutor_model"] = "  "
	_, why = Tutor.config(settings(s), no_env)
	T.ok(why and why:find("tutor_model"), why)
	s["crystalminer.tutor_model"] = "m"; s["crystalminer.tutor_api_key"] = "a\nb"
	_, why = Tutor.config(settings(s), no_env)
	T.ok(why and why:find("control"), why)
	s["crystalminer.tutor_api_key"] = nil; s["crystalminer.tutor_base_url"] = "https://u:p@example.org/v1"
	T.ok(not Tutor.describe(Tutor.config(settings(s), no_env)):find("u:p", 1, true))
end)

T.run("openai_compatible requests: same prompts, no Anthropic fields or headers", function()
	local cfg = Tutor.config(settings(OC), no_env)
	local b = Tutor.ask_request(cfg, "Why?", 2, "Square Court")
	T.eq(b.model, "llama3.2"); T.eq(b.max_tokens, 400); T.eq(b.temperature, 0.2)
	T.eq(#b.messages, 2)
	T.eq(b.messages[1].role, "system"); T.eq(b.messages[1].content, Tutor.tutor_system_prompt())
	T.eq(b.messages[2].role, "user")
	T.eq(b.messages[2].content, Tutor.ask_body("Why?", 2, "Square Court").messages[1].content)
	for _, k in ipairs({ "system", "output_config", "fallbacks", "response_format", "stream" }) do T.eq(b[k], nil, k) end
	local hs = Tutor.openai_headers(cfg.api_key)
	T.eq(ser(hs), '{1="Content-Type: application/json"}')
	hs = Tutor.openai_headers("k1")
	T.eq(ser(hs), '{1="Content-Type: application/json",2="Authorization: Bearer k1"}')
	for _, line in ipairs(hs) do T.ok(line:match("^[%w%-]+: %S"), "header format: " .. line) end

	local s = Tutor.symmetry_request(cfg, "a fourfold axis")
	T.eq(s.max_tokens, 200)
	T.ok(s.messages[1].content:sub(1, #Tutor.symmetry_system_prompt()) == Tutor.symmetry_system_prompt())
	T.ok(s.messages[1].content:find('"symbol"', 1, true) and s.messages[1].content:find("JSON", 1, true))
	T.eq(s.messages[2].content, "Description: a fourfold axis")
	local rf = s.response_format
	T.eq(rf.type, "json_schema"); T.eq(rf.json_schema.strict, true)
	T.ok(rf.json_schema.name:match("^[%w_%-]+$") and #rf.json_schema.name <= 64)
	T.eq(ser(rf.json_schema.schema), ser(Tutor.symmetry_body("x").output_config.format.schema))
	for _, k in ipairs({ "system", "output_config", "fallbacks" }) do T.eq(s[k], nil, k) end
	T.eq(ser(Tutor.symmetry_request(cfg, "x", "json_object").response_format), '{type="json_object"}')
	T.eq(Tutor.symmetry_request(cfg, "x", "none").response_format, nil)

	local req, got
	Tutor.send({ fetch = function(r, cb) req = r; cb({ succeeded = true, code = 200,
		data = '{"choices":[{"index":0,"message":{"role":"assistant","content":"Tutor: A mirror."},"finish_reason":"stop"}]}' }) end },
		cfg, b, function(x) return ser(x) end, json_decode, function(t) got = t end)
	T.eq(req.url, "http://localhost:11434/v1/chat/completions"); T.eq(req.method, "POST"); T.eq(req.timeout, 60)
	T.eq(ser(req.extra_headers), '{1="Content-Type: application/json"}')
	T.eq(got, "Tutor: A mirror."); T.eq(Tutor.strip_label(got), "A mirror.")
	T.eq(Tutor.strip_label("A mirror."), "A mirror.")
end)

T.run("openai_compatible responses are read safely", function()
	local function r(content, fr) return { choices = { { message = { role = "assistant", content = content }, finish_reason = fr } } } end
	T.eq(Tutor.openai_response_text(r("  A mirror.  ", "stop"), 200), "A mirror.")
	T.eq(Tutor.openai_response_text(r("<think>\nhmm\n</think>\n\nA mirror.", "stop"), 200), "A mirror.")
	local t, err = Tutor.openai_response_text(r("<think>still thinking", "stop"), 200)
	T.ok(t == nil and err:find("nothing to say"))
	t, err = Tutor.openai_response_text(r('{"symbol": "4', "length"), 200)
	T.ok(t == nil and err:find("cut off"))
	t, err = Tutor.openai_response_text(r("x", "content_filter"), 200)
	T.ok(t == nil and err:find("can't answer"))
	t, err = Tutor.openai_response_text({ error = { message = "model \"x\" not found", type = "api_error" } }, 404)
	T.ok(t == nil and err:find("does not know"), err)
	t, err = Tutor.openai_response_text({ error = { message = "Input should be 'text' or 'json_object'" } }, 500)
	T.ok(t == nil and err:find("500"), err)
	t, err = Tutor.openai_response_text({ error = { message = "bad key" } }, 401)
	T.ok(t == nil and err:find("API key"))
	t, err = Tutor.openai_response_text({ error = "plain string" }, 200)
	T.ok(t == nil and err:find("unavailable"))
	t, err = Tutor.openai_response_text({ choices = {} }, 200)
	T.ok(t == nil and err:find("unreadable"))
	t, err = Tutor.openai_response_text("garbage", 200)
	T.ok(t == nil and err:find("unreadable"))
	t, err = Tutor.openai_response_text(r(nil, "stop"), 200)
	T.ok(t == nil and err:find("nothing to say"))
	T.eq(Tutor.openai_response_text(r({ { type = "text", text = "A " }, { type = "text", text = "mirror." } }, "stop"), 200), "A mirror.")
	-- through send: non-JSON error bodies, unreadable 200s, network failure, timeout
	local cfg = Tutor.config(settings(OC), no_env)
	local function via(res)
		local got, gerr
		Tutor.send({ fetch = function(_, cb) cb(res) end }, cfg, {}, function() return "{}" end, json_decode,
			function(a, b) got, gerr = a, b end)
		return got, gerr
	end
	t, err = via({ succeeded = true, code = 500, data = "Internal Server Error" }); T.ok(t == nil and err:find("500"), err)
	t, err = via({ succeeded = true, code = 200, data = "<html>" }); T.ok(t == nil and err:find("unreadable"), err)
	t, err = via({ succeeded = false, code = 0, data = "" }); T.ok(t == nil and err:find("reached"), err)
	t, err = via({ succeeded = false, timeout = true, code = 0, data = "" }); T.ok(t == nil and err:find("too long"), err)
	t, err = via({ succeeded = true, code = 200, data = '{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}' })
	T.eq(t, "ok")
end)

T.run("symmetry falls back from json_schema to json_object to no response_format", function()
	local cfg = Tutor.config(settings(OC), no_env)
	local function run(responses)
		local sent, n, got, gerr, calls = {}, 0, nil, nil, 0
		Tutor.send_symmetry({ fetch = function(r, cb)
			n = n + 1; sent[n] = r.data; cb(responses[n] or responses[#responses]) end },
			cfg, "a fourfold axis", function(b) return ser(b.response_format) end, json_decode,
			function(a, b) calls = calls + 1; got, gerr = a, b end)
		T.eq(calls, 1)
		return sent, got, gerr
	end
	local ok200 = { succeeded = true, code = 200,
		data = '{"choices":[{"message":{"content":"{\\"symbol\\": \\"4\\", \\"explanation\\": \\"x\\"}"},"finish_reason":"stop"}]}' }
	local bad = { succeeded = true, code = 500,
		data = '{"error":{"message":"Input should be \'text\' or \'json_object\'","type":"internal_server_error"}}' }
	local sent, got = run({ ok200 })
	T.eq(#sent, 1); T.eq(sent[1], ser({ type = "json_schema", json_schema = {
		name = "point_group_choice", schema = Tutor.symmetry_body("x").output_config.format.schema, strict = true } }))
	T.eq(got, '{"symbol": "4", "explanation": "x"}')
	sent, got = run({ bad, ok200 })
	T.eq(#sent, 2); T.eq(sent[2], '{type="json_object"}'); T.ok(got)
	sent, got = run({ bad, { succeeded = true, code = 400, data = "Bad Request" }, ok200 })
	T.eq(#sent, 3); T.eq(sent[3], "nil"); T.ok(got)
	local err
	sent, got, err = run({ bad, bad, bad })
	T.eq(#sent, 3); T.eq(got, nil); T.ok(err:find("500"))
	-- not retried: success with a bad answer, auth, missing model, rate limit, network failure
	for _, res in ipairs({ { succeeded = true, code = 200, data = '{"choices":[{"message":{"content":"x"},"finish_reason":"length"}]}' },
		{ succeeded = true, code = 401, data = '{"error":{"message":"no"}}' },
		{ succeeded = true, code = 404, data = "404 page not found" },
		{ succeeded = true, code = 429, data = "" },
		{ succeeded = false, code = 0, data = "" } }) do
		sent = run({ res })
		T.eq(#sent, 1, ser(res))
	end
end)

T.run("the symbol is extracted defensively and only engine-known symbols pass", function()
	local sym, note = Tutor.choose_symbol('{"symbol": "4mm", "explanation": "Fourfold axis with mirrors."}', json_decode)
	T.eq(sym, "4mm"); T.eq(note, "Fourfold axis with mirrors.")
	sym = Tutor.choose_symbol('```json\n{"symbol": "4mm", "explanation": "x"}\n```', json_decode); T.eq(sym, "4mm")
	sym = Tutor.choose_symbol('```\n{"symbol":"m","explanation":"x"}\n```', json_decode); T.eq(sym, "m")
	sym = Tutor.choose_symbol('Sure! Here is my answer: {"symbol": " 2 ", "explanation": "x"} Hope it helps.', json_decode)
	T.eq(sym, "2")
	sym, note = Tutor.choose_symbol('{"symbol": "none", "explanation": ""}', json_decode); T.eq(sym, "none"); T.eq(note, nil)
	sym, note = Tutor.choose_symbol('{"symbol": "4mm", "explanation": "' .. string.rep("a", 301) .. '"}', json_decode)
	T.eq(sym, "4mm"); T.eq(note, nil)
	sym = Tutor.choose_symbol('{"symbol": "4mm"}', json_decode); T.eq(sym, "4mm")
	-- wrong answers seen from small local models, and garbage
	for _, bad in ipairs({ '{"symbol": "I420", "explanation": "x"}', '{"symbol": "cmm", "explanation": "x"}',
		'{"symbol": 4}', '{"group": "4mm"}', "4mm", "I think it is 4mm.", "", "{", "[]" }) do
		local s2, msg = Tutor.choose_symbol(bad, json_decode)
		T.eq(s2, nil, bad); T.ok(msg:find("could not pick a valid symmetry"), bad)
	end
	T.eq(Tutor.choose_symbol(nil, json_decode), nil)
	-- every accepted symbol is one the engine resolves
	for _, e in ipairs(S.catalog) do
		local s3 = Tutor.choose_symbol('{"symbol": "' .. e.symbol .. '", "explanation": "x"}', json_decode)
		T.eq(S.point_group(s3).symbol, e.symbol)
	end
end)

T.run("limits are unchanged for both providers", function()
	T.eq(Tutor.COOLDOWN, 20); T.eq(Tutor.MAX_IN_FLIGHT, 3); T.eq(Tutor.MAX_CHARS, 300); T.eq(Tutor.MAX_TOKENS, 4096)
	local cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "openai_compatible",
		["crystalminer.tutor_model"] = "m", ["crystalminer.tutor_max_tokens"] = "999999" }), no_env)
	T.eq(cfg.ask_tokens, 4096)
	cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "openai_compatible",
		["crystalminer.tutor_model"] = "m", ["crystalminer.tutor_timeout"] = "1" }), no_env)
	T.eq(cfg.timeout, 5)
end)

T.run("deepseek preset: hosted URL, model and the DEEPSEEK_API_KEY variable", function()
	local env = function(k) return ({ DEEPSEEK_API_KEY = "ds-env", CRYSTALMINER_TUTOR_API_KEY = "other" })[k] end
	-- The base URL setting's default (Ollama) is what Luanti hands back when it was never changed.
	local cfg, off = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "deepseek",
		["crystalminer.tutor_base_url"] = Tutor.DEFAULT_BASE_URL }), env)
	T.eq(off, nil)
	T.eq(cfg.provider, "openai_compatible"); T.eq(cfg.service, "DeepSeek")
	T.eq(cfg.url, "https://api.deepseek.com/chat/completions"); T.eq(cfg.model, "deepseek-flash")
	T.eq(cfg.api_key, "ds-env")
	T.ok(not Tutor.describe(cfg):find("ds-env", 1, true), "the key must never be logged")
	T.ok(Tutor.describe(cfg):find("deepseek", 1, true))
	-- The settings win over the preset.
	cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "deepseek", ["crystalminer.tutor_model"] = "deepseek-v4-pro",
		["crystalminer.tutor_api_key"] = "ds-set", ["crystalminer.tutor_base_url"] = "https://proxy.example/v1" }), env)
	T.eq(cfg.model, "deepseek-v4-pro"); T.eq(cfg.api_key, "ds-set"); T.eq(cfg.url, "https://proxy.example/v1/chat/completions")
	-- Without a key the tutor stays off and says why.
	cfg, off = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "deepseek" }), no_env)
	T.ok(off and off:find("DEEPSEEK_API_KEY"), off)
end)

T.run("chat request: answered turns only, alternating, the newest last, with the chat prompt", function()
	local cfg = Tutor.config(settings(OC), no_env)
	local history = {
		{ role = "user", text = "What is a mirror?" }, { role = "assistant", text = "A reflection." },
		{ role = "user", text = "Lost question" }, { role = "error", text = "The tutor could not be reached." },
		{ role = "user", text = "And inversion?" }, { role = "assistant", text = "Through a point." },
	}
	local b = Tutor.chat_request(cfg, history, "Which is in m-3m?", 3, "Kaleidoscope")
	T.eq(b.model, "llama3.2"); T.eq(b.max_tokens, Tutor.CHAT_TOKENS)
	T.eq(#b.messages, 6)
	T.eq(b.messages[1].role, "system"); T.eq(b.messages[1].content, Tutor.chat_system_prompt())
	local roles = {}
	for i = 2, #b.messages do roles[#roles + 1] = b.messages[i].role end
	T.eq(table.concat(roles, " "), "user assistant user assistant user")
	T.eq(b.messages[4].content, "And inversion?")
	T.eq(b.messages[6].content, "Student tier: 3\nStudent is in: Kaleidoscope\nQuestion: Which is in m-3m?")
	-- Claude gets the same turns in its own format.
	local a = Tutor.chat_request({ provider = "anthropic" }, history, "Which is in m-3m?", 3, nil)
	T.eq(#a.messages, 5); T.eq(a.messages[1].role, "user"); T.eq(a.system[1].text, Tutor.chat_system_prompt())
	T.ok(a.messages[5].content:find("Student is in: the museum", 1, true))
	-- A long conversation sends only the last T.CHAT_HISTORY messages, starting with a question.
	local long = {}
	for i = 1, 20 do
		long[#long + 1] = { role = "user", text = "q" .. i }
		long[#long + 1] = { role = "assistant", text = "a" .. i }
	end
	b = Tutor.chat_request(cfg, long, "last", 0, nil)
	T.eq(#b.messages, Tutor.CHAT_HISTORY + 2)
	T.eq(b.messages[2].role, "user"); T.eq(b.messages[2].content, "q" .. (20 - Tutor.CHAT_HISTORY / 2 + 1))
end)

T.run("chat prompt: the museum's galleries, the same rules, no hidden answer", function()
	local p = Tutor.chat_system_prompt()
	T.ok(p:find(content.tutor.name, 1, true))
	T.ok(p:find("Use only the reference below", 1, true))
	T.ok(p:find("Do not give away quiz answers", 1, true))
	T.ok(p:find(content.museum.exhibits[1].facts[1], 1, true), "museum facts")
	T.ok(p:find(content.lobby.history[1].who, 1, true), "history")
	for _, a in ipairs(content.regions) do
		if a.hidden then T.ok(not p:find(a.hidden, 1, true), "hidden answer leaked: " .. a.hidden) end
	end
end)

local function env(t) return function(k) return t[k] end end

T.run("the default model is deepseek/deepseek-flash, with DEEPSEEK_API_KEY", function()
	local cfg, off = Tutor.config(settings({}), env({ DEEPSEEK_API_KEY = "ds" }))
	T.eq(off, nil); T.eq(cfg.prefix, "deepseek"); T.eq(cfg.model, "deepseek-flash")
	T.eq(cfg.url, "https://api.deepseek.com/chat/completions"); T.eq(cfg.api_key, "ds")
	-- Without a key it is off and says which variable to set.
	local _, why = Tutor.config(settings({}), no_env)
	T.ok(why and why:find("DEEPSEEK_API_KEY", 1, true), why)
end)

T.run("provider/model, as in LiteLLM: each provider's address and key variable", function()
	local keys = { OPENAI_API_KEY = "o", GEMINI_API_KEY = "g", GROQ_API_KEY = "q", MISTRAL_API_KEY = "m", OPENROUTER_API_KEY = "r",
		TOGETHERAI_API_KEY = "t", XAI_API_KEY = "x", FIREWORKS_AI_API_KEY = "f", PERPLEXITYAI_API_KEY = "p", CEREBRAS_API_KEY = "c" }
	local cases = {
		{ "openai/gpt-5.5", "https://api.openai.com/v1", "gpt-5.5", "o" },
		{ "gemini/gemini-3-flash", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-3-flash", "g" },
		{ "groq/llama-4-scout", "https://api.groq.com/openai/v1", "llama-4-scout", "q" },
		{ "mistral/mistral-large-latest", "https://api.mistral.ai/v1", "mistral-large-latest", "m" },
		{ "openrouter/meta-llama/llama-4-maverick", "https://openrouter.ai/api/v1", "meta-llama/llama-4-maverick", "r" },
		{ "together_ai/Qwen/Qwen3-235B", "https://api.together.xyz/v1", "Qwen/Qwen3-235B", "t" },
		{ "xai/grok-4", "https://api.x.ai/v1", "grok-4", "x" },
		{ "fireworks_ai/accounts/fireworks/models/glm-5", "https://api.fireworks.ai/inference/v1", "accounts/fireworks/models/glm-5", "f" },
		{ "perplexity/sonar", "https://api.perplexity.ai", "sonar", "p" },
		{ "cerebras/qwen-3-coder", "https://api.cerebras.ai/v1", "qwen-3-coder", "c" },
		{ "deepseek/deepseek-v4-pro", "https://api.deepseek.com", "deepseek-v4-pro", nil },
	}
	for _, c in ipairs(cases) do
		local cfg, off = Tutor.config(settings({ ["crystalminer.tutor_model"] = c[1] }), env(keys))
		if c[4] then T.eq(off, nil, c[1]) end
		T.eq(cfg.provider, "openai_compatible", c[1]); T.eq(cfg.base_url, c[2], c[1]); T.eq(cfg.model, c[3], c[1])
		if c[4] then T.eq(cfg.api_key, c[4], c[1]) end
		T.eq(Tutor.ask_request(cfg, "Why?", 1, nil).model, c[3], c[1])
	end
	-- A missing key names its variable.
	local _, why = Tutor.config(settings({ ["crystalminer.tutor_model"] = "gemini/gemini-3-flash" }), no_env)
	T.ok(why and why:find("GEMINI_API_KEY", 1, true), why)
end)

T.run("anthropic/<model> sends that Claude model to the Messages API", function()
	local cfg, off = Tutor.config(settings({ ["crystalminer.tutor_model"] = "anthropic/claude-sonnet-5-5" }), env({ ANTHROPIC_API_KEY = "a" }))
	T.eq(off, nil); T.eq(cfg.provider, "anthropic"); T.eq(cfg.url, Tutor.URL)
	T.eq(Tutor.ask_request(cfg, "Why?", 1, nil).model, "claude-sonnet-5-5")
	T.eq(Tutor.symmetry_request(cfg, "a mirror").model, "claude-sonnet-5-5")
	T.eq(Tutor.chat_request(cfg, {}, "Why?", 1, nil).model, "claude-sonnet-5-5")
end)

T.run("local servers and a LiteLLM proxy: no key needed, the address from LiteLLM's variables", function()
	local cfg, off = Tutor.config(settings({ ["crystalminer.tutor_model"] = "ollama/llama3.2" }), no_env)
	T.eq(off, nil); T.eq(cfg.url, "http://localhost:11434/v1/chat/completions"); T.eq(cfg.model, "llama3.2"); T.eq(cfg.api_key, nil)
	-- LiteLLM's OLLAMA_API_BASE has no /v1; it is added.
	cfg = Tutor.config(settings({ ["crystalminer.tutor_model"] = "ollama_chat/qwen3" }), env({ OLLAMA_API_BASE = "http://gpu-box:11434/" }))
	T.eq(cfg.url, "http://gpu-box:11434/v1/chat/completions")
	cfg, off = Tutor.config(settings({ ["crystalminer.tutor_model"] = "litellm_proxy/bedrock-claude" }),
		env({ LITELLM_PROXY_API_BASE = "http://0.0.0.0:4000", LITELLM_PROXY_API_KEY = "sk-proxy" }))
	T.eq(off, nil); T.eq(cfg.url, "http://0.0.0.0:4000/v1/chat/completions"); T.eq(cfg.model, "bedrock-claude"); T.eq(cfg.api_key, "sk-proxy")
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_model"] = "litellm_proxy/x" }), no_env).url, "http://localhost:4000/v1/chat/completions")
	-- vLLM has no usual address, so it must be given.
	local _, why = Tutor.config(settings({ ["crystalminer.tutor_model"] = "hosted_vllm/qwen" }), no_env)
	T.ok(why and why:find("HOSTED_VLLM_API_BASE", 1, true), why)
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_model"] = "hosted_vllm/qwen", ["crystalminer.tutor_base_url"] = "http://h:8000/v1" }), no_env).url,
		"http://h:8000/v1/chat/completions")
end)

T.run("choosing the model: setting, then CRYSTALMINER_TUTOR_MODEL; a prefix wins; a bare name needs one", function()
	local e = env({ CRYSTALMINER_TUTOR_MODEL = "openai/gpt-5.5", OPENAI_API_KEY = "o" })
	T.eq(Tutor.config(settings({}), e).model, "gpt-5.5")
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_model"] = "groq/llama-4" }), e).prefix, "groq")
	-- An old "provider = deepseek" with a model from another provider follows the model.
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_provider"] = "deepseek", ["crystalminer.tutor_model"] = "openai/gpt-5.5" }), e).prefix, "openai")
	-- A provider setting with a bare model name still works.
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_provider"] = "mistral", ["crystalminer.tutor_model"] = "mistral-small" }), no_env).base_url, "https://api.mistral.ai/v1")
	local _, why = Tutor.config(settings({ ["crystalminer.tutor_model"] = "llama3.2" }), no_env)
	T.ok(why and why:find("provider in front", 1, true) and why:find("ollama", 1, true), why)
	-- openai_compatible keeps the model's name as it is, slashes and all.
	T.eq(Tutor.config(settings({ ["crystalminer.tutor_provider"] = "openai_compatible", ["crystalminer.tutor_model"] = "openai/gpt-oss-20b",
		["crystalminer.tutor_base_url"] = "https://api.groq.com/openai/v1" }), no_env).model, "openai/gpt-oss-20b")
end)

T.run("a limiter can have a shorter wait between questions", function()
	local lim = Tutor.new_limiter(5)
	T.ok(Tutor.try_start(lim, "ann", 100)); Tutor.finish(lim, "ann")
	local ok, msg = Tutor.try_start(lim, "ann", 102)
	T.ok(not ok and msg:find("3 s"), msg)
	T.ok(Tutor.try_start(lim, "ann", 105))
end)

-- Settings written before the provider/model setting (tutor_provider anthropic or openai_compatible) must keep working.
T.run("old settings: anthropic with its key is still Claude, whatever tutor_model holds", function()
	local A = { ["crystalminer.tutor_provider"] = "anthropic", ["crystalminer.anthropic_api_key"] = "sk-ant-old" }
	local cfg, off = Tutor.config(settings(A), no_env)
	T.eq(off, nil); T.eq(cfg.provider, "anthropic"); T.eq(cfg.url, "https://api.anthropic.com/v1/messages")
	T.eq(cfg.model, "claude-opus-5-5"); T.eq(cfg.api_key, "sk-ant-old")
	-- A model name left over from an earlier openai_compatible setup was ignored by the anthropic provider, and still is.
	A["crystalminer.tutor_model"] = "llama3.2"
	cfg, off = Tutor.config(settings(A), no_env)
	T.eq(off, nil); T.eq(cfg.provider, "anthropic"); T.eq(cfg.model, "claude-opus-5-5")
	T.eq(Tutor.ask_request(cfg, "Why?", 1, nil).model, "claude-opus-5-5")
	-- A Claude model name is used.
	A["crystalminer.tutor_model"] = "claude-sonnet-5-5"
	T.eq(Tutor.config(settings(A), no_env).model, "claude-sonnet-5-5")
	-- ANTHROPIC_API_KEY comes before the shared Tutor: API key, which may hold another provider's key.
	local B = { ["crystalminer.tutor_provider"] = "anthropic", ["crystalminer.tutor_api_key"] = "ds-leftover" }
	cfg = Tutor.config(settings(B), env({ ANTHROPIC_API_KEY = "a-env" }))
	T.eq(cfg.api_key, "a-env")
	cfg, off = Tutor.config(settings(B), no_env)
	T.eq(off, nil); T.eq(cfg.api_key, "ds-leftover")
end)

T.run("old settings: openai_compatible at https://api.deepseek.com is DeepSeek", function()
	local D = { ["crystalminer.tutor_provider"] = "openai_compatible", ["crystalminer.tutor_base_url"] = "https://api.deepseek.com",
		["crystalminer.tutor_model"] = "deepseek-flash" }
	-- The key in the setting, in CRYSTALMINER_TUTOR_API_KEY (as before), or in DEEPSEEK_API_KEY (as the README now says).
	for _, case in ipairs({
		{ settings = { ["crystalminer.tutor_api_key"] = "k-set" }, env = {}, key = "k-set" },
		{ settings = {}, env = { CRYSTALMINER_TUTOR_API_KEY = "k-cm" }, key = "k-cm" },
		{ settings = {}, env = { DEEPSEEK_API_KEY = "k-ds" }, key = "k-ds" },
		{ settings = {}, env = { DEEPSEEK_API_KEY = "k-ds", CRYSTALMINER_TUTOR_API_KEY = "k-cm" }, key = "k-cm" },
	}) do
		local s = {}
		for k, v in pairs(D) do s[k] = v end
		for k, v in pairs(case.settings) do s[k] = v end
		local cfg, off = Tutor.config(settings(s), env(case.env))
		T.eq(off, nil)
		T.eq(cfg.provider, "openai_compatible"); T.eq(cfg.service, "DeepSeek")
		T.eq(cfg.url, "https://api.deepseek.com/chat/completions"); T.eq(cfg.model, "deepseek-flash")
		T.eq(cfg.api_key, case.key)
		T.ok(not Tutor.describe(cfg):find(case.key, 1, true), "the key must never be logged")
		local req
		Tutor.send({ fetch = function(r) req = r end }, cfg, Tutor.chat_request(cfg, {}, "Why?", 1, nil),
			function(b) return ser(b) end, nil, function() end)
		T.eq(req.url, "https://api.deepseek.com/chat/completions")
		T.ok(req.data:find('model="deepseek-flash"', 1, true), req.data)
		T.eq(req.extra_headers[2], "Authorization: Bearer " .. case.key)
	end
	-- With a trailing slash, and with no key at all (as before: the server answers 401, the tutor is not switched off).
	D["crystalminer.tutor_base_url"] = "https://api.deepseek.com/"
	local cfg, off = Tutor.config(settings(D), no_env)
	T.eq(off, nil); T.eq(cfg.url, "https://api.deepseek.com/chat/completions"); T.eq(cfg.api_key, nil)
	-- A local server is not taken for a hosted provider.
	cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "openai_compatible", ["crystalminer.tutor_model"] = "m",
		["crystalminer.tutor_base_url"] = "http://127.0.0.1:8000/v1" }), env({ DEEPSEEK_API_KEY = "k-ds" }))
	T.eq(cfg.service, nil); T.eq(cfg.api_key, nil)
end)

T.run("provider error details never show an API key", function()
	-- Fake keys are put together here, so that no key-shaped string is in the repository.
	local key = "sk-" .. ("0a1b"):rep(8)
	local _, err = Tutor.openai_response_text({ error = { message = "Authentication Fails, Your api key: " .. key .. " is invalid" } }, 401)
	T.ok(not err:find("0123456789abcdef", 1, true), err)
	T.ok(err:find("refused the API key", 1, true), err)
	for _, m in ipairs({ "Incorrect API key provided: sk-proj-" .. ("Ab1"):rep(4) .. "****wxyz.", "bad header Bearer abc.def-ghi",
		"API key not valid: AIza" .. ("Xy9"):rep(12), "Invalid API Key gsk_" .. ("9f8e"):rep(10) }) do
		_, err = Tutor.openai_response_text({ error = { message = m } }, 401)
		T.ok(not err:find("Ab1Ab1", 1, true) and not err:find("abc.def", 1, true) and not err:find("Xy9Xy9", 1, true)
			and not err:find("9f8e9f8e", 1, true), err)
	end
	-- The configured key itself, even a short one that looks like nothing in particular, through openai_fetch.
	local cfg = Tutor.config(settings({ ["crystalminer.tutor_provider"] = "openai_compatible", ["crystalminer.tutor_model"] = "m",
		["crystalminer.tutor_api_key"] = "hunter2key" }), no_env)
	local got
	Tutor.openai_fetch({ fetch = function(_, cb) cb({ succeeded = true, code = 401,
		data = '{"error":{"message":"key hunter2key is not valid"}}' }) end }, cfg, {}, function() return "B" end,
		json_decode, function(_, e) got = e end)
	T.ok(got and not got:find("hunter2key", 1, true) and got:find("***", 1, true), got)
	-- An ordinary message is left as it is.
	_, err = Tutor.openai_response_text({ error = { message = "model \"llama3.2\" not found" } }, 404)
	T.ok(err:find("llama3.2", 1, true), err)
end)

T.run("chat: a server with too small a context gets the question again the /ask way", function()
	local cfg = Tutor.config(settings(OC), no_env)
	local history = { { role = "user", text = "What is a mirror?" }, { role = "assistant", text = "A reflection." } }
	local reqs, got, gerr = {}, nil, nil
	local replies = {
		{ succeeded = true, code = 400, data = '{"error":{"message":"This model\'s maximum context length is 4096 tokens. However, you requested 6167 tokens"}}' },
		{ succeeded = true, code = 200, data = '{"choices":[{"message":{"content":"A mirror reflects."},"finish_reason":"stop"}]}' },
	}
	local http = { fetch = function(r, cb) reqs[#reqs + 1] = r; cb(replies[#reqs]) end }
	Tutor.send_chat(http, cfg, history, "And inversion?", 2, "the museum", function(b) return ser(b) end, json_decode,
		function(t, e) got, gerr = t, e end)
	T.eq(#reqs, 2); T.eq(got, "A mirror reflects."); T.eq(gerr, nil)
	T.ok(reqs[1].data:find(Tutor.chat_system_prompt():sub(1, 200), 1, true), "first: the chat prompt")
	T.ok(reqs[1].data:find("What is a mirror?", 1, true), "first: with the history")
	T.ok(not reqs[2].data:find("What is a mirror?", 1, true), "second: without the history")
	T.ok(reqs[2].data:find("max_tokens=400", 1, true), reqs[2].data:sub(1, 80))
	-- Any other error is passed on, once.
	reqs, replies = {}, { { succeeded = true, code = 401, data = '{"error":{"message":"no"}}' } }
	Tutor.send_chat(http, cfg, history, "Q", 2, nil, function(b) return ser(b) end, json_decode, function(t, e) got, gerr = t, e end)
	T.eq(#reqs, 1); T.eq(got, nil); T.ok(gerr:find("API key"), gerr)
	-- Claude gets the chat request through T.send, unchanged.
	local ccfg = Tutor.config(settings({ ["crystalminer.tutor_model"] = "anthropic/claude-opus-5-5", ["crystalminer.anthropic_api_key"] = "k" }), no_env)
	reqs = {}
	Tutor.send_chat(http, ccfg, history, "Q", 2, nil, function(b) return ser(b) end, json_decode, function() end)
	T.eq(#reqs, 1); T.eq(reqs[1].url, Tutor.URL)
end)

T.run("an error with detail reads as one sentence", function()
	local _, err = Tutor.openai_response_text({ error = { message = "boom" } }, 500)
	T.eq(err, "The tutor is unavailable (error 500): boom")
end)

T.finish()
