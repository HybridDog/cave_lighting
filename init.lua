local function inform(name, msg)
	minetest.chat_send_player(name, msg)
	minetest.log("info", "[cave_lighting] "..name..": "..msg)
end

-- tests if theres a node an e.g. torch is allowed to be placed on
local function pos_placeable(pos)
	local undernode = minetest.get_node(pos).name
	if undernode == "air" then
		return false
	end
	local data = minetest.registered_nodes[undernode]
	if not data then
		return false
	end
	if data.drawtype == "normal"
	or not data.drawtype then
		return true
	end
	return false
end

-- tests if it's a possible place for a light node
local function pos_allowed(pos, maxlight, name)
	local light = minetest.get_node_light(pos, 0.5)
	if not light
	or light > maxlight
	or minetest.get_node(pos).name ~= "air"
	or minetest.is_protected(pos, name) then
		return false
	end
	for i = -1,1,2 do
		for _,p2 in pairs{
			{x=pos.x+i, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y+i, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+i},
		} do
			if pos_placeable(p2) then
				return p2
			end
		end
	end
	return false
end

-- finds out possible places for a light node in a cave
local function get_ps(pos, maxlight, name, max)
	local tab = {}
	local num = 1

	local todo = {pos}
	local nt = 1

	local tab_avoid = {}
	while nt ~= 0 do
		local p = todo[nt]
		todo[nt] = nil
		nt = nt-1

		for i = -1,1 do
			for j = -1,1 do
				for k = -1,1 do
					local p2 = {x=p.x+i, y=p.y+j, z=p.z+k}
					local vi = minetest.hash_node_position(p2)
					if not tab_avoid[vi] then
						local atpos = pos_allowed(p2, maxlight, name)
						if atpos then
							tab[num] = {above=p2, under=atpos}
							num = num+1

							nt = nt+1
							todo[nt] = p2

							tab_avoid[vi] = true
							if max
							and num > max then
								return false
							end
						end
					end
				end
			end
		end
	end
	return tab
end

-- lits up a cave
local function place_torches(pos, maxlight, player, name)
	-- get the light_source item
	local inv = player:get_inventory()
	local wi = player:get_wield_index()
	local node = inv:get_stack("main", wi):get_name()
	local data = minetest.registered_nodes[node]
	if not data then
		-- support the chatcommand tool
		node = inv:get_stack("main", wi+1):get_name()
		data = minetest.registered_nodes[node]
		if not data then
			inform(name, "You need to have a node next to or as your wielded item.")
			return
		end
	end
	local nodelight = data.light_source
	if not nodelight
	or nodelight < maxlight then
		inform(name, "You need a node emitting light (enough light).")
		return
	end
	-- get possible positions
	local ps = get_ps(pos, maxlight, name, 200^3)
	if not ps then
		inform(name, "It doesn't seem to be dark there or the cave is too big.")
		return
	end
	local sound = data.sounds
	if sound then
		sound = sound.place
	end
	local count = 0

	-- [[	-- should search for optimal places for torches
	local l1 = math.max(2*maxlight-nodelight+1, 1)
	local found = true
	while found do
		found = false
		for n,pt in pairs(ps) do
			local pos = pt.above
			local light = minetest.get_node_light(pos, 0.5) or 0
			if light == l1 then
				count = count+1
				if sound
				and count < 50 then
					minetest.sound_play(sound.name, {pos=pos, gain=sound.gain/count})
				end
				pt.type = "node"
				minetest.item_place_node(ItemStack(node), player, pt)
				found = true
				ps[n] = nil
			elseif light > maxlight then
				ps[n] = nil
			end
		end
	end--]]

	for _,pt in pairs(ps) do
		local pos = pt.above
		local light = minetest.get_node_light(pos, 0.5) or 0
		if light <= maxlight then
			count = count+1
			if sound
			and count < 50 then
				minetest.sound_play(sound.name, {pos=pos, gain=sound.gain/count})
			end
			pt.type = "node"
			minetest.item_place_node(ItemStack(node), player, pt)
		end
	end

	return {count, data.description or node, nodelight}
