-- Reference results from the Lua engine for tests/test_web.mjs, which checks web/js/symmetry.js against them: the images of sample blocks in every world (in each world's own coordinates, as tools/export_web.lua writes them) and the detected symmetry of sample builds. Run from the repository root; prints JSON.
package.path = "mods/crystalminer/?.lua;" .. package.path
local S = require("symmetry")
local L = require("lessons")
local content = require("content")

local out = { images = {}, detect = {} }
for _, a in ipairs(content.regions) do
	local r = S.region(L.region_spec(a, a.generators))
	-- A few blocks spread through the build space, including its edges and centre.
	local picks = {}
	for _, f in ipairs({ { 0, 0, 0 }, { 0.5, 0.5, 0.5 }, { 0.2, 0.7, 0.4 }, { 0.9, 0.1, 0.6 }, { 0.33, 0.0, 0.81 } }) do
		local p = {}
		for i = 1, 3 do p[i] = r.min[i] + math.floor(f[i] * (r.size[i] - 1) + 0.5) end
		picks[#picks + 1] = p
	end
	for _, p in ipairs(picks) do
		local imgs = {}
		for _, q in ipairs(S.images(r, p[1], p[2], p[3])) do
			imgs[#imgs + 1] = string.format("%d,%d,%d", q.x - r.min[1], q.y, q.z - r.min[3])
		end
		table.sort(imgs)
		out.images[#out.images + 1] = string.format('{"id":"%s","at":[%d,%d,%d],"images":["%s"]}', a.id,
			p[1] - r.min[1], p[2], p[3] - r.min[3], table.concat(imgs, '","'))
	end
end

-- Builds whose symmetry is known: each as a list of blocks "x,y,z=colour".
local builds = {
	{ "0,0,0=red" },
	{ "0,0,0=red", "1,0,0=red" },
	{ "0,0,0=red", "1,0,0=blue" },
	{ "0,0,0=red", "1,0,0=red", "0,1,0=red" },
	{ "0,0,0=red", "2,0,0=red", "1,1,0=red", "1,-1,0=red", "1,0,1=red", "1,0,-1=red" },
	{ "0,0,0=red", "1,0,0=red", "0,0,1=red", "1,0,1=red", "0,1,0=blue" },
	{ "0,0,0=red", "1,0,0=red", "2,0,0=red", "0,0,1=red" },
}
for _, b in ipairs(builds) do
	local nodes = {}
	for _, e in ipairs(b) do
		local x, y, z, c = e:match("^(-?%d+),(-?%d+),(-?%d+)=(%a+)$")
		nodes[(2 * x + 1) .. "," .. (2 * y + 1) .. "," .. (2 * z + 1)] = c
	end
	local g, entry = S.detect(nodes)
	out.detect[#out.detect + 1] = string.format('{"blocks":["%s"],"symbol":"%s","order":%d}', table.concat(b, '","'),
		entry and entry.symbol or "?", #g.ops)
end
print('{"images":[' .. table.concat(out.images, ",") .. '],"detect":[' .. table.concat(out.detect, ",") .. "]}")
