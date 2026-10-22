-- Review questions (lessons.lua): what /quiz may ask again in a place whose questions for the
-- player's tier are done. From the real quiz data and a small made-up area.
package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local L = require("lessons")
local content = require("content")
local T = require("testlib")

print("lessons")

local function ids(qs)
	local out = {}
	for _, q in ipairs(qs) do out[#out + 1] = q.id end
	return table.concat(out, " ")
end

-- Questions at tiers 0, 2 and 5, with a gap: tiers 1, 3 and 4 have none.
local area = { id = "test_area", quiz = {
	[0] = { { q = "a", options = { "x", "y" }, answer = 0, why = "w" } },
	[2] = { { q = "b", options = { "x", "y" }, answer = 1, why = "w" }, { q = "c", options = { "x", "y" }, answer = 0, why = "w" } },
	[5] = { { q = "d", options = { "x", "y" }, answer = 1, why = "w" } },
} }

T.run("review questions: every tier up to the player's, lowest first", function()
	T.eq(ids(L.review_questions(area, 0)), "test_area.0.0")
	T.eq(ids(L.review_questions(area, 1)), "test_area.0.0")
	T.eq(ids(L.review_questions(area, 2)), "test_area.0.0 test_area.2.0 test_area.2.1")
	T.eq(ids(L.review_questions(area, 4)), "test_area.0.0 test_area.2.0 test_area.2.1")
end)

T.run("review questions never come from above the player's tier", function()
	for tier = 0, 6 do
		for _, q in ipairs(L.review_questions(area, tier)) do
			local _, t = q.id:match("^(.-)%.(%d+)%.%d+$")
			T.ok(tonumber(t) <= tier, q.id .. " at tier " .. tier)
		end
	end
	-- Real data: Mirror Plaza has tier-1 and tier-3 questions; at tier 2 only the tier-1 ones.
	local plaza = L.area(content, "mirror_plaza")
	for _, q in ipairs(L.review_questions(plaza, 2)) do T.ok(q.id:find("^mirror_plaza%.1%.") ~= nil, q.id) end
	T.eq(#L.review_questions(plaza, 2), #L.questions(plaza, 1))
	T.eq(#L.review_questions(plaza, 3), #L.questions(plaza, 1) + #L.questions(plaza, 3))
	-- A place with questions only above the tier, or none at all, has nothing to review.
	T.eq(#L.review_questions(L.area(content, "screw_hall"), 3), 0)
	T.eq(#L.review_questions({ id = "empty" }, 4), 0)
	T.eq(L.review_pick({ id = "empty" }, 4, 1), nil)
end)

T.run("review questions keep the ids, options and explanations of the normal questions", function()
	local gate = content.gate
	local normal = L.questions(gate, 0)
	local review = L.review_questions(gate, 4)
	T.eq(#review, #normal)
	for i, q in ipairs(review) do
		T.eq(q.id, normal[i].id)
		T.eq(q.answer, normal[i].answer, q.id)
		T.eq(q.why, normal[i].why, q.id)
		T.eq(q.hint, normal[i].hint, q.id)
		T.eq(q.display, normal[i].display, q.id)
		local same, tier = L.question(content, q.id)
		T.ok(same ~= nil and tier == 0, q.id)
	end
end)

T.run("review_pick cycles through the questions", function()
	local gate = content.gate
	local qs = L.review_questions(gate, 4)
	T.eq(#qs, 5)
	local seen = {}
	for k = 1, #qs do
		local q = L.review_pick(gate, 4, k)
		T.eq(q.id, qs[k].id)
		seen[q.id] = true
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	T.eq(n, #qs, "each question once per round")
	T.eq(L.review_pick(gate, 4, #qs + 1).id, qs[1].id, "wraps round")
	T.eq(L.review_pick(gate, 4, 2 * #qs + 3).id, qs[3].id, "wraps round again")
	T.eq(L.review_pick(gate, 4, nil).id, qs[1].id, "no k: the first")
end)

T.run("reviewing changes no progress", function()
	local p = L.new_progress()
	p.tier = 4
	local before = L.remaining(content, p)
	for k = 1, 12 do L.review_pick(content.gate, p.tier, k) end
	L.review_questions(L.area(content, "mirror_plaza"), p.tier)
	T.eq(p.tier, 4)
	T.eq(next(p.answered), nil)
	T.eq(L.remaining(content, p), before)
end)

T.finish()
