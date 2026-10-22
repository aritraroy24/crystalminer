local cm = crystalminer
local INFO_NAME = "crystalminer:guide_npc"
local INFO_POS = { x = 28, y = cm.GROUND_Y + 1, z = -40 }
local VISITOR_NAME = "crystalminer:museum_visitor"
local VISITOR_POSITIONS = {
	{ x = -12, y = cm.GROUND_Y + 1, z = -40,
		message = "The Workshop is west of here. Try the Try-it Pad before you visit the galleries." },
	{ x = 10, y = cm.GROUND_Y + 1, z = -20,
		message = "Gallery 1 is through the north door. Work out which operation made each copy, then try the quiz." },
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
local NPC_FORMSPEC = "crystalminer:npc"
local VISITOR_WANDER_RADIUS = 3
local VISITOR_WALK_SPEED = 0.6
local npcs_ensured = false

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
		static_save = true,
		collisionbox = { -0.3, 0, -0.3, 0.3, 1.8, 0.3 },
		visual = "cube",
		textures = {
			"info_top.png", "info_top.png",
			"info_side.png", "info_face.png",
			"info_side.png", "info_side.png",
		},
		visual_size = { x = 1, y = 2, z = 1 },
	},
	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then return end
		core.show_formspec(clicker:get_player_name(), NPC_FORMSPEC,
			"formspec_version[4]size[11,7]" ..
			"label[0.6,0.5;Information desk]" ..
			"label[0.6,1.0;I can help you find your way around the museum.]" ..
			"button[0.6,1.6;4.6,0.8;welcome;What should I do first?]" ..
			"button[5.5,1.6;4.8,0.8;galleries;Where are the galleries?]" ..
			"button[0.6,2.6;4.6,0.8;workshop;What is the Workshop?]" ..
			"button[5.5,2.6;4.8,0.8;next;What should I do next?]" ..
			"field[0.8,4.3;9.8,0.8;question;Ask a question;]" ..
			"button[3.2,5.3;4.6,0.8;ask;Ask the tutor]" ..
			"button_exit[3.2,6.2;4.6,0.6;close;Close]")
	end,
})

core.register_entity(VISITOR_NAME, {
	initial_properties = {
		physical = true,
		static_save = true,
		collisionbox = { -0.3, 0, -0.3, 0.3, 1.8, 0.3 },
		visual = "cube",
		textures = {
			"npc_side.png", "npc_side.png",
            "npc_face.png", "npc_side.png",
            "npc_side.png", "npc_side.png",
		},
		visual_size = { x = 1, y = 2, z = 1 },
	},
	on_activate = function(self, staticdata)
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
	npcs_ensured = false
	for _, object in ipairs(core.get_objects_inside_radius({ x = 0, y = 10, z = 20 }, 110)) do
		local entity = object:get_luaentity()
		if entity and (entity.name == INFO_NAME or entity.name == VISITOR_NAME) then object:remove() end
	end
end

local function ensure_entity(pos, entity_name)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 1)) do
		local entity = object:get_luaentity()
		if entity and entity.name == entity_name then return end
	end
	core.add_entity(pos, entity_name)
end

local function ensure_npcs()
	if npcs_ensured then return end
	npcs_ensured = true
	ensure_entity(INFO_POS, INFO_NAME)

	local visitors = {}
	for _, object in ipairs(core.get_objects_inside_radius({ x = 0, y = 10, z = 20 }, 110)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VISITOR_NAME then
			visitors[#visitors + 1] = object
		end
	end

	local used = {}
	for slot, visitor in ipairs(VISITOR_POSITIONS) do
		local match
		for _, object in ipairs(visitors) do
			local entity = object:get_luaentity()
			if not used[object] and entity and entity.slot == slot then
				match = object
				break
			end
		end
		if not match then
			local nearest_distance = 8
			for _, object in ipairs(visitors) do
				local distance = vector.distance(object:get_pos(), visitor)
				if not used[object] and distance < nearest_distance then
					match = object
					nearest_distance = distance
				end
			end
		end

		if match then
			used[match] = true
			local entity = match:get_luaentity()
			entity.slot = slot
			entity.home = { x = visitor.x, y = visitor.y, z = visitor.z }
			entity.message = visitor.message
			if vector.distance(match:get_pos(), visitor) > VISITOR_WANDER_RADIUS + 1 then
				match:set_pos(visitor)
			end
		else
			core.add_entity(visitor, VISITOR_NAME,
				core.serialize({ slot = slot, home = visitor }))
		end
	end

	for _, object in ipairs(visitors) do
		if not used[object] then object:remove() end
	end
end

table.insert(cm.on_clear, remove_npcs)
table.insert(cm.on_build, ensure_npcs)

core.after(0, ensure_npcs)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= NPC_FORMSPEC or fields.quit then return end
	local name = player:get_player_name()
	local quick = {
		welcome = "I am at the information desk. Start with the welcome board, then visit the Workshop or Gallery 1.",
		galleries = "The Workshop is west. Gallery 1 is north. Beyond it are Gallery 2, Gallery 3 and the Portal Hall.",
		workshop = "In the Workshop, place blocks in the glass box and use the levers to try translations, rotations, mirrors and inversions.",
		next = "Press I for your progress board, or type /tour for a guided tour. The /quiz command unlocks the next tier.",
	}
	for button, message in pairs(quick) do
		if fields[button] then
			core.chat_send_player(name, "[Information desk]: " .. message)
			return
		end
	end
	if fields.ask then
		local question = (fields.question or ""):trim()
		local ok, err = cm.ask_tutor(name, question,
			"You asked the information desk: " .. question)
		if not ok then
			core.chat_send_player(name, "[Information desk]: " .. err)
		end
	end
end)
