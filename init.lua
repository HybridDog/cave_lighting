local load_time_start = os.clock()

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
		for _,p2 in pairs({
			{x=pos.x+i, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y+i, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+i},
		}) do
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
	local tab_avoid = {}
	while todo[1] do
		for n,p in pairs(todo) do
			for i = -1,1 do
				for j = -1,1 do
					for k = -1,1 do
						local p2 = {x=p.x+i, y=p.y+j, z=p.z+k}
						local pstr = p2.x.." "..p2.y.." "..p2.z
						if not tab_avoid[pstr] then
							local atpos = pos_allowed(p2, maxlight, name)
							if atpos then
								tab[num] = {above=p2, under=atpos}
								tab_avoid[pstr] = true
								num = num+1
								table.insert(todo, p2)
								if max
								and num > max then
									return false
								end
							end
						end
					end
				end
			end
			todo[n] = nil
		end
	end
	return tab
end

-- lits up a cave
local function place_torches(pos, maxlight, player, name)
	local node = player:get_inventory():get_stack("main", player:get_wield_index()):get_name()
	local data = minetest.registered_nodes[node]
	if not data then
		-- support the chatcommand tool
		node = player:get_inventory():get_stack("main", player:get_wield_index()+1):get_name()
		data = minetest.registered_nodes[node]
		if not data then
			minetest.chat_send_player(name, "You need to have a node next to or as your wielded item.")
			return
		end
	end
	local nodelight = data.light_source
	if not nodelight
	or nodelight < maxlight then
		minetest.chat_send_player(name, "You need a node emitting light (enough light).")
		return
	end
	local ps = get_ps(pos, maxlight, name, 20000)
	if not ps then
		minetest.chat_send_player(name, "It doesn't seem to be dark there or the cave is too big.")
		return
	end
	local sound = data.sounds
	if sound then
		sound = sound.place
	end
	local count = 0

	--[[	-- should search for optimal places for torches
	local l1 = math.max(2*maxlight-nodelight+1, 1)
	local found = true
	while found do
		found = false
		for n,pt in pairs(ps) do
			local pos = pt.above
			local light = minetest.get_node_light(pos, 0.5) or 0
			if light == l1 then
				count = count+1
				if sound then
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

	for n,pt in pairs(ps) do
		local pos = pt.above
		local light = minetest.get_node_light(pos, 0.5) or 0
		if light <= maxlight then
			count = count+1
			if sound then
				minetest.sound_play(sound.name, {pos=pos, gain=sound.gain/count})
			end
			pt.type = "node"
			minetest.item_place_node(ItemStack(node), player, pt)
		end
	end

	return {count, data.description or node, nodelight}
end

-- searches the position the player looked at and lights the cave
local function light_cave(player, name, maxlight)
	minetest.chat_send_player(name, "lighting a cave…")

	-- search the place where the player sees a dark cave
	local pos = player:getpos()
	pos.y = pos.y+1.625
	pos = vector.round(pos)
	local dir = player:get_look_dir()
	local p2 = vector.add(pos, vector.round(vector.multiply(dir, 20)))
	local bl, pos2 = minetest.line_of_sight(pos, p2, 1)
	if bl then
		minetest.chat_send_player(name, "Could not find a node you look at.")
		return
	end

	-- if rooms with 1 node thin walls are lighted the light nodes should be placed inside the room
	local pos = pos2
	for _,c in pairs({"x", "y", "z"}) do
		dir[c] = math.sign(dir[c])
		pos[c] = pos[c]-dir[c]
		if minetest.get_node(pos).name == "air" then
			bl = true
			break
		end
		pos[c] = pos[c]+dir[c]
	end
	if not bl then
		minetest.chat_send_player(name, "There does not seem to be air near the node you looked at.")
	end

	local t = place_torches(pos, maxlight, player, name)
	if t then
		if t[1] == 0 then
			minetest.chat_send_player(name, "No nodes placed.")
			return
		end
		minetest.chat_send_player(name, t[1].." "..t[2].."s placed. (maxlight="..maxlight..", used_light="..t[3]..")")
	end
end

-- the chatcommand
minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight]",
	privs = {give=true, interact=true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local maxlight = tonumber(param) or 7
		if not player then
			return false, "Player not found"
		end
		light_cave(player, name, maxlight)
	end
})

local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[cave_lighting] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
