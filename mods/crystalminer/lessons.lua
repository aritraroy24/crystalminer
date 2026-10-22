-- Tiers, quiz questions and explanations. Pure Lua, no Luanti calls.

local L = {}

local function sorted_tiers(t)
	local keys = {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

--- All areas: the gate first, then the regions.
function L.areas(content)
	local out = { content.gate }
	for _, r in ipairs(content.regions) do out[#out + 1] = r end
	return out
end

function L.area(content, id)
	for _, a in ipairs(L.areas(content)) do
		if a.id == id then return a end
	end
	return nil
end

function L.area_tier(area)
	return area.tier or 0
end

--- The questions of one area at one tier, each with a stable id "area.tier.index".
function L.questions(area, tier)
	local out = {}
	for i, q in ipairs((area.quiz or {})[tier] or {}) do
		out[#out + 1] = { id = area.id .. "." .. tier .. "." .. (i - 1), q = q.q, options = q.options, answer = q.answer,
			why = q.why, hint = q.hint, display = q.display }
	end
	return out
end

--- Every question needed to complete a tier, in order.
function L.questions_for_tier(content, tier)
	local out = {}
	for _, a in ipairs(L.areas(content)) do
		for _, q in ipairs(L.questions(a, tier)) do out[#out + 1] = q end
	end
	return out
end

function L.question(content, id)
	local area_id, tier = id:match("^(.-)%.(%d+)%.%d+$")
	if not area_id then return nil end
	local a = L.area(content, area_id)
	if not a then return nil end
	for _, q in ipairs(L.questions(a, tonumber(tier))) do
		if q.id == id then return q, tonumber(tier) end
	end
	return nil
end

--- The questions of one area that a player at `tier` may review: every tier from 0 up to and
--- including `tier`, lowest tier first. Never a question above `tier` (no spoilers).
function L.review_questions(area, tier)
	local out = {}
	for _, t in ipairs(sorted_tiers(area.quiz)) do
		if t <= tier then
			for _, q in ipairs(L.questions(area, t)) do out[#out + 1] = q end
		end
	end
	return out
end

--- The k-th review question of an area (k = 1, 2, 3 ...; it wraps round), or nil if the area has
--- none at or below `tier`.
function L.review_pick(area, tier, k)
	local qs = L.review_questions(area, tier)
	if #qs == 0 then return nil end
	return qs[(math.max(1, math.floor(k or 1)) - 1) % #qs + 1]
end

function L.max_tier(content)
	local m = 0
	for k in pairs(content.tiers) do m = math.max(m, k) end
	return m
end

--- Explanation lines for every tier up to the player's.
function L.explanation(area, player_tier)
	local out = {}
	for _, t in ipairs(sorted_tiers(area.explain)) do
		if t <= player_tier then
			for _, line in ipairs(area.explain[t]) do out[#out + 1] = line end
		end
	end
	return out
end

function L.new_progress()
	return { tier = 0, answered = {}, challenge = 1 }
end

--- Number of questions still open in the player's current tier.
function L.remaining(content, progress)
	local n = 0
	for _, q in ipairs(L.questions_for_tier(content, progress.tier)) do
		if not progress.answered[q.id] then n = n + 1 end
	end
	return n
end

--- Records a correct answer. Returns true if that completed the tier (the tier is then raised).
function L.record_correct(content, progress, id)
	progress.answered[id] = true
	if progress.tier < L.max_tier(content) and L.remaining(content, progress) == 0 then
		progress.tier = progress.tier + 1
		return true
	end
	return false
end

--- The seed blocks of a region's showcase as { dx, dy, dz, colour }, offsets from the region's
-- minimum corner. Pixel art rows run top to bottom; "." is empty.
function L.showcase_blocks(area)
	local sc = area.showcase
	if not sc then return {} end
	local out = {}
	for _, b in ipairs(sc.blocks or {}) do out[#out + 1] = { b[1], b[2], b[3], b[4] } end
	for _, art in ipairs(sc.art or {}) do
		local n = #art.rows
		for row, line in ipairs(art.rows) do
			for col = 1, #line do
				local colour = art.key[line:sub(col, col)]
				if colour then
					local u, v = col - 1, n - row
					if art.plane == "xy" then
						out[#out + 1] = { art.at[1] + u, art.at[2] + v, art.at[3], colour }
					else -- "zy"
						out[#out + 1] = { art.at[1], art.at[2] + v, art.at[3] + u, colour }
					end
				end
			end
		end
	end
	return out
end

--- The symmetry-engine spec for a region, optionally with different generators (Free Lab).
function L.region_spec(area, generators)
	local spec = { min = area.at, generators = generators or area.generators or {} }
	if area.periodic then
		spec.cell, spec.counts = area.periodic.cell, area.periodic.counts
	else
		spec.size, spec.anchor = area.size, area.anchor
	end
	return spec
end

return L