end

-- gets something like pt.above, pt.under
local function get_pt_air(player, name)
	-- search the place where the player sees a dark cave
	local pos = player:getpos()
	pos.y = pos.y+1.625
	pos = vector.round(pos)
	local dir = player:get_look_dir()
	local p2 = vector.add(pos, vector.round(vector.multiply(dir, 20)))
	local bl, pos2 = minetest.line_of_sight(pos, p2, 1)
	if bl then
		inform(name, "Could not find a node you look at.")
		return
	end

	-- if rooms with 1 node thin walls are lighted the light nodes should be placed inside the room
	pos = vector.new(pos2)
	for _,c in pairs{"x", "y", "z"} do
		local v = math.sign(dir[c])
		pos[c] = pos[c]-v
		if minetest.get_node(pos).name == "air" then
			bl = true
			break
		end
		pos[c] = pos[c]+v
	end
	if not bl then
		inform(name, "There does not seem to be air near the node you looked at.")
	end
	return pos, pos2
end

-- searches the position the player looked at and lights the cave
local function light_cave(player, name, maxlight)
	inform(name, "lighting a cave…")

	local pos = get_pt_air(player, name)
	if not pos then
		return false, "no air found"
	end

	local t = place_torches(pos, maxlight, player, name)
	if t then
		if t[1] == 0 then
			return false, "No nodes placed."
		end
		return true, t[1].." "..t[2].."s placed. (maxlight="..maxlight..", used_light="..t[3]..")"
	end
end

-- the chatcommand
minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight]",
	privs = {give=true, interact=true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		return light_cave(player, name, tonumber(param) or 7)
	end
})


-- lazy torch placing
local light_making_players, timer

-- the chatcommand
minetest.register_chatcommand("auto_light_placing",{
	description = "automatically places lights",
	params = "[maxlight]",
	privs = {give=true, interact=true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		light_making_players = light_making_players or {}
		light_making_players[name] = tonumber(param) or 7
		timer = -0.5
	end
})

minetest.register_globalstep(function(dtime)
	-- abort if noone uses it
	if not light_making_players then
		return
	end

	-- abort that it doesn't shoot too often (change it if your pc runs faster)
	timer = timer+dtime
	if timer < 0.1 then
		return
	end
	timer = 0

	for name,maxlight in pairs(light_making_players) do
		local player = minetest.get_player_by_name(name)
		local pt = {type = "node"}
		pt.above, pt.under = get_pt_air(player, name)
		if pt.above
		and pos_placeable(pt.under) then
			local node = player:get_inventory():get_stack("main", player:get_wield_index()):get_name()
			local data = minetest.registered_nodes[node]
			local failed
			if not data then
				-- support the chatcommand tool
				node = player:get_inventory():get_stack("main", player:get_wield_index()+1):get_name()
				data = minetest.registered_nodes[node]
				if not data then
					inform(name, "You need to have a node next to or as your wielded item.")
					failed = true
				end
			end
			if data then
				local nodelight = data.light_source
				if not nodelight
				or nodelight < maxlight then
					inform(name, "You need a node emitting light (enough light).")
					failed = true
				end
				local light = minetest.get_node_light(pt.above, 0.5) or 0
				if light <= maxlight
				and minetest.get_node(pt.above).name == "air" then
					local sound = data.sounds
					if sound then
						sound = sound.place
					end
					if sound then
						minetest.sound_play(sound.name, {pos=pt.above, gain=sound.gain})
					end
					minetest.item_place_node(ItemStack(node), player, pt)
				end
			end
			if failed then
				light_making_players[name] = nil
				if not next(light_making_players) then
					light_making_players = nil
				end
			end
		end
	end
end)
