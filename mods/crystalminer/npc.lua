local cm = crystalminer
local INFO_NAME = "crystalminer:guide_npc"
local INFO_POS = { x = 28, y = cm.GROUND_Y + 1, z = -40 }
local VISITOR_NAME = "crystalminer:museum_visitor"
local VISITOR_POSITIONS = {
	-- Not at x = -12, z = -40: that is the middle of the fluorite sculpture's plinth (sculptures.lua).
	{ x = -6, y = cm.GROUND_Y + 1, z = -45,
		message = "The Workshop is west of here. Try the Try-it Pad before you visit the galleries." },
	{ x = 10, y = cm.GROUND_Y + 1, z = -20,
		message = "This is Gallery 1. Work out which operation made each copy, then try the quiz." },
	{ x = -30, y = cm.GROUND_Y + 1, z = -40,
		message = "The Workshop has four levers: slide, turn, mirror and send a shape through its centre." },
	{ x = 30, y = cm.GROUND_Y + 1, z = -40,
		message = "The information desk can point you to the galleries, the Workshop and the guided tour." },
	{ x = -30, y = cm.GROUND_Y + 1, z = -15,
		message = "Look closely at the copies in Gallery 1. Can you name the symmetry operation that made each one?" },
	{ x = 30, y = cm.GROUND_Y + 1, z = -15,
		message = "I am collecting examples of translation, rotation, reflection and inversion. Which is your favourite?" },
	{ x = -35, y = cm.GROUND_Y + 1, z = 10,
		message = "Gallery 2 tells the story of how people discovered crystal symmetry. Read the timeline from south to north." },
	{ x = 35, y = cm.GROUND_Y + 1, z = 10,
		message = "After Gallery 2, visit Gallery 3 to see crystal models, then continue north to the Portal Hall." },
}
local DESK_GREETING = "I can help you find your way around the museum. Ask Prism, the AI tutor, anything."
local VISITOR_WANDER_RADIUS = 3
local VISITOR_WALK_SPEED = 0.6
-- The NPCs are not saved in the map (static_save = false): they exist only while a player is near
-- and are added again when one comes back. Saved NPCs were added again at every server start and
-- piled up (one more information-desk NPC and eight more visitors per restart).
local spawning = false     -- true only while this file adds an NPC; anything else activating is removed
local live = {}            -- "info" or a visitor slot -> its ObjectRef
local world_built = false

local function choose_visitor_target(self)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * VISITOR_WANDER_RADIUS
	self.target = {
		x = self.home.x + math.cos(angle) * distance,
		y = self.home.y,
		z = self.home.z + math.sin(angle) * distance,
	}
	self.target_time = 3 + math.random() * 5
end

local function visitor_message_at(pos)
	for _, visitor in ipairs(VISITOR_POSITIONS) do
		if vector.distance(pos, visitor) <= 1 then return visitor.message end
	end
	return "Have you visited the Workshop yet?"
end

core.register_entity(INFO_NAME, {
	initial_properties = {
		physical = true,
		static_save = false,
		collisionbox = { -0.3, 0, -0.3, 0.3, 1.8, 0.3 },
		visual = "cube",
		textures = {
			"crystalminer_npc_desk_top.png", "crystalminer_npc_desk_top.png",
			"crystalminer_npc_desk_side.png", "crystalminer_npc_desk_face.png",
			"crystalminer_npc_desk_side.png", "crystalminer_npc_desk_side.png",
		},
		visual_size = { x = 1, y = 2, z = 1 },
	},
	on_activate = function(self)
		-- One saved in the map by an earlier version: remove it (this file adds the current one).
		if not spawning then self.object:remove() end
	end,
	-- The desk NPC greets the visitor and opens Prism's chat (tutor_window.lua), the one window for questions.
	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		core.chat_send_player(name, "[Information desk]: " .. DESK_GREETING)
		cm.open_tutor(name)
	end,
})

