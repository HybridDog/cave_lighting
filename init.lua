local path = minetest.get_modpath"cave_lighting"
local search_dfs = dofile(path .. "/fill_3d.lua")

cave_lighting = {}

local function inform(name, msg)
	minetest.chat_send_player(name, msg)
	minetest.log("info", "[cave_lighting] "..name..": "..msg)
end

-- Like minetest.get_node but also works in unloaded areas
local function get_node_loaded(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then
		return node
	end
	minetest.load_area(pos)
	return minetest.get_node(pos)
end

-- Places a node with the same effects than the player's placing
local function place_node(def, wi, stack, player, pt, inv)
	local leftover = def.on_place(stack, player, pt)
	inv:set_stack("main", wi, leftover)
	return leftover
end

-- Tests if theres a node an e.g. torch is allowed to be placed on
local function pos_placeable(pos)
	local undernode = get_node_loaded(pos).name
	if undernode == "air" then
		return false
	end
	local data = minetest.registered_nodes[undernode]
	if data
	and (data.drawtype == "normal" or not data.drawtype)
	and data.pointable and not data.buildable_to then
		return true
	end
	return false
end

local moves_touch = {
	{x = -1, y = 0, z = 0},
	{x = 1, y = 0, z = 0},
	{x = 0, y = -1, z = 0},
	{x = 0, y = 1, z = 0},
	{x = 0, y = 0, z = -1},
	{x = 0, y = 0, z = 1},
}
local moves_near = {}
for x = -1,1 do
	for y = -1,1 do
		for z = -1,1 do
			if x*x + y*y + z*z > 0 then
				moves_near[#moves_near+1] = {x = x, y = y, z = z}
			end
		end
	end
end

-- Tests if it's a possible place for a light node
local function pos_allowed(pos, maxlight, name)
	local light = minetest.get_node_light(pos, 0.5)
	if not light
	or light > maxlight
	or get_node_loaded(pos).name ~= "air"
	or minetest.is_protected(pos, name) then
		return
	end
	for k = 1, 6 do
		local p2 = vector.add(pos, moves_touch[k])
		if pos_placeable(p2) then
			return p2
		end
	end
end

-- Finds out possible places for a light node in a cave with an efficient
-- variant of Depth First Search
local function search_positions(startpos, maxlight, pname, max_positions)
	local visited = {}
	local found = {}
	local num_found = 0
	local function on_visit(pos)
		local vi = minetest.hash_node_position(pos)
		if visited[vi] then
			return false
		end
		visited[vi] = true
		if num_found > max_positions then
			return false
		end
		local under_pos = pos_allowed(pos, maxlight, pname)
		if under_pos then
			num_found = num_found+1
			found[num_found] = {under = under_pos, above = pos}
			return true
		end
		return false
	end
	on_visit(startpos)
	search_dfs(on_visit, startpos, vector.add, moves_near)
	-- Do not return the positions if the search has found too many, to avoid
	-- fragmented lighting
	return num_found <= max_positions and num_found > 0 and found
end

-- Lights up a cave
local function place_torches(pos, maxlight, player)
	-- Get the light_source item
	local inv = player:get_inventory()
	local wi = player:get_wield_index()
	local stack = inv:get_stack("main", wi)
	local node_name = stack:get_name()
	local def = minetest.registered_nodes[node_name]
	if not def then
		-- Support the chatcommand tool
		wi = wi+1
		stack = inv:get_stack("main", wi)
		node_name = stack:get_name()
		def = minetest.registered_nodes[node_name]
		if not def then
			return false,
				"You need to have a node next to or as your wielded item."
		end
	end
	local nodelight = def.light_source
	if not nodelight
	or nodelight < maxlight then
		return false, "You need a node emitting light (enough light)."
	end
	-- Get possible positions
	local ps = search_positions(pos, maxlight, name, 200^3)
	if not ps then
		return false, "It doesn't seem to be dark there or the cave is too big."
	end
	local sound = def.sounds
	if sound then
		sound = sound.place
	end
	local count = 0

	-- [[	-- should search for optimal places for torches
	-- The light depends on the manhattan distance to the light source.
	-- If for example maxlight=4 and nodelight=7 and a light stripe is
	-- (2,3,4,5,6,7), then I assume it is advisable to first put light nodes
	-- where the light is 3: (6,7,6,5,6,7)
	local l1 = math.max(maxlight - (nodelight - maxlight) + 2, 0)
	local n = #ps
	local found = true
	while found do
		found = false
		for k = n, 1, -1 do
			local pt = ps[k]
			local pos = pt.above
			local light = minetest.get_node_light(pos, 0.5) or 0
			if light == l1 then
				pt.type = "node"
				stack = place_node(def, wi, stack, player, pt, inv)
				if stack:get_name() ~= node_name then
					return false, "No remaining light nodes"
				end
				count = count+1
				if sound
				and count < 50 then
					minetest.sound_play(sound.name, {pos = pos,
						gain = sound.gain / count})
				end
				found = true
				ps[k] = ps[n]
				ps[n] = nil
				n = n-1
			elseif light > maxlight then
				ps[k] = ps[n]
				ps[n] = nil
				n = n-1
			end
		end
	end--]]

	for k = 1, n do
		local pt = ps[k]
		local pos = pt.above
		local light = minetest.get_node_light(pos, 0.5) or 0
		if light <= maxlight then
			pt.type = "node"
			stack = place_node(def, wi, stack, player, pt, inv)
			if stack:get_name() ~= node_name then
				return false, "No remaining light nodes"
			end
			count = count+1
			if sound
			and count < 50 then
				minetest.sound_play(sound.name, {pos = pos,
					gain = sound.gain / count})
			end
		end
	end

	return {count, def.description or stack:get_name(), nodelight}
end

-- Returns the camera position of the player; it does not include
-- the client-side offset, e.g. bobbing (see view_bobbing_amount)
local function get_eye_pos(player)
	local pos = vector.add(player:getpos(), player:get_eye_offset())
	pos.y = pos.y + player:get_properties().eye_height
	return pos
end

-- Returns pointed thing above and under positions for the player's view
-- and tests if a node can be placed there
local function get_pointed_target(player)
	-- Search a target node where the player would be able to place a torch
	local pos1 = get_eye_pos(player)
	local dir = player:get_look_dir()
	local pos2 = vector.add(pos1, vector.multiply(dir, 20))
	local pointed = minetest.raycast(pos1, pos2, false, true)()
	if not pointed then
		return
	end
	local def_under = minetest.registered_nodes[
		get_node_loaded(pointed.under).name]
	local def_above = minetest.registered_nodes[
		get_node_loaded(pointed.above).name]
	if not def_under or not def_above
	or not def_above.buildable_to or def_under.buildable_to then
		-- Cannot place a node here
		return
	end

	return pointed.above, pointed.under
end

function cave_lighting.light_cave(player, maxlight)
	local pos = get_pointed_target(player)
	if not pos then
		return false, "No valid position for a torch placement found"
	end

	inform(player:get_player_name(), "Lighting a cave…")
	local t, errormsg = place_torches(pos, maxlight, player)
	if not t then
		return false, errormsg
	end
	if t[1] == 0 then
		return false, "No nodes placed."
	end
	return true, ("%d \"%s\"s placed. (maxlight: %d, placed nodes' light: %d)"
		):format(t[1], t[2], maxlight, t[3])
end

-- Chatcommand to light a full cave
minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight=7]",
	privs = {give=true, interact=true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		return cave_lighting.light_cave(player, tonumber(param) or 7)
	end
})


