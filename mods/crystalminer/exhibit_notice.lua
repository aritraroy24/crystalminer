-- On-screen status for live exhibit loads. The text helpers are pure so they can be tested
-- without a Luanti server.

local N = {}

N.SAFETY_SECONDS = 70
N.SUCCESS_SECONDS = 2
N.FAILURE_SECONDS = 4
N.STAGES = { searching = true, checking = true, building = true }

function N.dots(elapsed)
	return string.rep(".", math.floor(elapsed) % 3 + 1)
end

function N.elapsed(elapsed)
	return math.max(0, math.floor(elapsed)) .. " s"
end

function N.display_name(name)
	name = tostring(name or "Live structure")
	if #name > 48 then name = name:sub(1, 45) .. "..." end
	return name
end

function N.lines(stage, elapsed, detail)
	elapsed = elapsed or 0
	if stage == "building" then return "Building the exhibit room...", N.elapsed(elapsed) end
	if stage == "checking" then return "Loading a random crystal structure", (detail or "Checking a record") .. " " .. N.elapsed(elapsed) end
	return "Loading a random crystal structure", "Searching the Materials Project" .. N.dots(elapsed) .. " " .. N.elapsed(elapsed)
end

function N.success(name, room)
	return "Structure ready: " .. N.display_name(name), "Entering exhibit room " .. tostring(room)
end

function N.failure(reason)
	return "Loading crystal structure", tostring(reason or "Could not load a new structure")
end

if not (rawget(_G, "core") and rawget(_G, "crystalminer")) then return N end

local cm = crystalminer
local active = {}
cm.exhibit_notice = N
cm.exhibit_notice_states = active

local function now()
	if core.get_us_time then return core.get_us_time() / 1000000 end
	return os.time()
end

local function player_for(name)
	local player = core.get_player_by_name(name)
	if not player or not player.hud_add or not player.hud_change or not player.hud_remove then return nil end
	if player.get_hp and player:get_hp() <= 0 then return nil end
	return player
end

local function remove(state, player)
	player = player or player_for(state.name)
	if player then
		if state.title then player:hud_remove(state.title) end
		if state.status then player:hud_remove(state.status) end
	end
	active[state.name] = nil
end

local function render(state, player)
	player = player or player_for(state.name)
	if not player then remove(state); return false end
	local elapsed = now() - state.started
	local title, status = N.lines(state.stage, elapsed, state.detail)
	if state.finished then
		if state.ok then title, status = N.success(state.structure, state.room)
		else title, status = N.failure(state.reason) end
	end
	local def = {
		hud_elem_type = "text", position = { x = 0.5, y = 0.2 }, alignment = { x = 0, y = 0 },
		number = 0xFFE680, size = { x = 2 }, z_index = 100, text = title,
	}
	local status_def = {
		hud_elem_type = "text", position = { x = 0.5, y = 0.24 }, alignment = { x = 0, y = 0 },
		number = 0xFFFFFF, size = { x = 1.5 }, z_index = 100, text = status,
	}
	if not state.title then state.title = player:hud_add(def) else player:hud_change(state.title, "text", title) end
	if not state.status then state.status = player:hud_add(status_def) else player:hud_change(state.status, "text", status) end
	return true
end

local function tick(state)
	if active[state.name] ~= state then return end
	if not render(state) then return end
	local elapsed = now() - state.started
	if state.finished then
		if elapsed >= state.remove_at then remove(state); return end
	else
		if elapsed >= N.SAFETY_SECONDS then
			state.finished, state.ok = true, false
			state.reason = "Could not load a new structure; the request timed out."
			state.remove_at = elapsed + N.FAILURE_SECONDS
			render(state)
		end
	end
	core.after(1, tick, state)
end

function N.begin(name, room)
	local state = { name = name, room = room, stage = "searching", started = now() }
	active[name] = state
	render(state)
	core.after(1, tick, state)
	return state
end

function N.join(name, room, shared)
	local state = active[name]
	if state then return state end
	state = N.begin(name, room)
	if shared then N.update(name, shared.stage, shared.detail, shared.started) end
	return state
end

function N.update(name, stage, detail, started)
	local state = active[name]
	if not state then return end
	if N.STAGES[stage] then state.stage = stage end
	state.detail = detail
	if started then state.started = started end
	render(state)
end

function N.finish(name, ok, structure, room, reason)
	local state = active[name]
	if not state then return end
	state.finished, state.ok = true, ok
	state.structure, state.room, state.reason = structure, room, reason
	state.remove_at = now() - state.started + (ok and N.SUCCESS_SECONDS or N.FAILURE_SECONDS)
	render(state)
end

function N.remove(name)
	local state = active[name]
	if state then remove(state) end
end

cm.exhibit_notice_remove = N.remove
core.register_on_leaveplayer(function(player) N.remove(player:get_player_name()) end)

return N