core.register_entity(VISITOR_NAME, {
	initial_properties = {
		physical = true,
		static_save = false,
		collisionbox = { -0.3, 0, -0.3, 0.3, 1.8, 0.3 },
		visual = "cube",
		textures = {
			"crystalminer_npc_visitor_side.png", "crystalminer_npc_visitor_side.png",
            "crystalminer_npc_visitor_face.png", "crystalminer_npc_visitor_side.png",
            "crystalminer_npc_visitor_side.png", "crystalminer_npc_visitor_side.png",
		},
		visual_size = { x = 1, y = 2, z = 1 },
	},
	on_activate = function(self, staticdata)
		if not spawning then self.object:remove(); return end
		local data = core.deserialize(staticdata or "")
		local pos = self.object:get_pos()
		self.slot = data and data.slot
		self.home = data and data.home or { x = pos.x, y = pos.y, z = pos.z }
		self.target = nil
		self.target_time = 0
		self.message = self.slot and VISITOR_POSITIONS[self.slot].message or visitor_message_at(pos)
	end,
	get_staticdata = function(self)
		return core.serialize({ slot = self.slot, home = self.home })
	end,
	on_step = function(self, dtime)
		self.object:set_acceleration({ x = 0, y = 0, z = 0 })
		self.target_time = self.target_time - dtime
		local pos = self.object:get_pos()
		if not self.target or self.target_time <= 0 or vector.distance(pos, self.target) < 0.4 then
			choose_visitor_target(self)
		end

		local dx = self.target.x - pos.x
		local dz = self.target.z - pos.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < 0.1 then
			self.object:set_velocity({ x = 0, y = 0, z = 0 })
			return
		end

		self.object:set_velocity({
			x = dx / distance * VISITOR_WALK_SPEED,
			y = 0,
			z = dz / distance * VISITOR_WALK_SPEED,
		})
		self.object:set_yaw(math.atan2(-dx, dz))
	end,
	on_rightclick = function(self, clicker)
		if clicker and clicker:is_player() then
			local message = self.slot and VISITOR_POSITIONS[self.slot].message
				or visitor_message_at(self.object:get_pos())
			core.chat_send_player(clicker:get_player_name(), "[Visitor]: " .. message)
		end
	end,
})

local function remove_npcs()
	for _, object in ipairs(core.get_objects_inside_radius({ x = 0, y = 10, z = 20 }, 110)) do
		local entity = object:get_luaentity()
		if entity and (entity.name == INFO_NAME or entity.name == VISITOR_NAME) then object:remove() end
	end
	live = {}
end

local function alive(object) return object ~= nil and object:get_pos() ~= nil end

-- A player this close is inside the active-block range (active_block_range map blocks, 4 by
-- default), so an NPC added for them stays active.
local NEAR = math.max(8, ((tonumber(core.settings:get("active_block_range")) or 4) - 2) * 16)
local function player_near(pos)
	for _, player in ipairs(core.get_connected_players()) do
		local p = player:get_pos()
		if p and vector.distance(p, pos) <= NEAR then return true end
	end
	return false
end

local function spawn(key, pos, entity_name, staticdata)
	spawning = true
	local object = core.add_entity(pos, entity_name, staticdata)
	spawning = false
	live[key] = object
end

--- Adds each NPC that is missing and has a player near its place (or every missing one with always).
local function ensure_npcs(always)
	if not world_built then return end
	if not alive(live.info) and (always or player_near(INFO_POS)) then spawn("info", INFO_POS, INFO_NAME) end
	for slot, visitor in ipairs(VISITOR_POSITIONS) do
		local home = { x = visitor.x, y = visitor.y, z = visitor.z }
		if not alive(live[slot]) and (always or player_near(home)) then
			spawn(slot, home, VISITOR_NAME, core.serialize({ slot = slot, home = home }))
		end
	end
end
cm.npc_refresh = ensure_npcs
cm.npc_places = { INFO_POS }
for _, visitor in ipairs(VISITOR_POSITIONS) do cm.npc_places[#cm.npc_places + 1] = visitor end

table.insert(cm.on_clear, remove_npcs)
table.insert(cm.on_build, function() world_built = true; ensure_npcs() end)
cm.when_ready(function() world_built = true end)

local npc_timer = 0
core.register_globalstep(function(dtime)
	npc_timer = npc_timer + dtime
	if npc_timer < 2 then return end
	npc_timer = 0
	ensure_npcs()
end)