-- Lazy torch placing

local light_making_players

function cave_lighting.enable_auto_placing(pname, maxlight)
	light_making_players = light_making_players or {}
	light_making_players[pname] = maxlight
end

function cave_lighting.disable_auto_placing(pname)
	light_making_players[pname] = nil
	if not next(light_making_players) then
		light_making_players = nil
	end
end

-- Chatcommand to automatically light the way while playing
minetest.register_chatcommand("auto_light_placing",{
	description = "automatically places lights",
	params = "[maxlight=3]",
	privs = {give=true, interact=true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		cave_lighting.enable_auto_placing(name, tonumber(param) or 3)
		return true, "Placing lights automatically"
	end
})

local function autoplace_step()
	-- Abort if noone uses it
	if not light_making_players then
		return
	end

	for pname, maxlight in pairs(light_making_players) do
		local player = minetest.get_player_by_name(pname)
		local pt = {type = "node"}
		pt.above, pt.under = get_pointed_target(player)
		if pt.above then
			local wi = player:get_wield_index()
			local inv = player:get_inventory()
			local stack = inv:get_stack("main", wi)
			local def = minetest.registered_nodes[stack:get_name()]
			local failed
			if not def then
				-- support the chatcommand tool
				wi = wi + 1
				stack = inv:get_stack("main", wi)
				def = minetest.registered_nodes[stack:get_name()]
				if not def then
					inform(pname, "You need to have a node next to or as " ..
						"your wielded item.")
					failed = true
				end
			end
			if def then
				local nodelight = def.light_source
				if not nodelight
				or nodelight < maxlight then
					inform(pname,
						"You need a node emitting light (enough light).")
					failed = true
				end
				local light = minetest.get_node_light(pt.above, 0.5) or 0
				if light <= maxlight
				and get_node_loaded(pt.above).name == "air" then
					local sound = def.sounds
					if sound then
						sound = sound.place
					end
					if sound then
						minetest.sound_play(sound.name,
							{pos = pt.above, gain = sound.gain})
					end
					place_node(def, wi, stack, player, pt, inv)
				end
			end
			if failed then
				cave_lighting.disable_auto_placing(pname)
			end
		end
	end
end

local function autoplace()
	autoplace_step()
	minetest.after(0.1, autoplace)
end
autoplace()
