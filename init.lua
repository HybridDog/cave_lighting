local load_time_start = os.clock()

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
			if minetest.get_node(p2).name ~= "air" then
				return p2
			end
		end
	end
	return false
end

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

local function place_torches(pos, maxlight, player, name)
	local node = player:get_inventory():get_stack("main", player:get_wield_index()):get_name()
	local data = minetest.registered_nodes[node]
	if not data then
		node = player:get_inventory():get_stack("main", player:get_wield_index()+1):get_name()
		data = minetest.registered_nodes[node]
		if not data then
			minetest.chat_send_player(name, "You need to have a node next to or as your wielded item.")
			return
		end
	end
	local light = data.light_source
	if not light
	or light < maxlight then
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
	return count, data.description or ""
end

local function light_cave(player, name, maxlight)
	minetest.chat_send_player(name, "lighting a cave…")
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
	pos = vector.round(vector.subtract(pos2, dir))
	if minetest.get_node(pos).name ~= "air" then
		minetest.chat_send_player(name, "Something went wrong.")
		return
	end
	local count, desc = place_torches(pos, maxlight, player, name)
	if count then
		minetest.chat_send_player(name, count.." "..desc.."s placed.")
	end
end

minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight]",
	privs = {give = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local maxlight = tonumber(param) or 5
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
